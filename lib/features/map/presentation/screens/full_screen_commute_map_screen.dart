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
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';
import 'package:diu_ride/features/rides/presentation/screens/search_rides_screen.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';

class FullScreenCommuteMapScreen extends ConsumerStatefulWidget {
  final LatLng? initialDestination;
  final String? initialDestinationName;

  const FullScreenCommuteMapScreen({
    super.key,
    this.initialDestination,
    this.initialDestinationName,
  });

  @override
  ConsumerState<FullScreenCommuteMapScreen> createState() =>
      _FullScreenCommuteMapScreenState();
}

class _FullScreenCommuteMapScreenState
    extends ConsumerState<FullScreenCommuteMapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  // Current GPS Location
  LatLng _currentLocation = const LatLng(
    CampusLocations.diuCenterLat,
    CampusLocations.diuCenterLng,
  );
  String _currentLocationName = 'DIU Smart City, Ashulia';
  bool _isLoadingGps = true;

  // Selected Destination
  LatLng? _selectedDestination;
  String _destinationName = '';
  double _routeDistanceKm = 0.0;
  int _routeEtaMinutes = 0;
  String? _nearestDroppingZone;
  int _walkMinutesToZone = 2;
  List<LatLng> _routePolylinePoints = [];
  String _routeSummary = '';
  bool _isCalculatingRoute = false;

  // Search Results & Suggestions
  List<LocationSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  // Selected Ride or Student Pin
  RideModel? _selectedRide;
  PassengerRequestModel? _selectedStudentRequest;

  // Custom Emoji Markers (🏍️ Biker & 🙋‍♂️ Passenger)
  BitmapDescriptor? _bikerEmojiMarker;
  BitmapDescriptor? _passengerEmojiMarker;

  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) {
      _selectedDestination = widget.initialDestination;
      _destinationName = widget.initialDestinationName ?? 'Destination';
      _searchController.text = _destinationName;
    }
    _initLiveLocation();
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
      debugPrint('[CustomEmojiMarkers] Error: $e');
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
      ..strokeWidth = 3.5;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 8, borderPaint);

    // Pointer at bottom
    final path = Path()
      ..moveTo(size / 2 - 8, size - 14)
      ..lineTo(size / 2 + 8, size - 14)
      ..lineTo(size / 2, size - 2)
      ..close();
    canvas.drawPath(path, Paint()..color = borderColor);

    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.44),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2 - 4),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(pngBytes!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLiveLocation() async {
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
          _animateCameraTo(_currentLocation, zoom: 15.0);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _animateCameraTo(LatLng target, {double zoom = 15.0}) {
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

    // Ensure bounding box has non-zero padding so Google Map doesn't zoom out to entire planet
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

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<void> _calculateRouteStats(LatLng point, String name) async {
    setState(() {
      _selectedDestination = point;
      _destinationName = name;
      _isCalculatingRoute = true;
      _selectedRide = null;
    });

    final route = await LocationSearchService.getRoute(_currentLocation, point);

    // Identify nearest dropping zone
    String bestZone = 'DIU Main Gate 1';
    double minZoneDist = double.infinity;
    for (final z in LocationSearchService.campusLandmarks) {
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        z.lat,
        z.lng,
      );
      if (d < minZoneDist) {
        minZoneDist = d;
        bestZone = z.title;
      }
    }
    final walkMins = math.max(1, (minZoneDist / 80.0).round());

    if (mounted && _selectedDestination == point) {
      setState(() {
        _routeDistanceKm = double.parse(route.distanceKm.toStringAsFixed(1));
        _routeEtaMinutes = route.durationMinutes;
        _routePolylinePoints = route.polylinePoints;
        _routeSummary = route.summary;
        _nearestDroppingZone = bestZone;
        _walkMinutesToZone = walkMins;
        _isCalculatingRoute = false;
      });
      _fitRouteBounds();
    }
  }

  void _onLocationSelected(LocationSearchResult result) async {
    _searchController.text = result.title;
    setState(() {
      _showSearchResults = false;
    });

    LatLng target = result.latLng;
    if (result.placeId != null) {
      final point = await LocationSearchService.getPlaceCoordinates(result.placeId!);
      if (point != null) target = point;
    }
    _calculateRouteStats(target, result.title);
  }

  void _onMapTapped(LatLng point) async {
    setState(() {
      _showSearchResults = false;
      _selectedRide = null;
    });
    final name = await LocationSearchService.reverseGeocode(point);
    _searchController.text = name;
    _calculateRouteStats(point, name);
  }

  void _handleSearchChanged(String text) {
    _searchDebounceTimer?.cancel();
    final clean = text.trim();
    if (clean.isEmpty) {
      setState(() {
        _searchResults = LocationSearchService.campusLandmarks.take(8).toList();
        _showSearchResults = true;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final res = await LocationSearchService.search(clean);
      if (mounted) {
        setState(() {
          _searchResults = res;
          _isSearching = false;
        });
      }
    });
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationName = '';
      _routeDistanceKm = 0.0;
      _routeEtaMinutes = 0;
      _nearestDroppingZone = null;
      _selectedRide = null;
      _selectedStudentRequest = null;
      _routePolylinePoints = [];
      _routeSummary = '';
      _searchController.clear();
      _showSearchResults = false;
    });
    _animateCameraTo(_currentLocation);
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

  Set<Marker> _buildMarkers(List<RideModel> rides, List<dynamic> studentRequests, bool isRider) {
    final markers = <Marker>{};

    // 1. Live User GPS Spot Marker
    markers.add(
      Marker(
        markerId: const MarkerId('live_user_spot'),
        position: _currentLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: '📍 You Are Here',
          snippet: _currentLocationName,
        ),
      ),
    );

    // 2. Selected Destination Marker
    if (_selectedDestination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('target_destination'),
          position: _selectedDestination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🏁 $_destinationName',
            snippet: '$_routeDistanceKm km • ~$_routeEtaMinutes min commute',
          ),
        ),
      );
    }

    // 3. Official Dropping Zones Markers
    for (final zone in LocationSearchService.campusLandmarks.take(6)) {
      markers.add(
        Marker(
          markerId: MarkerId('drop_zone_${zone.title}'),
          position: zone.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '⬡ Dropping Zone: ${zone.title}',
            snippet: zone.subtitle,
          ),
          onTap: () {
            _searchController.text = zone.title;
            _calculateRouteStats(zone.latLng, zone.title);
          },
        ),
      );
    }

    // 4. In Rider Mode: Show nearest students waiting for a ride (🙋‍♂️ Pins)
    if (isRider) {
      for (final raw in studentRequests) {
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
              snippet: '${req.pickup} ➔ ${req.dropoff} • ৳${req.proposedFare.toInt()} (Tap to call/pickup)',
            ),
            onTap: () {
              setState(() {
                _selectedStudentRequest = req;
                _selectedRide = null;
              });
            },
          ),
        );
      }
    } else {
      // 4. In Passenger Mode: Show nearest active motorbikes who posted rides (🏍️ Pins)
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
            markerId: MarkerId('biker_${ride.id}'),
            position: pos,
            icon: _bikerEmojiMarker ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: '🏍️ Biker: ${ride.driverName} (${ride.vehicle.modelName})',
              snippet: '➔ ${ride.destinationName} • ৳${ride.farePerSeat.toInt()} (Tap to call/book)',
            ),
            onTap: () {
              setState(() {
                _selectedRide = ride;
                _selectedStudentRequest = null;
              });
            },
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};
    if (_selectedDestination != null && _routePolylinePoints.isNotEmpty) {
      // Google Maps double casing for clean road appearance
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_casing'),
          points: _routePolylinePoints,
          color: const Color(0xFF1565C0),
          width: 7,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_route'),
          points: _routePolylinePoints,
          color: const Color(0xFF42A5F5),
          width: 5,
        ),
      );
    } else if (_selectedDestination != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_direct'),
          points: [_currentLocation, _selectedDestination!],
          color: const Color(0xFFE65100),
          width: 4,
          patterns: [PatternItem.dash(15), PatternItem.gap(8)],
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(allAvailableRidesProvider).value ?? [];
    final studentRequests = ref.watch(passengerRequestsProvider).value ?? [];
    final appMode = ref.watch(appModeProvider);
    final isRider = appMode.isRider;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Edge-to-Edge Full Screen Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation,
              zoom: 14.5,
            ),
            markers: _buildMarkers(rides, studentRequests, isRider),
            polylines: _buildPolylines(),
            myLocationEnabled: !_isLoadingGps,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            trafficEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
            onMapCreated: (controller) {
              _mapController = controller;
              if (_selectedDestination != null) {
                _fitRouteBounds();
              }
            },
            onTap: _onMapTapped,
          ),

          // 2. Top Glassmorphic Google Search Bar & Back Button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopSearchBar(),
                    if (_showSearchResults) _buildSearchResultsOverlay(),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Recenter / "My Spot" Button
          Positioned(
            right: 16,
            bottom: _selectedDestination != null || _selectedRide != null ? 220 : 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_gps_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0284C7),
                  elevation: 4,
                  onPressed: () {
                    _initLiveLocation();
                    _animateCameraTo(_currentLocation);
                  },
                  tooltip: 'Recenter My Spot',
                  child: _isLoadingGps
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7)),
                        )
                      : const Icon(Icons.my_location),
                ),
                if (_selectedDestination != null) ...[
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'fit_route_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE65100),
                    elevation: 4,
                    onPressed: _fitRouteBounds,
                    tooltip: 'Fit Route',
                    child: const Icon(Icons.alt_route),
                  ),
                ],
              ],
            ),
          ),

          // 4. Bottom Interactive Action Sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _selectedRide != null
                  ? _buildSelectedRideBottomCard(_selectedRide!)
                  : _selectedStudentRequest != null
                      ? _buildSelectedStudentRequestBottomCard(_selectedStudentRequest!)
                      : _buildDestinationActionSheet(rides),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),

          // Text Field
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _handleSearchChanged,
              onTap: () {
                setState(() {
                  _showSearchResults = true;
                  if (_searchController.text.trim().isEmpty) {
                    _searchResults = LocationSearchService.campusLandmarks.take(8).toList();
                  } else {
                    _handleSearchChanged(_searchController.text);
                  }
                });
              },
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Search destination in Dhaka / Campus...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),

          // Loading indicator or Clear button
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65100)),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
              tooltip: 'Clear',
              onPressed: _clearDestination,
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.search, color: Color(0xFFE65100), size: 22),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsOverlay() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _searchResults.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off, color: Colors.grey, size: 24),
                    const SizedBox(height: 6),
                    Text(
                      'No matching places found.\nTry typing another spot (e.g. Motijheel, Dhanmondi, Mirpur, DIU)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFFFFF8E1),
                    child: Icon(
                      item.category == 'campus'
                          ? Icons.school
                          : item.category == 'metro'
                              ? Icons.train
                              : Icons.location_on,
                      size: 16,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _onLocationSelected(item),
                );
              },
            ),
    );
  }

  Widget _buildDestinationActionSheet(List<RideModel> allRides) {
    final appMode = ref.watch(appModeProvider);
    if (_selectedDestination == null) {
      return Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.touch_app, color: Color(0xFFE65100), size: 18),
                SizedBox(width: 8),
                Text(
                  'Explore Campus & Dhaka Routes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tap any spot on the map or pick a major corridor below:',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: LocationSearchService.campusLandmarks.take(6).map((lm) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      label: Text(lm.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      avatar: const Icon(Icons.place, size: 14, color: Color(0xFFE65100)),
                      onPressed: () => _onLocationSelected(lm),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    // Matching rides heading towards this corridor
    final matchingRides = allRides.where((r) {
      final dest = r.destinationName.toLowerCase();
      final sel = _destinationName.toLowerCase();
      return dest.contains(sel) || sel.contains(dest);
    }).toList();

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Destination Title and Distance/ETA badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _destinationName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isCalculatingRoute
                          ? 'Calculating turn-by-turn road route...'
                          : '$_routeDistanceKm km road route • ~$_routeEtaMinutes min bike ride',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                    ),
                    if (_routeSummary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '🛣️ Path: $_routeSummary',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                tooltip: 'Clear Route',
                onPressed: _clearDestination,
              ),
            ],
          ),

          // Dropping zone tag
          if (_nearestDroppingZone != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Text('⬡', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Nearest Dropping Zone: $_nearestDroppingZone (~$_walkMinutesToZone min walk)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action Buttons: Find Rides, Offer Ride, Request Ride
          Row(
            children: [
              // Find Rides Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(rideSearchFilterProvider.notifier).setDropoff(_destinationName);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchRidesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(
                    matchingRides.isNotEmpty ? 'View Bikers (${matchingRides.length})' : 'Find Bikers',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              if (!appMode.isPassenger) ...[
                // Offer Ride Button (Only for Bikers / Non-Passenger)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
                      if (!ok || !mounted) return;
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => OfferRideScreen(
                            onRidePublished: () {
                              nav.pop();
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.two_wheeler, size: 16),
                    label: const Text('Offer Ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE65100),
                      side: const BorderSide(color: Color(0xFFE65100), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Request Button (Only in passenger mode)
                if (!appMode.isRider)
                  InkWell(
                    onTap: () {
                      PostRideRequestSheet.show(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Icon(Icons.hail, color: Color(0xFF334155), size: 18),
                    ),
                  ),
              ] else ...[
                // Passenger Mode: Prominent Request Ride Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      PostRideRequestSheet.show(context);
                    },
                    icon: const Icon(Icons.hail, size: 16),
                    label: const Text('Request Ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF141416),
                      side: const BorderSide(color: Color(0xFF141416), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRideBottomCard(RideModel ride) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.two_wheeler, color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    ride.driverName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${ride.vehicle.modelName})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '৳${ride.farePerSeat.toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${ride.originName} ➔ ${ride.destinationName}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Direct Call Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF16A34A),
                  side: const BorderSide(color: Color(0xFF16A34A), width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                ),
                onPressed: () {
                  DirectCallService.makeDirectPhoneCall(
                    context,
                    phoneNumber: ride.driverPhone ?? '',
                    peerName: ride.driverName,
                  );
                },
                icon: const Icon(Icons.phone_in_talk, size: 15),
                label: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100), width: 1.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () {
                    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
                    final sorted = [currentUserId, ride.driverId]..sort();
                    final convId = 'peer_dm_${sorted[0]}__${sorted[1]}';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: convId,
                          sourcePostId: ride.id,
                          chatContext: 'from_ride_post',
                          peerId: ride.driverId,
                          peerName: ride.driverName,
                          peerPhone: ride.driverPhone,
                          vehicleModel: ride.vehicle.modelName,
                          peerRole: 'Biker',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  label: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () {
                    BookingConfirmationSheet.show(
                      context: context,
                      ride: ride,
                      onBookingSuccess: () {
                        setState(() => _selectedRide = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🎉 Seat Booking Request Sent!'),
                            backgroundColor: Color(0xFF16A34A),
                          ),
                        );
                      },
                    );
                  },
                  icon: const Icon(Icons.bookmark_added_rounded, size: 15),
                  label: const Text('Book Seat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.all(6),
                ),
                onPressed: () => setState(() => _selectedRide = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedStudentRequestBottomCard(PassengerRequestModel req) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.school_rounded, color: Color(0xFF0284C7), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    req.passengerName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${req.passengerDept})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '৳${req.proposedFare.toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0369A1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.trip_origin, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pickup: ${req.pickup}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Color(0xFFE11D48)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dropoff: ${req.dropoff} • ${req.requestedTime}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Direct Call Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF16A34A),
                  side: const BorderSide(color: Color(0xFF16A34A), width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                ),
                onPressed: () {
                  DirectCallService.makeDirectPhoneCall(
                    context,
                    phoneNumber: req.passengerPhone,
                    peerName: req.passengerName,
                  );
                },
                icon: const Icon(Icons.phone_in_talk, size: 15),
                label: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
                    final sorted = [currentUserId, req.passengerId]..sort();
                    final convId = 'peer_dm_${sorted[0]}__${sorted[1]}';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: convId,
                          sourcePostId: req.id,
                          chatContext: 'from_passenger_request',
                          peerId: req.passengerId,
                          peerName: req.passengerName,
                          peerPhone: req.passengerPhone,
                          vehicleModel: 'Student Request',
                          peerRole: 'Passenger',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  label: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFF0284C7), width: 1.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final user = ref.read(authNotifierProvider).user;
                    if (SameAccountGuard.blockOwnPassengerAccept(context, user, req)) {
                      return;
                    }
                    final driverId = user?.id ?? '';
                    final driverName = user?.name ?? 'DIU Biker';
                    final driverPhone = user?.phone ?? '';
                    try {
                      await ref.read(ridesRepositoryProvider).acceptPassengerRequest(
                        requestId: req.id,
                        driverId: driverId,
                        driverName: driverName,
                        driverPhone: driverPhone,
                        driverBike: user?.vehicleInfo?.isNotEmpty == true ? user!.vehicleInfo! : 'Campus Motorbike',
                        driverStudentId: user?.studentId,
                      );
                      ref.invalidate(passengerRequestsProvider);
                      if (mounted) {
                        setState(() => _selectedStudentRequest = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Accepted ${req.passengerName}\'s ride request!'),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFB45309),
                          content: Text(e.toString().replaceFirst('Exception: ', '')),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 15),
                  label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                onPressed: () => setState(() => _selectedStudentRequest = null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
