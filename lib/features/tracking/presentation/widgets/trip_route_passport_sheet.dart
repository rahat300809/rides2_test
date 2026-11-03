import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';

class TripRoutePassportSheet extends StatefulWidget {
  final RideModel ride;
  final String? passengerName;
  final String? passengerPhone;
  final int elapsedSeconds;

  const TripRoutePassportSheet({
    super.key,
    required this.ride,
    this.passengerName,
    this.passengerPhone,
    this.elapsedSeconds = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required RideModel ride,
    String? passengerName,
    String? passengerPhone,
    int elapsedSeconds = 0,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TripRoutePassportSheet(
        ride: ride,
        passengerName: passengerName,
        passengerPhone: passengerPhone,
        elapsedSeconds: elapsedSeconds,
      ),
    );
  }

  @override
  State<TripRoutePassportSheet> createState() => _TripRoutePassportSheetState();
}

class _TripRoutePassportSheetState extends State<TripRoutePassportSheet> {
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final origin = LatLng(
      widget.ride.originLat != 0 ? widget.ride.originLat : 23.8765,
      widget.ride.originLng != 0 ? widget.ride.originLng : 90.3204,
    );
    final dest = LatLng(
      widget.ride.destinationLat != 0 ? widget.ride.destinationLat : 23.8069,
      widget.ride.destinationLng != 0 ? widget.ride.destinationLng : 90.3687,
    );

    final route = await LocationSearchService.getRoute(origin, dest);
    if (mounted) {
      setState(() {
        _routePoints = route.polylinePoints;
        _isLoading = false;
        _buildMarkers(origin, dest);
      });
    }
  }

  void _buildMarkers(LatLng origin, LatLng dest) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('trip_start'),
        position: origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Start: ${widget.ride.originName}'),
      ),
      Marker(
        markerId: const MarkerId('trip_end'),
        position: dest,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: 'End: ${widget.ride.destinationName}'),
      ),
    };

    final polylines = <Polyline>{
      if (_routePoints.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('exact_trip_route'),
          points: _routePoints,
          color: const Color(0xFFE65100),
          width: 5,
        ),
    };

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final rideCode = 'DIU-${r.id.replaceAll(RegExp(r'[^0-9]'), '').padRight(5, '7').substring(0, 5)}';
    final elapsedMin = widget.elapsedSeconds ~/ 60;
    final elapsedSec = widget.elapsedSeconds % 60;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4.5,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header: Trip Passport & Ride ID
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Official Trip Passport',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_outlined, size: 12, color: Color(0xFF16A34A)),
                                SizedBox(width: 3),
                                Text(
                                  'VERIFIED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            'Ride ID: #$rideCode',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: '#$rideCode'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ride ID copied!'),
                                  duration: Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF8E8E93)),
                          ),
                        ],
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

          // Live Route Map
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      r.originLat != 0 ? r.originLat : 23.8765,
                      r.originLng != 0 ? r.originLng : 90.3204,
                    ),
                    zoom: 12.0,
                  ),
                  onMapCreated: (ctrl) => _mapController = ctrl,
                  markers: _markers,
                  polylines: _polylines,
                  zoomControlsEnabled: false,
                  myLocationEnabled: true,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer()),
                  },
                ),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFE65100)),
                        const SizedBox(width: 4),
                        Text(
                          'Elapsed: ${elapsedMin.toString().padLeft(2, '0')}:${elapsedSec.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Passport Details
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // Road & Highway Corridor Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFEDD5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.alt_route, color: Color(0xFFE65100), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ROAD & ROUTE CORRIDOR',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.routeCorridor.isNotEmpty
                                  ? r.routeCorridor
                                  : '${r.originName} ➔ ${r.destinationName} Highway Link',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Journey Waypoints Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildRoutePoint(
                        label: 'Pickup Location',
                        value: r.originName,
                        sub: r.originSubtitle ?? 'Starting Boarding Spot',
                        color: const Color(0xFF16A34A),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 11),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 20,
                            child: VerticalDivider(width: 1, thickness: 1.5, color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                      _buildRoutePoint(
                        label: 'Dropoff Destination',
                        value: r.destinationName,
                        sub: r.destinationSubtitle ?? 'End Destination Spot',
                        color: const Color(0xFFE65100),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Rider & Passenger Cards
                Row(
                  children: [
                    // Rider
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('COMMUTER BIKER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            Text(r.driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            Text('${r.driverDept} • ${r.vehicle.modelName}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Passenger
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PASSENGER', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            Text(widget.passengerName ?? 'DIU Student', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            Text('Trip Fare: ৳${r.farePerSeat.toInt()} TK', style: const TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Share Route & Emergency Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                            text: 'DIU Ride Passport #$rideCode:\n${r.driverName} & ${widget.passengerName ?? "Passenger"}\nRoute: ${r.originName} ➔ ${r.destinationName}\nVehicle: ${r.vehicle.modelName}',
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Trip Passport details copied to share!'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('Share Trip'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Close Passport'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePoint({
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.3), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
              ),
              Text(
                sub,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
