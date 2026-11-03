import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/map/presentation/screens/full_screen_commute_map_screen.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';

class RiderRouteFareSetupSheet extends ConsumerStatefulWidget {
  final String originName;
  final String destinationName;
  final DateTime departureTime;
  final VoidCallback? onPublished;

  const RiderRouteFareSetupSheet({
    super.key,
    required this.originName,
    required this.destinationName,
    required this.departureTime,
    this.onPublished,
  });

  static Future<void> show(
    BuildContext context, {
    required String originName,
    required String destinationName,
    required DateTime departureTime,
    VoidCallback? onPublished,
    VoidCallback? onRidePublished,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RiderRouteFareSetupSheet(
        originName: originName,
        destinationName: destinationName,
        departureTime: departureTime,
        onPublished: onRidePublished ?? onPublished,
      ),
    );
  }

  @override
  ConsumerState<RiderRouteFareSetupSheet> createState() => _RiderRouteFareSetupSheetState();
}

class _RiderRouteFareSetupSheetState extends ConsumerState<RiderRouteFareSetupSheet> {
  final TextEditingController _fareController = TextEditingController(text: '50');
  GoogleMapController? _mapController;

  LatLng _originLatLng = const LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng);
  LatLng _destLatLng = const LatLng(23.8710, 90.3800);
  RouteSuggestion? _routeSuggestion;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _isLoadingRoute = true;
  bool _isPublishing = false;
  bool _hasPassengerHelmet = true;

  String _bikeModel = 'Yamaha FZ-X';
  String _bikePlate = 'Dhaka Metro-HA 24-8891';
  String _bikeColor = 'Black Metallic';

  @override
  void initState() {
    super.initState();
    _loadProfileBikeDetails();
    _resolveLocationsAndRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final configured = await MotorcycleConfigDialog.isConfigured(ref);
      if (!configured && mounted) {
        final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
        if (!ok && mounted) {
          Navigator.of(context).pop();
        } else if (mounted) {
          _loadProfileBikeDetails();
        }
      }
    });
  }

  @override
  void dispose() {
    _fareController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileBikeDetails() async {
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
              _bikeModel = match.group(1) ?? '';
              _bikePlate = match.group(2) ?? '';
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

  Future<void> _resolveLocationsAndRoute() async {
    setState(() => _isLoadingRoute = true);

    // Geocode or match known points
    _originLatLng = LocationSearchService.lookupCoordinates(widget.originName);
    _destLatLng = LocationSearchService.lookupCoordinates(widget.destinationName);

    final route = await LocationSearchService.getRoute(_originLatLng, _destLatLng);

    if (mounted) {
      // Calculate suggested fare: base 35 TK + approx 2.5 TK per km
      final dist = route.distanceKm;
      final suggested = (30 + (dist * 2.8)).round();
      final roundedFare = (suggested / 5).round() * 5; // Round to nearest 5
      _fareController.text = roundedFare.clamp(30, 200).toString();

      setState(() {
        _routeSuggestion = route;
        _isLoadingRoute = false;
        _markers = {
          Marker(
            markerId: const MarkerId('origin_marker'),
            position: _originLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup: ${widget.originName}'),
          ),
          Marker(
            markerId: const MarkerId('dest_marker'),
            position: _destLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: 'Destination: ${widget.destinationName}'),
          ),
        };
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route_casing'),
            points: route.polylinePoints,
            color: const Color(0xFFB23B00),
            width: 6,
          ),
          Polyline(
            polylineId: const PolylineId('route_main'),
            points: route.polylinePoints,
            color: const Color(0xFFE65100),
            width: 4,
          ),
        };
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              _originLatLng.latitude < _destLatLng.latitude ? _originLatLng.latitude : _destLatLng.latitude,
              _originLatLng.longitude < _destLatLng.longitude ? _originLatLng.longitude : _destLatLng.longitude,
            ),
            northeast: LatLng(
              _originLatLng.latitude > _destLatLng.latitude ? _originLatLng.latitude : _destLatLng.latitude,
              _originLatLng.longitude > _destLatLng.longitude ? _originLatLng.longitude : _destLatLng.longitude,
            ),
          ),
          48,
        ),
      );
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

  Future<void> _publish() async {
    final fare = double.tryParse(_fareController.text.trim()) ?? 50.0;
    final user = ref.read(authNotifierProvider).user;

    final bikeOk = await MotorcycleConfigDialog.ensureConfigured(context, ref);
    if (!bikeOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot publish ride: Motorcycle setup is required!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    await _loadProfileBikeDetails();

    if (!mounted) return;
    setState(() => _isPublishing = true);
    HapticFeedback.mediumImpact();

    final vehicle = VehicleModel(
      id: 'v_${DateTime.now().millisecondsSinceEpoch}',
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

    try {
      final createdRide = await ref.read(ridesRepositoryProvider).createRide(
            driverId: user?.id,
            driverName: user?.name ?? 'DIU Student Driver',
            driverPhone: user?.phone,
            driverDepartment: user?.department ?? 'CSE',
            originName: widget.originName,
            originLat: _originLatLng.latitude,
            originLng: _originLatLng.longitude,
            destinationName: widget.destinationName,
            destinationLat: _destLatLng.latitude,
            destinationLng: _destLatLng.longitude,
            departureTime: widget.departureTime,
            vehicle: vehicle,
            availableSeats: 1,
            farePerSeat: fare,
            isFemaleOnly: false,
          );

      if (user != null) {
        ref.read(notificationsProvider.notifier).notifyDriverPublishedRide(
              rideId: createdRide.id,
              origin: widget.originName,
              destination: widget.destinationName,
              departureTime: widget.departureTime,
              fare: fare,
            );
      }

      ref.invalidate(allAvailableRidesProvider);
      ref.invalidate(allSystemRidesProvider);
      ref.invalidate(myPostedRidesProvider);

      if (mounted) {
        Navigator.of(context).pop();
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
                    'Shared ride published! Peers on ${widget.destinationName} corridor can now book.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
        widget.onPublished?.call();
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
    final distText = _routeSuggestion != null
        ? '${_routeSuggestion!.distanceKm.toStringAsFixed(1)} km • ${_routeSuggestion!.durationMinutes} mins'
        : 'Calculating route...';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Title & Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Route Preview & Fare Setup',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      'Step 2 of 2: Confirm road corridor & passenger fare',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // 1. Google Map Route Preview (Interactive & Eager Scrolling)
                Container(
                  height: 260,
                  decoration: BoxDecoration(
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(target: _originLatLng, zoom: 12),
                          onMapCreated: (ctrl) {
                            _mapController = ctrl;
                            if (_routeSuggestion != null) {
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(_originLatLng, 12),
                              );
                            }
                          },
                          polylines: _polylines,
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
                                      initialDestination: _destLatLng,
                                      initialDestinationName: widget.destinationName,
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
                        // Overlay Route Pill
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.two_wheeler, color: Color(0xFFFFA000), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    distText,
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
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
                    color: const Color(0xFFF8FAFC),
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
                              widget.originName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF1E293B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.destinationName,
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
                const Text(
                  'Seat Fare for Peer Passenger (৳)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Affordable DIU shared fuel contribution',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    // Decrement button
                    IconButton.filled(
                      onPressed: () => _adjustFare(-5),
                      icon: const Icon(Icons.remove, size: 18),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 8),
                    // Increment button
                    IconButton.filled(
                      onPressed: () => _adjustFare(5),
                      icon: const Icon(Icons.add, size: 18),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), foregroundColor: const Color(0xFF1E293B)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

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

                const SizedBox(height: 18),

                // 4. Passenger Helmet Included Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
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
                                'Helmet for Passenger',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                              Text(
                                'Provided by biker (DIU safety standard)',
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

                // 5. Registered Bike Details (Read-only from profile, no editable name fields)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
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
                  onPressed: _isPublishing ? null : _publish,
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
      ),
    );
  }
}
