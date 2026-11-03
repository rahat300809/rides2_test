import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';

class CommuteCorridorMatchingSheet extends StatefulWidget {
  final String pickupName;
  final String destinationName;
  final DateTime requestedTime;
  final List<RideModel> allAvailableRides;
  final Function(RideModel ride)? onSelectRide;

  const CommuteCorridorMatchingSheet({
    super.key,
    required this.pickupName,
    required this.destinationName,
    required this.requestedTime,
    required this.allAvailableRides,
    this.onSelectRide,
  });

  static Future<void> show(
    BuildContext context, {
    required String pickupName,
    required String destinationName,
    required DateTime requestedTime,
    required List<RideModel> allAvailableRides,
    Function(RideModel ride)? onSelectRide,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CommuteCorridorMatchingSheet(
        pickupName: pickupName,
        destinationName: destinationName,
        requestedTime: requestedTime,
        allAvailableRides: allAvailableRides,
        onSelectRide: onSelectRide,
      ),
    );
  }

  @override
  State<CommuteCorridorMatchingSheet> createState() =>
      _CommuteCorridorMatchingSheetState();
}

class _CommuteCorridorMatchingSheetState
    extends State<CommuteCorridorMatchingSheet> {
  GoogleMapController? _mapController;
  List<LatLng> _routePolyline = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoadingRoute = true;
  String _selectedAreaFilter = 'All Corridor';
  RideModel? _selectedRide;

  LatLng _pickupLatLng = const LatLng(23.8765, 90.3204); // DIU Campus
  LatLng _destLatLng = const LatLng(23.8069, 90.3687); // Default Mirpur 10

  // Known corridors for smart route overlap (Comprehensive for all Dhaka & suburban zones)
  final Map<String, List<String>> _corridorWaypoints = {
    'uttara_diabari_airport': [
      'ashulia', 'diu smart city', 'daffodil', 'khagan', 'akran', 'birulia',
      'birulia bridge', 'panchabati', 'diabari', 'pallabi', 'uttara north',
      'uttara sector 10', 'uttara sector 11', 'house building', 'azampur',
      'airport', 'khilkhet', 'kuril', 'bashundhara',
    ],
    'mirpur_metro_corridor': [
      'ashulia', 'diu smart city', 'daffodil', 'khagan', 'akran', 'birulia',
      'birulia bridge', 'panchabati', 'diabari', 'pallabi', 'beribadh',
      'mirpur 12', 'mirpur 11', 'mirpur 10', 'mirpur 2', 'mirpur 1',
      'kazipara', 'shewrapara', 'agargaon', 'ecb', 'ecb chattar',
    ],
    'central_motijheel_corridor': [
      'ashulia', 'diu smart city', 'khagan', 'akran', 'birulia', 'mirpur',
      'kazipara', 'agargaon', 'bijoy sarani', 'farmgate', 'karwan bazar',
      'shahbagh', 'bangla motor', 'dhaka university', 'curzon', 'high court',
      'paltan', 'motijheel', 'kamalapur', 'sayedabad',
    ],
    'dhanmondi_mohammadpur_corridor': [
      'ashulia', 'diu smart city', 'khagan', 'charabag', 'savar', 'aminbazar',
      'gabtoli', 'technical', 'kalyanpur', 'shyamoli', 'asad gate',
      'mohammadpur', 'shankar', 'dhanmondi', 'kalabagan', 'science lab',
      'new market', 'azimpur',
    ],
    'savar_nabinagar_epz_corridor': [
      'ashulia', 'diu smart city', 'khagan', 'charabag', 'savar cantonment',
      'savar', 'savar bazar', 'thana stand', 'hemayetpur', 'c&b',
      'jahangirnagar', 'nabinagar', 'baipayl', 'depz', 'zirani', 'chandra',
    ],
    'gazipur_tongi_corridor': [
      'ashulia', 'diu smart city', 'ashulia bazar', 'abdullahpur', 'tongi',
      'station road', 'cherag ali', 'board bazar', 'gazipur chowrasta',
      'shibbari', 'gazipur',
    ],
    'gulshan_banani_badda_corridor': [
      'ashulia', 'diu smart city', 'birulia', 'diabari', 'uttara', 'airport',
      'khilkhet', 'kuril', 'radisson', 'banani', 'gulshan 2', 'gulshan 1',
      'mohakhali', 'badda', 'rampura', 'hatirjheel',
    ],
  };

  BitmapDescriptor? _bikeMarkerIcon;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkerIcons();
    _resolveCoordinatesAndBuildRoute();
  }

  Future<void> _loadCustomMarkerIcons() async {
    try {
      _bikeMarkerIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(46, 46)),
        'assets/images/bike_pin.png',
      );
    } catch (_) {
      try {
        _bikeMarkerIcon = await BitmapDescriptor.asset(
          const ImageConfiguration(size: Size(42, 42)),
          'assets/images/app_logo.png',
        );
      } catch (_) {
        _bikeMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      }
    }
    if (mounted) {
      _buildMapElements();
    }
  }

  Future<void> _resolveCoordinatesAndBuildRoute() async {
    // 1. Resolve Destination LatLng accurately via canonical dictionary & landmarks lookup
    _destLatLng = LocationSearchService.lookupCoordinates(widget.destinationName);

    // 2. Resolve Pickup LatLng accurately via canonical dictionary & landmarks lookup
    _pickupLatLng = LocationSearchService.lookupCoordinates(widget.pickupName);

    // If destination or pickup coordinates happen to be exactly overlapping (e.g. same campus spot)
    if ((_pickupLatLng.latitude - _destLatLng.latitude).abs() < 0.0005 &&
        (_pickupLatLng.longitude - _destLatLng.longitude).abs() < 0.0005) {
      final destLower = widget.destinationName.toLowerCase();
      if (destLower.contains('birulia')) {
        _destLatLng = const LatLng(23.8685, 90.3340);
      } else if (destLower.contains('mirpur')) {
        _destLatLng = const LatLng(23.8069, 90.3687);
      } else if (destLower.contains('uttara')) {
        _destLatLng = const LatLng(23.8710, 90.3800);
      } else {
        _destLatLng = const LatLng(23.8685, 90.3340); // Birulia Bridge Link
      }
    }

    // 3. Compute Real Road Polyline
    final routeData =
        await LocationSearchService.getRoute(_pickupLatLng, _destLatLng);
    if (mounted) {
      setState(() {
        _routePolyline = routeData.polylinePoints;
        _isLoadingRoute = false;
        _buildMapElements();
      });
      _fitMapBounds();
    }
  }

  void _buildMapElements() {
    final markers = <Marker>{};

    // Pickup Marker (Green)
    markers.add(
      Marker(
        markerId: const MarkerId('pickup_pt'),
        position: _pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup: ${widget.pickupName}',
          snippet: 'Your boarding location',
        ),
      ),
    );

    // Destination Marker (Red/Orange)
    markers.add(
      Marker(
        markerId: const MarkerId('dest_pt'),
        position: _destLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination: ${widget.destinationName}',
          snippet: 'Your requested dropoff',
        ),
      ),
    );

    // Nearest Rider Markers shown at their passenger pickup / stand positions
    final matchingRiders = _getRankedMatchingRides();
    for (int i = 0; i < matchingRiders.length; i++) {
      final r = matchingRiders[i];
      // Position where rider is waiting to pick up passengers
      final waitingLat = (r.originLat != 0.0)
          ? r.originLat
          : (_pickupLatLng.latitude + (math.sin(i * 1.8) * 0.004));
      final waitingLng = (r.originLng != 0.0)
          ? r.originLng
          : (_pickupLatLng.longitude + (math.cos(i * 1.8) * 0.004));

      final pos = LatLng(waitingLat, waitingLng);

      markers.add(
        Marker(
          markerId: MarkerId('rider_${r.id}'),
          position: pos,
          icon: _bikeMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '🏍️ ${r.driverName} (৳${r.farePerSeat.toInt()})',
            snippet: 'Waiting at ${r.originName} ➔ ${r.destinationName}',
          ),
          onTap: () {
            setState(() => _selectedRide = r);
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(pos, 14.5),
            );
          },
        ),
      );
    }

    final polylines = <Polyline>{};
    if (_routePolyline.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_route'),
          points: _routePolyline,
          color: const Color(0xFFE65100),
          width: 5,
        ),
      );
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  void _fitMapBounds() {
    if (_mapController == null || _routePolyline.isEmpty) return;
    double minLat = _pickupLatLng.latitude;
    double maxLat = _pickupLatLng.latitude;
    double minLng = _pickupLatLng.longitude;
    double maxLng = _pickupLatLng.longitude;

    for (final p in _routePolyline) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.015, minLng - 0.015),
          northeast: LatLng(maxLat + 0.015, maxLng + 0.015),
        ),
        50,
      ),
    );
  }

  double _calculateDistanceKm(LatLng p1, LatLng p2) {
    const earthRadius = 6371.0;
    final dLat = (p2.latitude - p1.latitude) * (math.pi / 180.0);
    final dLng = (p2.longitude - p1.longitude) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * (math.pi / 180.0)) *
            math.cos(p2.latitude * (math.pi / 180.0)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Real-Time Map Route Hexagon & Corridor Geometry Analyzer
  /// Evaluates real-time polyline GPS coordinates from the map,
  /// detects if rider's path intersects the route corridor hexagons,
  /// and weights higher the closer the hexagon is to the route's END POINT.
  Map<String, dynamic> _analyzeRideAlongRoute(RideModel ride) {
    final riderDest = LocationSearchService.lookupCoordinates(ride.destinationName);
    final targetDest = _destLatLng;
    final distToEndPoint = _calculateDistanceKm(riderDest, targetDest);

    final targetLower = widget.destinationName.toLowerCase().trim();
    final riderLower = ride.destinationName.toLowerCase().trim();
    final isExactText = riderLower.contains(targetLower) || targetLower.contains(riderLower);
    final isExact = isExactText || distToEndPoint <= 0.8;

    if (_routePolyline.isEmpty) {
      return {
        'isMatch': isExact,
        'isExact': isExact,
        'distToEndPoint': distToEndPoint,
        'minDistToRoute': distToEndPoint,
        'progressRatio': isExact ? 1.0 : 0.0,
        'score': isExact ? 2000.0 : 0.0,
      };
    }

    // Measure distance from rider destination to each real-time point along recommended map polyline
    double minDistToPolyline = double.infinity;
    int closestIdx = 0;
    final totalPoints = _routePolyline.length;

    for (int i = 0; i < totalPoints; i++) {
      final p = _routePolyline[i];
      final d = _calculateDistanceKm(riderDest, p);
      if (d < minDistToPolyline) {
        minDistToPolyline = d;
        closestIdx = i;
      }
    }

    // Progress ratio along the map route (0.0 = at pickup, 1.0 = at final destination)
    final progressRatio = totalPoints > 1 ? (closestIdx / (totalPoints - 1)).clamp(0.0, 1.0) : 1.0;

    // Triangle detour test:
    final distPickupToRider = _calculateDistanceKm(_pickupLatLng, riderDest);
    final distPickupToEnd = _calculateDistanceKm(_pickupLatLng, targetDest);
    final detourKm = (distPickupToRider + distToEndPoint) - distPickupToEnd;

    // Hexagon corridor criteria:
    // 1. Point is within 2.2 km of the real-time road polyline (corridor hexagon diameter)
    // 2. Or triangle detour <= 3.8 km along the forward path
    // 3. Or destination cluster proximity <= 5.5 km
    final isNearbyHexagon = minDistToPolyline <= 2.2;
    final isEnRoute = detourKm <= 3.8 && distPickupToRider <= (distPickupToEnd + 3.0);
    final isClusterMatch = distToEndPoint <= 5.5;

    final isMatch = isExact || isNearbyHexagon || isEnRoute || isClusterMatch;

    // Weight/Ranking algorithm:
    // "END POINT ER JOTO KACHER HEXACON SETAR WEIGHT TOTO BESI DHORE OITA TOP LISTED KOR"
    // - Exact destination: ~2000 weight
    // - Intermediate hexagon along route: higher score the closer to the END POINT (progressRatio -> 1.0, distToEnd -> 0)
    double score = 0.0;
    if (isExact) {
      score = 2000.0 - (distToEndPoint * 50.0);
    } else if (isMatch) {
      score = 1200.0 + (progressRatio * 600.0) - (distToEndPoint * 35.0) - (minDistToPolyline * 25.0);
    }

    return {
      'isMatch': isMatch,
      'isExact': isExact,
      'distToEndPoint': distToEndPoint,
      'minDistToRoute': minDistToPolyline,
      'progressRatio': progressRatio,
      'score': math.max(0.0, score),
    };
  }

  bool _isAlongSameCorridor(String targetDest, String riderDest) {
    final t = targetDest.toLowerCase().trim();
    final r = riderDest.toLowerCase().trim();

    if (r.contains(t) || t.contains(r)) return true;

    for (final corridor in _corridorWaypoints.values) {
      final tIndex = corridor.indexWhere((w) => t.contains(w) || w.contains(t));
      final rIndex = corridor.indexWhere((w) => r.contains(w) || w.contains(r));
      if (tIndex != -1 && rIndex != -1 && rIndex >= tIndex) return true;
    }

    try {
      final pTarget = LocationSearchService.lookupCoordinates(targetDest);
      final pRiderDest = LocationSearchService.lookupCoordinates(riderDest);
      final distToEnd = _calculateDistanceKm(pTarget, pRiderDest);
      if (distToEnd <= 5.5) return true;

      if (_routePolyline.isNotEmpty) {
        for (final p in _routePolyline) {
          if (_calculateDistanceKm(pRiderDest, p) <= 2.2) return true;
        }
      }
    } catch (_) {}

    return false;
  }

  List<RideModel> _getRankedMatchingRides() {
    final reqTime = widget.requestedTime;

    var candidates = widget.allAvailableRides.where((r) {
      if (_selectedAreaFilter != 'All Corridor') {
        final filter = _selectedAreaFilter.toLowerCase();
        final dest = r.destinationName.toLowerCase();
        if (!dest.contains(filter) && !(r.routeCorridor.toLowerCase().contains(filter))) {
          return false;
        }
      }
      return true;
    }).toList();

    // Map each candidate ride to its real-time polyline hexagon analysis
    final scores = <String, double>{};
    for (final r in candidates) {
      final analysis = _analyzeRideAlongRoute(r);
      double score = analysis['score'] as double;
      final timeDiff = (r.departureTime.difference(reqTime).inMinutes).abs();
      score += math.max(0, 180 - timeDiff);
      scores[r.id] = score;
    }

    // Sort descending: Rides nearest to the destination's end-point hexagon are at the top!
    candidates.sort((a, b) {
      final sA = scores[a.id] ?? 0.0;
      final sB = scores[b.id] ?? 0.0;
      return sB.compareTo(sA);
    });

    return candidates;
  }
  @override
  Widget build(BuildContext context) {
    final matchingRiders = _getRankedMatchingRides();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            width: 44,
            height: 4.5,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${widget.pickupName} ➔ ${widget.destinationName}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${matchingRiders.length} active commuter bikers matching your route',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Map View Showing Route & Waypoints
          SizedBox(
            height: 210,
            width: double.infinity,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _destLatLng,
                    zoom: 12.5,
                  ),
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    _fitMapBounds();
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer()),
                  },
                ),
                if (_isLoadingRoute)
                  Container(
                    color: Colors.white.withOpacity(0.7),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFFE65100)),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton.small(
                    heroTag: 'recenter_corridor',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE65100),
                    elevation: 3,
                    onPressed: _fitMapBounds,
                    child: const Icon(Icons.crop_free, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Area Filter Chips
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                'All Corridor',
                'Mirpur',
                'Uttara',
                'Dhaka University',
                'Motijheel',
                'Dhanmondi',
                'Savar',
              ].map((area) {
                final isSelected = _selectedAreaFilter.toLowerCase() == area.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(area),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE65100),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFFE65100) : Colors.transparent,
                    ),
                    onSelected: (val) {
                      setState(() {
                        _selectedAreaFilter = area;
                        _buildMapElements();
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // Matching Riders List (Prioritized)
          Expanded(
            child: matchingRiders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.two_wheeler_outlined, size: 48, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          Text(
                            'No riders listed for "${widget.destinationName}" right now',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Try selecting "All Corridor" or post a passenger ride request so bikers can accept your ride!',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                    itemCount: matchingRiders.length,
                    itemBuilder: (context, index) {
                      final ride = matchingRiders[index];
                      final isSelected = _selectedRide?.id == ride.id;

                      final target = widget.destinationName.toLowerCase();
                      final rideDest = ride.destinationName.toLowerCase();
                      final analysis = _analyzeRideAlongRoute(ride);
                      final isExact = analysis['isExact'] == true;
                      final isCorridorOverlap = analysis['isMatch'] == true || _isAlongSameCorridor(target, rideDest);
                      final progressPct = ((analysis['progressRatio'] as double? ?? 0.0) * 100).toInt();
                      final distToEnd = (analysis['distToEndPoint'] as double? ?? 0.0).toStringAsFixed(1);

                      // Format departure time
                      final depTime = ride.departureTime;
                      final timeStr =
                          '${depTime.hour > 12 ? depTime.hour - 12 : (depTime.hour == 0 ? 12 : depTime.hour)}:${depTime.minute.toString().padLeft(2, '0')} ${depTime.hour >= 12 ? 'PM' : 'AM'}';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFFF8E1) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFE65100)
                                : const Color(0xFFE2E8F0),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Match Badge
                              Row(
                                children: [
                                  if (isExact)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle, size: 12, color: Color(0xFF16A34A)),
                                          SizedBox(width: 4),
                                          Text(
                                            '🎯 Exact Destination Match',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF16A34A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isCorridorOverlap)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.hexagon_outlined, size: 12, color: Color(0xFF2563EB)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '⬡ On-Route Hexagon ($progressPct% to End • ~$distToEnd km away)',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '📍 Commute Route',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    '৳${ride.farePerSeat.toInt()} TK',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Biker Info Row
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFFFFE0B2),
                                    child: Text(
                                      ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'B',
                                      style: const TextStyle(
                                        color: Color(0xFFE65100),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              ride.driverName,
                                              style: const TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.verified, size: 13, color: Color(0xFF16A34A)),
                                          ],
                                        ),
                                        Text(
                                          '${ride.driverDept} • ⭐ ${ride.driverRating.toStringAsFixed(1)} • ${ride.vehicle.modelName}',
                                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                      ),
                                      const Text(
                                        'Departure',
                                        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Route Details
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.route, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${ride.originName} ➔ ${ride.destinationName}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (ride.vehicle.hasPassengerHelmet) ...[
                                      const SizedBox(width: 4),
                                      const Text(
                                        '🪖 Helmet',
                                        style: TextStyle(fontSize: 10.5, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Action Button: Book & Open Chat Negotiation
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context).pop();
                                    if (widget.onSelectRide != null) {
                                      widget.onSelectRide!(ride);
                                    } else {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: ride.id,
                                            driverName: ride.driverName,
                                            peerName: ride.driverName,
                                            peerPhone: ride.driverPhone,
                                            peerId: ride.driverId,
                                            vehicleModel: ride.vehicle.modelName,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                  label: const Text('Book & Confirm Ride in Chat'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
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
    );
  }
}
