import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/map/presentation/screens/full_screen_commute_map_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class LandingCommuteMapCard extends ConsumerStatefulWidget {
  final Function(String destination) onFindRides;
  final Function(String destination) onOfferRide;
  final Function(String destination) onRequestRide;
  final Function(RideModel ride)? onRideSelected;

  const LandingCommuteMapCard({
    super.key,
    required this.onFindRides,
    required this.onOfferRide,
    required this.onRequestRide,
    this.onRideSelected,
  });

  @override
  ConsumerState<LandingCommuteMapCard> createState() => _LandingCommuteMapCardState();
}

class _LandingCommuteMapCardState extends ConsumerState<LandingCommuteMapCard> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  // Current GPS Location
  LatLng _currentLocation = const LatLng(
    CampusLocations.diuCenterLat,
    CampusLocations.diuCenterLng,
  );
  bool _isLoadingGps = true;
  String _currentLocationName = 'DIU Smart City, Ashulia';

  // Selected Destination & Road Route stats
  LatLng? _selectedDestination;
  String _destinationName = '';
  double _routeDistanceKm = 0.0;
  int _routeEtaMinutes = 0;
  List<LatLng> _routePolylinePoints = [];
  bool _isCalculatingRoute = false;

  // Search Results & Autocomplete
  List<LocationSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Timer? _searchDebounceTimer;

  // Selected active ride pin or student request pin
  RideModel? _tappedRide;
  PassengerRequestModel? _tappedStudentRequest;

  // Custom Emoji Markers for live posted Bikers (🏍️) and Passengers (🙋‍♂️)
  BitmapDescriptor? _bikerEmojiMarker;
  BitmapDescriptor? _passengerEmojiMarker;

  // Quick preset locations
  final List<Map<String, dynamic>> _quickDestinations = [
    {
      'name': 'Uttara North Metro',
      'latLng': const LatLng(23.8710, 90.3800),
      'icon': Icons.train_outlined,
    },
    {
      'name': 'Mirpur 10 Circle',
      'latLng': const LatLng(23.8069, 90.3687),
      'icon': Icons.location_city,
    },
    {
      'name': 'Dhanmondi Sobhanbag',
      'latLng': const LatLng(23.7538, 90.3768),
      'icon': Icons.school_outlined,
    },
    {
      'name': 'Mohakhali Flyover',
      'latLng': const LatLng(23.7780, 90.4000),
      'icon': Icons.alt_route,
    },
    {
      'name': 'Savar Stand',
      'latLng': const LatLng(23.8475, 90.2570),
      'icon': Icons.directions_bus_outlined,
    },
    {
      'name': 'DIU Main Gate 1',
      'latLng': const LatLng(23.8775, 90.3201),
      'icon': Icons.shield_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLiveLocation();
    _initCustomEmojiMarkers();
  }

  Future<void> _initCustomEmojiMarkers() async {
    try {
      final biker = await _createEmojiMarkerBitmap(
        emoji: '🏍️',
        bgColor: const Color(0xFFFFF8E1),
        borderColor: const Color(0xFFE65100),
      );
      final passenger = await _createEmojiMarkerBitmap(
        emoji: '🙋‍♂️',
        bgColor: const Color(0xFFF0FDF4),
        borderColor: const Color(0xFF16A34A),
      );
      if (mounted) {
        setState(() {
          _bikerEmojiMarker = biker;
          _passengerEmojiMarker = passenger;
        });
      }
    } catch (e) {
      debugPrint('[LandingMapEmojiMarkers] Error: $e');
    }
  }

  static Future<BitmapDescriptor> _createEmojiMarkerBitmap({
    required String emoji,
    required Color bgColor,
    required Color borderColor,
    int size = 110,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(size / 2, size / 2 + 2), size / 2 - 8, shadowPaint);

    final bgPaint = Paint()..color = bgColor;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 8, bgPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 8, borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.46),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2 - 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(pngBytes);
  }

  LatLng _resolveLocation(String name, double? lat, double? lng) {
    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      return LatLng(lat, lng);
    }
    final lower = name.toLowerCase().trim();
    for (final loc in [...CampusLocations.allCampusSpots, ...CampusLocations.popularDestinations]) {
      if (lower.contains(loc.name.toLowerCase()) || loc.name.toLowerCase().contains(lower)) {
        return LatLng(loc.latitude, loc.longitude);
      }
    }
    if (lower.contains('gate 1') || lower.contains('main gate')) return const LatLng(23.8775, 90.3201);
    if (lower.contains('bus bay') || lower.contains('terminal')) return const LatLng(23.8762, 90.3195);
    if (lower.contains('uttara')) return const LatLng(23.8710, 90.3800);
    if (lower.contains('mirpur')) return const LatLng(23.8069, 90.3687);
    if (lower.contains('dhanmondi')) return const LatLng(23.7538, 90.3768);
    if (lower.contains('savar')) return const LatLng(23.8488, 90.2575);
    return const LatLng(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveLocation() async {
    try {
      final coords = await GpsLocationService.getAccurateCurrentCoordinates();
      final name = await GpsLocationService.getReadableCurrentLocationName();
      if (mounted) {
        setState(() {
          _currentLocation = coords;
          _isLoadingGps = false;
          _currentLocationName = name;
        });
        if (_selectedDestination != null) {
          _calculateRouteStats(_selectedDestination!, _destinationName);
        } else {
          _animateCameraTo(_currentLocation);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _animateCameraTo(LatLng target, {double zoom = 14.5}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  void _fitRouteBounds() {
    if (_selectedDestination == null || _mapController == null) return;

    double southWestLat = math.min(_currentLocation.latitude, _selectedDestination!.latitude);
    double southWestLng = math.min(_currentLocation.longitude, _selectedDestination!.longitude);
    double northEastLat = math.max(_currentLocation.latitude, _selectedDestination!.latitude);
    double northEastLng = math.max(_currentLocation.longitude, _selectedDestination!.longitude);

    if (_routePolylinePoints.isNotEmpty) {
      for (final p in _routePolylinePoints) {
        if (p.latitude < 20.0 || p.latitude > 27.0 || p.longitude < 87.0 || p.longitude > 93.0) continue;
        if (p.latitude < southWestLat) southWestLat = p.latitude;
        if (p.longitude < southWestLng) southWestLng = p.longitude;
        if (p.latitude > northEastLat) northEastLat = p.latitude;
        if (p.longitude > northEastLng) northEastLng = p.longitude;
      }
    }

    if ((northEastLat - southWestLat).abs() < 0.008) {
      northEastLat += 0.004;
      southWestLat -= 0.004;
    }
    if ((northEastLng - southWestLng).abs() < 0.008) {
      northEastLng += 0.004;
      southWestLng -= 0.004;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(southWestLat, southWestLng),
      northeast: LatLng(northEastLat, northEastLng),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 45));
  }

  void _onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await LocationSearchService.search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _calculateRouteStats(LatLng dest, String name) async {
    setState(() {
      _selectedDestination = dest;
      _destinationName = name;
      _isCalculatingRoute = true;
      _showSearchResults = false;
      _tappedRide = null;
      _tappedStudentRequest = null;
    });
    _searchController.text = name;

    try {
      final route = await LocationSearchService.getRoute(_currentLocation, dest);
      if (mounted) {
        setState(() {
          _routePolylinePoints = route.polylinePoints;
          _routeDistanceKm = double.parse(route.distanceKm.toStringAsFixed(1));
          _routeEtaMinutes = route.durationMinutes;
          _isCalculatingRoute = false;
        });
        _fitRouteBounds();
      }
    } catch (_) {
      // Direct Euclidean fallback
      final distMeters = Geolocator.distanceBetween(
        _currentLocation.latitude,
        _currentLocation.longitude,
        dest.latitude,
        dest.longitude,
      );
      final distKm = distMeters / 1000.0;
      final etaMins = (distKm / 30.0 * 60).round() + 5;
      if (mounted) {
        setState(() {
          _routePolylinePoints = [_currentLocation, dest];
          _routeDistanceKm = double.parse(distKm.toStringAsFixed(1));
          _routeEtaMinutes = etaMins;
          _isCalculatingRoute = false;
        });
        _fitRouteBounds();
      }
    }
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationName = '';
      _routeDistanceKm = 0.0;
      _routeEtaMinutes = 0;
      _routePolylinePoints = [];
      _tappedRide = null;
      _tappedStudentRequest = null;
      _searchController.clear();
      _showSearchResults = false;
    });
    _animateCameraTo(_currentLocation);
  }

  Set<Marker> _buildMarkers(List<RideModel> rides, List<dynamic> rawRequests, bool isRider) {
    final markers = <Marker>{};

    // 1. Current Location Marker (Cyan Pin)
    markers.add(
      Marker(
        markerId: const MarkerId('current_user_location'),
        position: _currentLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: '📍 You Are Here',
          snippet: _currentLocationName,
        ),
      ),
    );

    // 2. Selected Destination Marker (Red Pin)
    if (_selectedDestination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_destination'),
          position: _selectedDestination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🏁 Destination: $_destinationName',
            snippet: '$_routeDistanceKm km • ~$_routeEtaMinutes min commute',
          ),
        ),
      );
    }

    // 3. Dropping Zones & Campus Hubs (Azure Pins)
    for (final zone in LocationSearchService.campusLandmarks.take(5)) {
      markers.add(
        Marker(
          markerId: MarkerId('zone_${zone.title}'),
          position: zone.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '⬡ Zone: ${zone.title}',
            snippet: zone.subtitle,
          ),
          onTap: () {
            _calculateRouteStats(zone.latLng, zone.title);
          },
        ),
      );
    }

    // 4. In Rider Mode: Show nearest student ride requests who posted open requests (🙋‍♂️ Pins)
    if (isRider) {
      for (final raw in rawRequests) {
        PassengerRequestModel req;
        if (raw is PassengerRequestModel) {
          req = raw;
        } else if (raw is Map) {
          req = PassengerRequestModel.fromJson(Map<String, dynamic>.from(raw));
        } else {
          continue;
        }
        if (req.status != 'open' && req.status != 'pending') continue;

        final pos = _resolveLocation(req.pickup, req.pickupLat, req.pickupLng);
        markers.add(
          Marker(
            markerId: MarkerId('student_req_${req.id}'),
            position: pos,
            icon: _passengerEmojiMarker ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: '🙋‍♂️ Passenger: ${req.passengerName}',
              snippet: '${req.pickup} ➔ ${req.dropoff} • ৳${req.proposedFare.toInt()} • ${req.requestedTime}',
            ),
            onTap: () {
              setState(() {
                _tappedStudentRequest = req;
                _tappedRide = null;
              });
            },
          ),
        );
      }
    } else {
      // 4. In Passenger Mode: Show active biker rides who posted available seats (🏍️ Pins)
      for (final ride in rides) {
        if (ride.status != RideStatus.published && ride.status != RideStatus.active) continue;
        if (ride.availableSeats <= 0) continue;

        final pos = _resolveLocation(
          ride.originName,
          ride.startLat ?? ride.originLat,
          ride.startLng ?? ride.originLng,
        );

        markers.add(
          Marker(
            markerId: MarkerId('ride_${ride.id}'),
            position: pos,
            icon: _bikerEmojiMarker ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: '🏍️ Biker: ${ride.driverName} (${ride.vehicle.modelName})',
              snippet: '➔ ${ride.destinationName} • ৳${ride.farePerSeat.toInt()} • ${ride.availableSeats} seat(s)',
            ),
            onTap: () {
              setState(() {
                _tappedRide = ride;
                _tappedStudentRequest = null;
              });
            },
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_selectedDestination == null) return {};

    final polylines = <Polyline>{};
    if (_routePolylinePoints.isNotEmpty) {
      // Google Maps double casing for clean road appearance
      polylines.add(
        Polyline(
          polylineId: const PolylineId('commute_route_casing'),
          points: _routePolylinePoints,
          color: const Color(0xFF1565C0),
          width: 6,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('commute_route_core'),
          points: _routePolylinePoints,
          color: const Color(0xFF42A5F5),
          width: 4,
        ),
      );
    } else {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('commute_route_direct'),
          points: [_currentLocation, _selectedDestination!],
          color: const Color(0xFFE65100),
          width: 4,
          geodesic: true,
          patterns: [PatternItem.dash(18), PatternItem.gap(8)],
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];
    final rawRequests = ref.watch(passengerRequestsProvider).value ?? [];
    final appMode = ref.watch(appModeProvider);
    final isRider = appMode.isRider;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Live Interactive Map title and actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.map_rounded,
                        size: 18,
                        color: Color(0xFFE65100),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRider ? 'Live Map • Student Requests' : 'Live Map • Nearest Motorbikes',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          _isLoadingGps
                              ? 'Locating GPS...'
                              : isRider
                                  ? 'See students waiting along your route'
                                  : 'Tap map or search to see route km & time',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                Row(
                  children: [
                    // Full Screen Map View Button
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FullScreenCommuteMapScreen(
                              initialDestination: _selectedDestination,
                              initialDestinationName: _destinationName,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFEDD5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen, size: 16, color: Color(0xFFE65100)),
                            SizedBox(width: 4),
                            Text(
                              'Full Map',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Recenter My Location Button
                    InkWell(
                      onTap: () {
                        _fetchLiveLocation();
                        _animateCameraTo(_currentLocation);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.my_location, size: 14, color: Color(0xFF0284C7)),
                            SizedBox(width: 4),
                            Text(
                              'My Spot',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Suggestions Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchQueryChanged,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: isRider ? 'Search destination to preview student pickups...' : 'Search where to go (e.g. Uttara, Mirpur, Dhanmondi)...',
                  hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Color(0xFFE65100)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 17, color: Color(0xFF94A3B8)),
                          onPressed: _clearDestination,
                        )
                      : (_isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65100)),
                              ),
                            )
                          : null),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
              ),
            ),
          ),

          // Autocomplete Suggestions Dropdown
          if (_showSearchResults && _searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, i) {
                  final res = _searchResults[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_rounded, color: Color(0xFFE65100), size: 18),
                    title: Text(res.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: Text(res.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    onTap: () {
                      _calculateRouteStats(res.latLng, res.title);
                    },
                  );
                },
              ),
            ),

          // Google Map Viewport (Rounded Container with ClipRRect)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 310,
              width: double.infinity,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation,
                      zoom: 14.2,
                    ),
                    onMapCreated: (ctrl) {
                      _mapController = ctrl;
                      _animateCameraTo(_currentLocation);
                    },
                    myLocationEnabled: !_isLoadingGps,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                    markers: _buildMarkers(allRides, rawRequests, isRider),
                    polylines: _buildPolylines(),
                    onTap: (point) {
                      _calculateRouteStats(
                        point,
                        'Dropped Pin (${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)})',
                      );
                    },
                  ),

                  // Top Right: Floating Fullscreen Map & Recenter Buttons
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Recenter GPS Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _fetchLiveLocation();
                              _animateCameraTo(_currentLocation);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.my_location,
                                size: 16,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Expand to Fullscreen Map Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenCommuteMapScreen(
                                    initialDestination: _selectedDestination,
                                    initialDestinationName: _destinationName.isNotEmpty ? _destinationName : null,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65100),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fullscreen,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Full Map',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top instruction pill
                  if (_selectedDestination == null)
                    Positioned(
                      top: 10,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isRider ? Icons.school : Icons.touch_app, size: 13, color: const Color(0xFFE65100)),
                            const SizedBox(width: 5),
                            Text(
                              isRider ? 'Tap green pin for student request' : 'Tap map or search to draw route',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Route Overlay Card (When destination is set)
                  if (_selectedDestination != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.4)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Route Details Row
                            Row(
                              children: [
                                const Icon(Icons.location_on, color: Color(0xFFE65100), size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _destinationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _isCalculatingRoute
                                        ? 'Calculating...'
                                        : '$_routeDistanceKm km • ~$_routeEtaMinutes min',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: _clearDestination,
                                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Action buttons: Find Rides | Offer Ride | Request
                            Row(
                              children: [
                                // 1. Find Rides to Destination
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => widget.onFindRides(_destinationName),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.search, size: 14),
                                    label: const Text(
                                      'Find Rides',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // 2. Offer Ride Along This Route
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => widget.onOfferRide(_destinationName),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFE65100),
                                      side: const BorderSide(color: Color(0xFFE65100)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.two_wheeler, size: 14),
                                    label: const Text(
                                      'Offer Ride',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Active Ride Selected Overlay (When a bike marker is tapped in Passenger Mode)
                  if (_tappedRide != null && _selectedDestination == null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFFF8E1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Text('🏍️', style: TextStyle(fontSize: 16)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tappedRide!.driverName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${_tappedRide!.vehicle.modelName} • ${_tappedRide!.availableSeats} seat(s) left',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '৳${_tappedRide!.farePerSeat.toInt()}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFFE65100)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _tappedRide = null),
                                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.alt_route, size: 12, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${_tappedRide!.originName} ➔ ${_tappedRide!.destinationName}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Direct Call
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      DirectCallService.makeDirectPhoneCall(
                                        context,
                                        phoneNumber: _tappedRide!.driverPhone ?? '',
                                        peerName: _tappedRide!.driverName,
                                      );
                                    },
                                    icon: const Icon(Icons.phone_in_talk, size: 14),
                                    label: const Text('Call', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF16A34A),
                                      side: const BorderSide(color: Color(0xFF16A34A)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Chat Knock
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
                                      final sorted = [currentUserId, _tappedRide!.driverId]..sort();
                                      final convId = 'peer_dm_${sorted[0]}__${sorted[1]}';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: convId,
                                            peerId: _tappedRide!.driverId,
                                            peerName: _tappedRide!.driverName,
                                            peerPhone: _tappedRide!.driverPhone,
                                            vehicleModel: _tappedRide!.vehicle.modelName,
                                            peerRole: 'Biker',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                    label: const Text('Chat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFE65100),
                                      side: const BorderSide(color: Color(0xFFE65100)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Book Seat
                                Expanded(
                                  flex: 4,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (widget.onRideSelected != null) {
                                        widget.onRideSelected!(_tappedRide!);
                                      } else {
                                        BookingConfirmationSheet.show(
                                          context: context,
                                          ride: _tappedRide!,
                                          onBookingSuccess: () {
                                            setState(() => _tappedRide = null);
                                            ref.invalidate(allAvailableRidesProvider);
                                          },
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.bookmark_add_rounded, size: 14),
                                    label: const Text('Book Seat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Active Student Request Overlay (When a student pin is tapped in Rider mode)
                  if (_tappedStudentRequest != null && _selectedDestination == null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDCFCE7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Text('🙋‍♂️', style: TextStyle(fontSize: 16)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _tappedStudentRequest!.passengerName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${_tappedStudentRequest!.passengerDept} • ${_tappedStudentRequest!.requestedTime}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '৳${_tappedStudentRequest!.proposedFare.toInt()}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF15803D)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _tappedStudentRequest = null),
                                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.trip_origin, size: 12, color: Color(0xFF10B981)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${_tappedStudentRequest!.pickup} ➔ ${_tappedStudentRequest!.dropoff}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (_tappedStudentRequest!.notes.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Note: ${_tappedStudentRequest!.notes}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontStyle: FontStyle.italic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Direct Call
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      DirectCallService.makeDirectPhoneCall(
                                        context,
                                        phoneNumber: _tappedStudentRequest!.passengerPhone,
                                        peerName: _tappedStudentRequest!.passengerName,
                                      );
                                    },
                                    icon: const Icon(Icons.phone_in_talk, size: 14),
                                    label: const Text('Call', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF16A34A),
                                      side: const BorderSide(color: Color(0xFF16A34A)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Message Chat
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final authUser = ref.read(authNotifierProvider).user;
                                      final peerId = _tappedStudentRequest!.passengerId;
                                      final peerName = _tappedStudentRequest!.passengerName;
                                      final chatId = (authUser != null && peerId.isNotEmpty)
                                          ? 'peer_dm_${[authUser.id, peerId]..sort()}'
                                          : 'request_${_tappedStudentRequest!.id}';

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: chatId,
                                            driverName: peerName,
                                            peerId: peerId,
                                            peerName: peerName,
                                            peerPhone: _tappedStudentRequest!.passengerPhone,
                                            peerRole: 'Passenger',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                    label: const Text('Chat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF0284C7),
                                      side: const BorderSide(color: Color(0xFF0284C7)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Pick Up Peer
                                Expanded(
                                  flex: 4,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      try {
                                        final authUser = ref.read(authNotifierProvider).user;
                                        if (authUser == null) return;
                                        if (SameAccountGuard.blockOwnPassengerAccept(
                                          context,
                                          authUser,
                                          _tappedStudentRequest,
                                        )) {
                                          return;
                                        }
                                        final repo = ref.read(ridesRepositoryProvider);
                                        await repo.acceptPassengerRequest(
                                          requestId: _tappedStudentRequest!.id,
                                          driverId: authUser.id,
                                          driverName: authUser.name,
                                          driverPhone: authUser.phone,
                                          driverBike: authUser.vehicleModel ?? 'Motorbike',
                                          driverStudentId: authUser.studentId,
                                        );
                                        ref.invalidate(passengerRequestsProvider);
                                        final reqCopy = _tappedStudentRequest!;
                                        setState(() => _tappedStudentRequest = null);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Accepted ${reqCopy.passengerName}\'s request!'),
                                              backgroundColor: const Color(0xFF16A34A),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: const Color(0xFFB45309),
                                            content: Text(e.toString().replaceFirst('Exception: ', '')),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.two_wheeler, size: 14),
                                    label: const Text('Pick Up', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Quick Destination Pills Horizontal Selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Where do you want to go?',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (_selectedDestination != null)
                      GestureDetector(
                        onTap: _clearDestination,
                        child: const Text(
                          'Reset Pin',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _quickDestinations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final item = _quickDestinations[i];
                      final isSelected = _destinationName == item['name'];

                      return InkWell(
                        onTap: () {
                          _calculateRouteStats(item['latLng'] as LatLng, item['name'] as String);
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE65100)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 14,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item['name'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
