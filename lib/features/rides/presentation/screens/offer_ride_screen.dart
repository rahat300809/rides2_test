import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/map/presentation/screens/full_screen_commute_map_screen.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';

class OfferRideScreen extends ConsumerStatefulWidget {
  final VoidCallback onRidePublished;
  final String? initialOrigin;
  final String? initialDestination;
  final DateTime? initialTime;

  const OfferRideScreen({
    super.key,
    required this.onRidePublished,
    this.initialOrigin,
    this.initialDestination,
    this.initialTime,
  });

  @override
  ConsumerState<OfferRideScreen> createState() => _OfferRideScreenState();
}

class _OfferRideScreenState extends ConsumerState<OfferRideScreen> {
  int _currentStep = 0; // 0: Route & Schedule, 1: Map Preview & Fare Setup

  late TextEditingController _originController;
  late TextEditingController _destinationController;
  final TextEditingController _fareController = TextEditingController(text: '50');

  GoogleMapController? _offerMapController;
  LatLng _originLatLng = const LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng);
  LatLng _destinationLatLng = const LatLng(23.8710, 90.3800);
  RouteSuggestion? _routeSuggestion;
  Set<Polyline> _previewPolylines = {};
  Set<Marker> _markers = {};
  bool _isLoadingRoute = false;

  bool _isLocatingGps = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _departureTime = const TimeOfDay(hour: 16, minute: 30);
  bool _isNow = true;
  bool _hasPassengerHelmet = true;
  bool _isPublishing = false;
  bool _isBikeReady = true;

  String _bikeModel = 'Yamaha FZ-X';
  String _bikePlate = 'Dhaka Metro-HA 24-8891';
  String _bikeColor = 'Black Metallic';

  // Live Location Autocomplete Suggestions
  List<LocationSearchResult> _locationSuggestions = [];
  bool _showSuggestions = false;
  String _activeSearchField = ''; // 'origin' or 'destination'
  Timer? _searchDebounceTimer;

  final List<String> _quickDestinations = [
    'Mirpur 10',
    'Uttara North',
    'Dhaka University',
    'Motijheel',
    'Dhanmondi',
    'Farmgate',
    'ECB Chattar',
    'Savar',
  ];

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(
      text: widget.initialOrigin ?? 'DIU Smart City, Ashulia',
    );
    _destinationController = TextEditingController(
      text: widget.initialDestination ?? 'Uttara Sector 10',
    );

    if (widget.initialTime != null) {
      _departureTime = TimeOfDay.fromDateTime(widget.initialTime!);
      _isNow = false;
    }

    _loadSavedMotoConfig();
    _updateRealRoadRoute();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final configured = await MotorcycleConfigDialog.isConfigured(ref);
      if (mounted) {
        setState(() => _isBikeReady = configured);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _fareController.dispose();
    super.dispose();
  }

  void _onLocationQueryChanged(String query, String field) {
    _activeSearchField = field;
    _searchDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      setState(() {
        _locationSuggestions = LocationSearchService.campusLandmarks.take(6).toList();
        _showSuggestions = true;
      });
      return;
    }

    // 0ms instant local suggestion matching
    final instantMatches = LocationSearchService.getLocalMatches(clean);
    setState(() {
      _locationSuggestions = instantMatches;
      _showSuggestions = instantMatches.isNotEmpty;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final results = await LocationSearchService.search(clean);
      if (mounted && _activeSearchField == field && results.isNotEmpty) {
        setState(() {
          final seen = <String>{};
          _locationSuggestions = [...instantMatches, ...results].where((e) => seen.add(e.title)).toList();
          _showSuggestions = _locationSuggestions.isNotEmpty;
        });
      }
    });
  }

  void _selectLocationSuggestion(LocationSearchResult loc) {
    if (_activeSearchField == 'origin') {
      _originController.text = loc.title;
      _originLatLng = loc.latLng;
    } else {
      _destinationController.text = loc.title;
      _destinationLatLng = loc.latLng;
    }
    setState(() {
      _showSuggestions = false;
      _locationSuggestions = [];
    });
    _updateRealRoadRoute();
  }

  Future<bool> _isBikeConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString('rider_moto_model');
    final plate = prefs.getString('rider_moto_plate');
    if (model != null && model.trim().isNotEmpty && plate != null && plate.trim().isNotEmpty) {
      return true;
    }
    final user = ref.read(authNotifierProvider).user;
    if (user?.vehicleInfo != null && user!.vehicleInfo!.trim().isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<void> _checkMotorcycleSetup() async {
    final configured = await _isBikeConfigured();
    if (configured) {
      if (mounted && !_isBikeReady) setState(() => _isBikeReady = true);
      return;
    }
    if (!mounted) return;
    setState(() => _isBikeReady = false);

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 28),
            SizedBox(width: 10),
            Text('Motorcycle Setup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: const Text(
          'To offer campus rides, please configure your bike model and license plate number once. After setup, you will not be asked again!',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setup Motorcycle Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (proceed != true) {
      if (mounted) {
        setState(() => _isBikeReady = false);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
      return;
    }

    if (mounted) {
      await MotorcycleConfigDialog.show(
        context: context,
        onSaved: (m, p, c, h) {
          if (mounted) {
            setState(() {
              _bikeModel = m;
              _bikePlate = p;
              _bikeColor = c;
              _hasPassengerHelmet = h;
              _isBikeReady = true;
            });
          }
        },
      );

      final recheck = await _isBikeConfigured();
      if (mounted) {
        setState(() => _isBikeReady = recheck);
        if (!recheck && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _loadSavedMotoConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = prefs.getString('rider_moto_model');
      final plate = prefs.getString('rider_moto_plate');
      final color = prefs.getString('rider_moto_color');
      final helmet = prefs.getBool('rider_moto_helmet');
      final user = ref.read(authNotifierProvider).user;

      if (mounted) {
        setState(() {
          if (model != null && model.isNotEmpty) {
            _bikeModel = model;
          } else if (user?.vehicleInfo != null && user!.vehicleInfo!.isNotEmpty) {
            final vInfo = user.vehicleInfo!;
            final match = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(vInfo);
            if (match != null) {
              _bikeModel = match.group(1) ?? _bikeModel;
              _bikePlate = match.group(2) ?? _bikePlate;
            } else {
              _bikeModel = vInfo;
            }
          }
          if (plate != null && plate.isNotEmpty) _bikePlate = plate;
          if (color != null && color.isNotEmpty) _bikeColor = color;
          if (helmet != null) _hasPassengerHelmet = helmet;
        });
      }
    } catch (_) {}
  }

  Future<void> _updateRealRoadRoute() async {
    setState(() => _isLoadingRoute = true);

    _originLatLng = LocationSearchService.lookupCoordinates(_originController.text.trim());
    _destinationLatLng = LocationSearchService.lookupCoordinates(_destinationController.text.trim());

    final route = await LocationSearchService.getRoute(_originLatLng, _destinationLatLng);

    if (mounted) {
      final dist = route.distanceKm;
      final suggested = (30 + (dist * 2.8)).round();
      final roundedFare = (suggested / 5).round() * 5;
      _fareController.text = roundedFare.clamp(30, 200).toString();

      setState(() {
        _routeSuggestion = route;
        _isLoadingRoute = false;
        _markers = {
          Marker(
            markerId: const MarkerId('offer_pickup'),
            position: _originLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup: ${_originController.text}'),
          ),
          Marker(
            markerId: const MarkerId('offer_dest'),
            position: _destinationLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: 'Destination: ${_destinationController.text}'),
          ),
        };
        _previewPolylines = {
          Polyline(
            polylineId: const PolylineId('offer_preview_route_casing'),
            points: route.polylinePoints,
            color: const Color(0xFFB23B00),
            width: 6,
          ),
          Polyline(
            polylineId: const PolylineId('offer_preview_route'),
            points: route.polylinePoints,
            color: const Color(0xFFE65100),
            width: 4,
          ),
        };
      });

      _offerMapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_destinationLatLng, 12.5),
      );
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLocatingGps = true);
    HapticFeedback.lightImpact();
    try {
      final name = await GpsLocationService.getReadableCurrentLocationName();
      final coords = await GpsLocationService.getAccurateCurrentCoordinates();
      if (mounted) {
        setState(() {
          _originController.text = name;
          _originLatLng = coords;
        });
        _updateRealRoadRoute();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Origin set to $name')),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _originController.text = GpsLocationService.defaultCampusName;
          _originLatLng = const LatLng(GpsLocationService.defaultCampusLat, GpsLocationService.defaultCampusLng);
        });
      }
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departureTime,
      helpText: 'SELECT DEPARTURE TIME',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF141416),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _departureTime = picked;
        _isNow = false;
      });
    }
  }

  void _adjustFare(int delta) {
    HapticFeedback.selectionClick();
    final cur = int.tryParse(_fareController.text.trim()) ?? 50;
    final next = (cur + delta).clamp(20, 300);
    setState(() {
      _fareController.text = next.toString();
    });
  }

  void _proceedToStep2() {
    final origin = _originController.text.trim();
    final dest = _destinationController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both pickup and destination locations.'),
          backgroundColor: Color(0xFFE65100),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    _updateRealRoadRoute();
    setState(() => _currentStep = 1);
  }

  Future<void> _publishRide() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'publish or offer a ride')) return;

    final configured = await _isBikeConfigured();
    if (!configured) {
      if (mounted) await _checkMotorcycleSetup();
      final recheck = await _isBikeConfigured();
      if (!recheck) return;
    }
    final origin = _originController.text.trim();
    final dest = _destinationController.text.trim();
    final fare = double.tryParse(_fareController.text.trim()) ?? 50.0;

    if (!mounted) return;
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify both origin and destination.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (origin.toLowerCase() == dest.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Origin and destination cannot be the same!'), backgroundColor: Colors.red),
      );
      return;
    }
    if (fare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fare per seat must be greater than zero.'), backgroundColor: Colors.red),
      );
      return;
    }
    final departureDateTime = _isNow
        ? DateTime.now()
        : DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _departureTime.hour,
            _departureTime.minute,
          );

    if (!_isNow && departureDateTime.isBefore(DateTime.now().subtract(const Duration(minutes: 60)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Departure time cannot be more than 1 hour in the past!'), backgroundColor: Colors.red),
      );
      return;
    }

    final bikeOk = await MotorcycleConfigDialog.isConfigured(ref);
    if (!bikeOk) {
      if (mounted) {
        final setupOk = await MotorcycleConfigDialog.ensureConfigured(context, ref);
        if (!setupOk) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot publish ride: Motorcycle setup is required!'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        await _loadSavedMotoConfig();
      } else {
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isPublishing = true);
    HapticFeedback.mediumImpact();

    final vehicle = VehicleModel(
      id: 'v_rider_moto',
      type: VehicleType.bike,
      modelName: _bikeModel,
      color: _bikeColor,
      licensePlate: _bikePlate,
      hasAc: false,
      hasPassengerHelmet: _hasPassengerHelmet,
      isSmokeFree: true,
      hasPhoneCharger: true,
      hasLuggageSpace: false,
    );

    final currentUser = ref.read(authNotifierProvider).user;

    try {
      final createdRide = await ref.read(ridesRepositoryProvider).createRide(
            driverId: currentUser?.id,
            driverName: currentUser?.name ?? 'DIU Student Driver',
            driverPhone: currentUser?.phone,
            driverDepartment: currentUser?.department ?? 'CSE',
            originName: origin,
            originLat: _originLatLng.latitude,
            originLng: _originLatLng.longitude,
            destinationName: dest,
            destinationLat: _destinationLatLng.latitude,
            destinationLng: _destinationLatLng.longitude,
            departureTime: departureDateTime,
            vehicle: vehicle,
            availableSeats: 1,
            farePerSeat: fare,
            isFemaleOnly: false,
          );

      if (currentUser != null) {
        ref.read(notificationsProvider.notifier).notifyDriverPublishedRide(
              rideId: createdRide.id,
              origin: origin,
              destination: dest,
              departureTime: departureDateTime,
              fare: fare,
            );
      }

      ref.invalidate(allAvailableRidesProvider);
      ref.invalidate(allSystemRidesProvider);
      ref.invalidate(myPostedRidesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Shared Ride Published! Visible to all DIU students ✓',
                    style: AppTypography.bodyMdMedium.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        widget.onRidePublished();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish ride: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBikeReady) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'Motorcycle Setup Required',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Color(0xFF0F172A)),
          ),
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0F172A), size: 19),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.two_wheeler, size: 40, color: Color(0xFFE65100)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Motorcycle Setup Required',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To offer campus peer rides, please set up your motorcycle model and license plate number once.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    await MotorcycleConfigDialog.show(
                      context: context,
                      onSaved: (m, p, c, h) {
                        if (mounted) {
                          setState(() {
                            _bikeModel = m;
                            _bikePlate = p;
                            _bikeColor = c;
                            _hasPassengerHelmet = h;
                            _isBikeReady = true;
                          });
                        }
                      },
                    );
                    final recheck = await _isBikeConfigured();
                    if (recheck && mounted) {
                      setState(() => _isBikeReady = true);
                    }
                  },
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Configure Motorcycle Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: _currentStep == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0F172A), size: 19),
                onPressed: () => setState(() => _currentStep = 0),
              )
            : const Icon(Icons.two_wheeler, color: Color(0xFFE65100)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentStep == 0 ? 'Offer a Campus Ride' : 'Route & Fare Confirmation',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Color(0xFF0F172A)),
            ),
            Text(
              _currentStep == 0 ? 'Step 1 of 2: Set route & time' : 'Step 2 of 2: Map, km, time & fare',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Step ${_currentStep + 1}/2',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFFE65100)),
            ),
          ),
        ],
      ),
      body: _currentStep == 0 ? _buildStep0RouteAndSchedule() : _buildStep1MapAndFare(),
    );
  }

  // STEP 1: Commute Route & Departure Time (Matches Homepage Clean UI)
  Widget _buildStep0RouteAndSchedule() {
    return ListView(
      padding: const EdgeInsets.all(18),
      physics: const BouncingScrollPhysics(),
      children: [
        // Driver Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE65100), Color(0xFFFF9800)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE65100).withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.two_wheeler, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biker Corridor Commute',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    Text(
                      'Peer carpool: Share motorcycle fuel & travel safely',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Route Inputs Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pickup & Destination Locations',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),

              // From Row
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _originController,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)),
                      onTap: () => _onLocationQueryChanged(_originController.text, 'origin'),
                      onChanged: (val) => _onLocationQueryChanged(val, 'origin'),
                      decoration: const InputDecoration(
                        hintText: 'Where from? (Pickup point)',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isLocatingGps
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)))
                        : const Icon(Icons.my_location, size: 19, color: Color(0xFF10B981)),
                    onPressed: _fetchCurrentLocation,
                    tooltip: 'Current GPS',
                  ),
                ],
              ),

              const Divider(color: Color(0xFFE2E8F0), height: 12),

              // To Row
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFFE65100), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _destinationController,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)),
                      onTap: () => _onLocationQueryChanged(_destinationController.text, 'destination'),
                      onChanged: (val) => _onLocationQueryChanged(val, 'destination'),
                      decoration: const InputDecoration(
                        hintText: 'Where to? (Destination route)',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                      onSubmitted: (_) => _proceedToStep2(),
                    ),
                  ),
                  if (_destinationController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _destinationController.clear();
                        _onLocationQueryChanged('', 'destination');
                        setState(() {});
                      },
                    ),
                ],
              ),

              // Autocomplete suggestions popup for Origin or Destination
              if (_showSuggestions && _locationSuggestions.isNotEmpty) ...[
                const Divider(color: Color(0xFFE2E8F0), height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Matching ${_activeSearchField == 'origin' ? 'Pickups' : 'Destinations'}:',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showSuggestions = false),
                      child: const Text('Hide', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _locationSuggestions.take(6).length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (ctx, i) {
                      final item = _locationSuggestions[i];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: item.category == 'metro'
                                ? const Color(0xFFE0F2FE)
                                : (item.category == 'campus' ? const Color(0xFFFFF3E0) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            item.category == 'metro'
                                ? Icons.directions_subway
                                : (item.category == 'campus' ? Icons.school : Icons.place),
                            size: 16,
                            color: item.category == 'metro'
                                ? const Color(0xFF0284C7)
                                : (item.category == 'campus' ? const Color(0xFFE65100) : const Color(0xFF64748B)),
                          ),
                        ),
                        title: Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _selectLocationSuggestion(item),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Departure Time Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Departure Schedule',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isNow = true;
                          _selectedDate = DateTime.now();
                          _departureTime = TimeOfDay.now();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isNow ? const Color(0xFFE65100) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, size: 18, color: _isNow ? Colors.white : const Color(0xFF475569)),
                            const SizedBox(width: 6),
                            Text(
                              'Leaving Now',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _isNow ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isNow ? const Color(0xFFE65100) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.schedule, size: 18, color: !_isNow ? Colors.white : const Color(0xFF475569)),
                            const SizedBox(width: 6),
                            Text(
                              !_isNow
                                  ? '${_departureTime.hourOfPeriod == 0 ? 12 : _departureTime.hourOfPeriod}:${_departureTime.minute.toString().padLeft(2, '0')} ${_departureTime.period == DayPeriod.am ? 'AM' : 'PM'}'
                                  : 'Schedule Time',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !_isNow ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Corridor Chips
        const Text(
          'Popular Campus Routes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickDestinations.map((dest) {
            final isSel = _destinationController.text.trim().toLowerCase() == dest.toLowerCase();
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _destinationController.text = dest;
                  _destinationLatLng = LocationSearchService.lookupCoordinates(dest);
                  _showSuggestions = false;
                });
                _updateRealRoadRoute();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFFE65100).withOpacity(0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSel ? const Color(0xFFE65100) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.near_me_outlined, size: 13, color: isSel ? const Color(0xFFE65100) : const Color(0xFF64748B)),
                    const SizedBox(width: 5),
                    Text(
                      dest,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        color: isSel ? const Color(0xFFE65100) : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Next Button ->
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _proceedToStep2,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: const Text(
              'Review Route Map & Set Fare →',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.2),
            ),
          ),
        ),
      ],
    );
  }

  // STEP 2: Route Map, Km, Estimated Time & Fare Setup
  Widget _buildStep1MapAndFare() {
    final distText = _routeSuggestion != null
        ? '${_routeSuggestion!.distanceKm.toStringAsFixed(1)} km • ${_routeSuggestion!.durationMinutes} mins'
        : 'Calculating real road route...';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            physics: const BouncingScrollPhysics(),
            children: [
              // 1. Google Map Route Preview (Interactive, Eager Scroll & Zoom Enabled)
              Container(
                height: 270,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: _originLatLng, zoom: 12),
                        onMapCreated: (ctrl) {
                          _offerMapController = ctrl;
                          if (_routeSuggestion != null) {
                            _offerMapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(_destinationLatLng, 12.5),
                            );
                          }
                        },
                        polylines: _previewPolylines,
                        markers: _markers,
                        myLocationEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: false,
                        scrollGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                      ),
                      if (_isLoadingRoute)
                        Container(
                          color: Colors.white.withOpacity(0.7),
                          child: const Center(
                            child: CircularProgressIndicator(color: Color(0xFFE65100)),
                          ),
                        ),
                      // Top-Right: Fullscreen Map View
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FullScreenCommuteMapScreen(
                                    initialDestination: _destinationLatLng,
                                    initialDestinationName: _destinationController.text,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen, size: 16, color: Color(0xFF0F172A)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Full Map',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Overlay Route Info Banner
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withOpacity(0.88),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.two_wheeler, color: Color(0xFFFFA000), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  distText,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. Route Corridor Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                        Container(width: 2, height: 26, color: const Color(0xFFCBD5E1)),
                        Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE65100), shape: BoxShape.circle)),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _originController.text,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _destinationController.text,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 3. Student Fare Setup
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seat Fare for Passenger (৳)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Standard student fuel-share contribution',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        IconButton.filled(
                          onPressed: () => _adjustFare(-5),
                          icon: const Icon(Icons.remove, size: 18),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: const Color(0xFF1E293B)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _fareController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
                            decoration: InputDecoration(
                              prefixText: '৳ ',
                              prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                              filled: true,
                              fillColor: const Color(0xFFFFF8E1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFFFD8A8)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFFFD8A8)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: () => _adjustFare(5),
                          icon: const Icon(Icons.add, size: 18),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: const Color(0xFF1E293B)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Quick Fare Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [40, 50, 60, 70, 80].map((f) {
                        final isSel = _fareController.text == f.toString();
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _fareController.text = f.toString());
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFE65100) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '৳$f',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSel ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 4. Passenger Helmet Toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sports_motorsports_rounded, color: Color(0xFFE65100), size: 22),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Passenger Helmet Provided',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            Text(
                              'Compulsory DIU campus safety standard',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: _hasPassengerHelmet,
                      activeColor: const Color(0xFFE65100),
                      onChanged: (val) => setState(() => _hasPassengerHelmet = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 5. Registered Bike Details (Read-only from Profile - no editable name fields)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.two_wheeler, color: Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_bikeModel • $_bikeColor',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                          ),
                          Text(
                            'Plate: $_bikePlate • Configured in Profile',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),

        // Bottom Bar CTA
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isPublishing ? null : _publishRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isPublishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isPublishing ? 'Publishing Shared Ride...' : 'Publish Shared Ride to DIU Campus',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, letterSpacing: 0.2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
