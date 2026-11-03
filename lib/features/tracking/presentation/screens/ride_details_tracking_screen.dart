import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/rating/presentation/widgets/rate_ride_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_sos_dialog.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

class RideDetailsTrackingScreen extends ConsumerStatefulWidget {
  final String rideId;

  const RideDetailsTrackingScreen({
    super.key,
    required this.rideId,
  });

  @override
  ConsumerState<RideDetailsTrackingScreen> createState() => _RideDetailsTrackingScreenState();
}

class _RideDetailsTrackingScreenState extends ConsumerState<RideDetailsTrackingScreen> {
  int _seats = 1;
  bool _isReserved = false;
  WebSocketClient? _wsClient;
  StreamSubscription? _wsSub;
  GoogleMapController? _trackingMapController;

  double _driverLat = 23.8778;
  double _driverLng = 90.3235;
  int _etaMinutes = 5;
  double _distanceKm = 1.2;
  final String _roadInfo = 'Cruising along Birulia - Ashulia Road';

  // Real-time GPS Location Sharing & Start/End Tracing
  bool _isSharingLocation = false;
  double? _mySharedLat;
  double? _mySharedLng;

  double? _peerSharedLat;
  double? _peerSharedLng;
  String? _peerSharedName;
  String? _peerSharedRole;

  RideModel? _updatedRide;

  BitmapDescriptor? _bikerMarker;
  BitmapDescriptor? _pickupMarker;
  BitmapDescriptor? _destMarker;
  BitmapDescriptor? _passengerMarker;
  List<LatLng> _routePolyline = [];
  bool _hasFetchedPolyline = false;

  @override
  void initState() {
    super.initState();
    _initCustomMarkers();
    _connectRealtime();
  }

  Future<void> _initCustomMarkers() async {
    try {
      final biker = await _createCircleMarkerBitmap(
        emojiOrText: '🏍️',
        bgColor: const Color(0xFFE65100),
        borderColor: const Color(0xFFFFF3E0),
        size: 58,
      );
      final pickup = await _createCircleMarkerBitmap(
        emojiOrText: '🟢',
        bgColor: const Color(0xFF10B981),
        borderColor: const Color(0xFFD1FAE5),
        size: 46,
      );
      final dest = await _createCircleMarkerBitmap(
        emojiOrText: '🏁',
        bgColor: const Color(0xFFEF4444),
        borderColor: const Color(0xFFFEE2E2),
        size: 46,
      );
      final passenger = await _createCircleMarkerBitmap(
        emojiOrText: '🙋',
        bgColor: const Color(0xFF2563EB),
        borderColor: const Color(0xFFDBEAFE),
        size: 52,
      );
      if (mounted) {
        setState(() {
          _bikerMarker = biker;
          _pickupMarker = pickup;
          _destMarker = dest;
          _passengerMarker = passenger;
        });
      }
    } catch (e) {
      debugPrint('[RideDetailsTracking] Custom marker error: $e');
    }
  }

  static Future<BitmapDescriptor> _createCircleMarkerBitmap({
    required String emojiOrText,
    required Color bgColor,
    required Color borderColor,
    int size = 56,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Soft drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(size / 2, size / 2 + 1), size / 2 - 4, shadowPaint);

    // Outer white halo
    final ringPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 4, ringPaint);

    // Background circle
    final bgPaint = Paint()..color = bgColor;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6, bgPaint);

    // Border stroke
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6, borderPaint);

    // Text / Emoji painter
    final textPainter = TextPainter(
      text: TextSpan(
        text: emojiOrText,
        style: TextStyle(fontSize: size * 0.44),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2 - 1,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    return BitmapDescriptor.bytes(pngBytes);
  }

  Future<void> _fetchRoadPolyline(RideModel ride) async {
    if (ride.originLat == 0.0 || ride.destinationLat == 0.0) return;
    try {
      final origin = LatLng(ride.originLat, ride.originLng);
      final dest = LatLng(ride.destinationLat, ride.destinationLng);
      final route = await LocationSearchService.getRoute(origin, dest);
      if (mounted && route.polylinePoints.isNotEmpty) {
        setState(() {
          _routePolyline = route.polylinePoints;
        });
      }
    } catch (_) {}
  }

  void _connectRealtime() {
    _wsClient = WebSocketClient();
    _wsClient?.connect();
    _wsSub = _wsClient?.messages.listen((msg) {
      if (msg['event'] == 'driver_location_update') {
        final data = msg['data'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _driverLat = (data['latitude'] as num).toDouble();
            _driverLng = (data['longitude'] as num).toDouble();
            _etaMinutes = data['etaMinutes'] as int? ?? _etaMinutes;
            _distanceKm = (data['distanceRemainingKm'] as num?)?.toDouble() ?? _distanceKm;
          });
          _trackingMapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_driverLat, _driverLng)),
          );
        }
      } else if (msg['event'] == 'location_shared') {
        final data = msg['data'] as Map<String, dynamic>;
        if (data['rideId'] == widget.rideId && mounted) {
          final currentUserId = ref.read(authNotifierProvider).user?.id;
          final senderId = data['userId'];
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          if (senderId != currentUserId) {
            setState(() {
              _peerSharedLat = lat;
              _peerSharedLng = lng;
              _peerSharedName = data['userName'] as String? ?? 'Peer';
              _peerSharedRole = data['role'] as String? ?? 'Rider';
            });
            _showToast('${data['userName']} shared their live GPS location with Google Maps!');
          }
        }
      } else if (msg['event'] == 'ride_updated') {
        final data = msg['data'] as Map<String, dynamic>;
        if (data['id'] == widget.rideId && mounted) {
          try {
            final updated = RideModel.fromJson(data);
            setState(() {
              _updatedRide = updated;
            });
          } catch (_) {}
        }
      } else if (msg['event'] == 'ride_session_status_changed' || msg['event'] == 'ride_completed') {
        final data = msg['data'] is Map ? msg['data'] as Map<String, dynamic> : <String, dynamic>{};
        final rId = data['rideId'] ?? data['id'];
        final status = data['status']?.toString();
        if ((rId == widget.rideId || rId?.toString().contains(widget.rideId) == true) && status == 'completed' && mounted) {
          ref.invalidate(allAvailableRidesProvider);
          ref.invalidate(myBookingsProvider);
          _showToast('🏁 Trip completed and closed by rider!');
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsClient?.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primaryFixed, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(color: AppColors.inverseOnSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareMyLocation(RideModel ride) async {
    setState(() => _isSharingLocation = true);
    _showToast('Fetching device GPS coordinates...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? GpsLocationService.defaultCampusLat;
    final lng = pos?.longitude ?? GpsLocationService.defaultCampusLng;

    final user = ref.read(authNotifierProvider).user;
    final userId = user?.id ?? 'usr_current';
    final userName = user?.name ?? 'DIU Student';
    final role = (user?.id == ride.driverId) ? 'Driver' : 'Passenger';

    await ref.read(ridesRepositoryProvider).shareLiveLocation(
      rideId: ride.id,
      userId: userId,
      userName: userName,
      role: role,
      latitude: lat,
      longitude: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).shareLocation(lat, lng);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSharingLocation = false;
        _mySharedLat = lat;
        _mySharedLng = lng;
      });
      _showToast('GPS Location shared with Google Maps link!');
    }
  }

  Future<void> _startRideWithGps(RideModel ride) async {
    _showToast('Starting ride and recording GPS start point...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? ride.originLat;
    final lng = pos?.longitude ?? ride.originLng;
    final mapsLink = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);

    await ref.read(ridesRepositoryProvider).startRide(
      ride.id,
      startLat: lat,
      startLng: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).sendMessage(
        '🚀 [Trip Started] Rider has officially started the ride! Start GPS recorded: $mapsLink',
      );
    } catch (_) {}

    if (mounted) {
      _showToast('Ride Started! Start GPS & Google Maps link recorded.');
      ref.invalidate(searchRidesResultsProvider);
    }
  }

  Future<void> _completeRideWithGps(RideModel ride) async {
    _showToast('Completing ride and recording GPS end point...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? ride.destinationLat;
    final lng = pos?.longitude ?? ride.destinationLng;
    final mapsLink = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);

    await ref.read(ridesRepositoryProvider).completeRide(
      ride.id,
      endLat: lat,
      endLng: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).sendMessage(
        '🏁 [Trip Completed] Ride has arrived and completed successfully! Destination GPS recorded: $mapsLink',
      );
    } catch (_) {}

    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(allSystemRidesProvider);
    ref.invalidate(myPostedRidesProvider);
    ref.invalidate(myBookingsProvider);
    ref.invalidate(searchRidesResultsProvider);

    if (mounted) {
      _showToast('Ride Completed & Closed!');
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
              SizedBox(width: 8),
              Text('Trip Completed!'),
            ],
          ),
          content: Text(
            'Ride from ${ride.originName} to ${ride.destinationName} has been successfully completed and closed.',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Close Screen', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];
    final RideModel ride = _updatedRide ?? (
      allRides.cast<RideModel?>().firstWhere(
        (r) => r?.id == widget.rideId,
        orElse: () => null,
      ) ?? _defaultRide(widget.rideId)
    );

    final currentUser = ref.watch(authNotifierProvider).user;
    final appMode = ref.watch(appModeProvider);
    final isDriver = appMode.isRider || (
      currentUser != null && (
        ride.driverId == currentUser.id ||
        ride.driverId == currentUser.studentId ||
        (currentUser.phone.isNotEmpty && ride.driverPhone == currentUser.phone)
      )
    );

    final totalFare = (ride.farePerSeat * _seats).toInt();

    if (!_hasFetchedPolyline && ride.originLat != 0.0) {
      _hasFetchedPolyline = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchRoadPolyline(ride);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 20),
            const SizedBox(width: 8),
            Text(
              'Ride Details',
              style: AppTypography.headlineSm.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                SizedBox(width: 4),
                Text(
                  'DIU Verified',
                  style: TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP LIVE REALTIME TRACKING MAP VIEW (CLEAN & COMPACT)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
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
                child: Stack(
                  children: [
                    // Real Interactive Google Map with live driver and smooth route
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_driverLat, _driverLng),
                        zoom: 14.5,
                      ),
                      onMapCreated: (ctrl) {
                        _trackingMapController = ctrl;
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: false,
                      mapToolbarEnabled: false,
                      scrollGesturesEnabled: true,
                      zoomGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      gestureRecognizers: {
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      },
                      markers: _buildTrackingMarkers(ride),
                      polylines: _buildTrackingPolylines(ride),
                    ),

                    // Top Left: Minimal Live GPS Pill
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF16A34A),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Live GPS',
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

                    // Top Right Action Buttons: Recenter, External Maps, Campus SOS
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Recenter Camera
                          InkWell(
                            onTap: () {
                              _trackingMapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(_driverLat, _driverLng),
                                  15.5,
                                ),
                              );
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.96),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4),
                                ],
                              ),
                              child: const Icon(Icons.my_location, size: 16, color: Color(0xFFE65100)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // External Google Maps directions
                          InkWell(
                            onTap: () async {
                              final url = Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&origin=${ride.originLat},${ride.originLng}&destination=${ride.destinationLat},${ride.destinationLng}&travelmode=driving',
                              );
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.96),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4),
                                ],
                              ),
                              child: const Icon(Icons.directions, size: 16, color: Color(0xFF2563EB)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Compact Campus SOS
                          InkWell(
                            onTap: () {
                              CampusSosDialog.show(
                                context: context,
                                onConfirmed: () {
                                  _showToast('Connecting to DIU Smart Campus Security Hotline...');
                                },
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFFDC2626).withOpacity(0.3), blurRadius: 4),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield, color: Colors.white, size: 12),
                                  SizedBox(width: 3),
                                  Text(
                                    'SOS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Floating ETA Glass Pill (Bottom) - Sleek & Compact
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.near_me, color: Color(0xFFE65100), size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_etaMinutes mins away • ${_distanceKm.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    _roadInfo,
                                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'On Time',
                                style: TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
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
            const SizedBox(height: 12),

            if (isDriver) ...[
              // RIDER COMMAND DASHBOARD (CLEAN & PROFESSIONAL)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Offered Ride',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                ),
                                Text(
                                  '${ride.vehicle.modelName.isNotEmpty ? ride.vehicle.modelName : "Motorbike"} • ${ride.vehicle.licensePlate}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65100).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '৳${ride.farePerSeat.toInt()} / seat',
                            style: const TextStyle(
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.navigation, size: 13, color: Color(0xFF10B981)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${ride.originName} ➔ ${ride.destinationName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          'Leaving at ${ride.departureTime.hour.toString().padLeft(2, '0')}:${ride.departureTime.minute.toString().padLeft(2, '0')} (${ride.durationMinutes} mins)',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.event_seat, size: 12, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '${ride.availableSeats} of ${ride.totalSeats} seats open',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDriverMissionControlCard(ride, ref),
            ] else ...[
              // PASSENGER COMMUTER VIEW - CLEAN, POLISHED, AIRY CARDS
              // 1. RIDER PROFILE CARD
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFFFE0B2),
                          child: Text(
                            ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'R',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFE65100),
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
                                  Flexible(
                                    child: Text(
                                      ride.driverName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, size: 15, color: Color(0xFF16A34A)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ride.driverDept} • ★ ${ride.driverRating.toStringAsFixed(1)} (${ride.driverRideCount} rides)',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Quick Connect Triggers: Chat, Buzzer & Call
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Chat
                            InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: ride.id,
                                      peerName: ride.driverName,
                                      vehicleModel: ride.vehicle.modelName,
                                      peerPhone: ride.driverPhone,
                                      peerRole: 'Driver',
                                      peerId: ride.driverId,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.chat_bubble_outline, color: Color(0xFF0F172A), size: 16),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Ring Buzzer
                            InkWell(
                              onTap: () => _triggerAlertRingFromTracking(ride),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFF7ED),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.notifications_none, color: Color(0xFFEA580C), size: 16),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Call
                            InkWell(
                              onTap: () {
                                final phone = ride.driverPhone;
                                DirectCallService.showCallOptions(
                                  context,
                                  phoneNumber: (phone != null && phone.isNotEmpty) ? phone : '01712345678',
                                  peerName: ride.driverName,
                                  peerRole: 'Driver',
                                );
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDCFCE7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.phone_outlined, color: Color(0xFF16A34A), size: 16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Single clean trust banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.school_outlined, size: 14, color: Color(0xFF64748B)),
                          SizedBox(width: 5),
                          Text(
                            'DIU Batch Verified Peer',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                          Spacer(),
                          Icon(Icons.shield_outlined, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'Safety Assured',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. VEHICLE DETAILS & AMENITIES CARD
              InkWell(
                onTap: () => _showVehicleSpecsAndSafetySheet(context, ride),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
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
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        ride.vehicle.modelName.isNotEmpty ? ride.vehicle.modelName : 'Campus Motorbike',
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFE65100)),
                                  ],
                                ),
                                Text(
                                  '${ride.vehicle.color} • ${ride.vehicle.licensePlate}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 12, color: Color(0xFF16A34A)),
                                SizedBox(width: 3),
                                Text(
                                  'DIU Sticker OK',
                                  style: TextStyle(
                                    color: Color(0xFF16A34A),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildCompactChip(Icons.sports_motorsports_outlined, 'Helmet Available', const Color(0xFF10B981)),
                          _buildCompactChip(Icons.verified_outlined, 'Campus Verified Bike', const Color(0xFF2563EB)),
                          _buildCompactChip(Icons.bolt, 'Express Route', const Color(0xFFF59E0B)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 3. COMMUTE ITINERARY SCHEDULE TIMELINE CARD
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Route Itinerary',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${ride.distanceKm} km • ${ride.durationMinutes} mins',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Vertical Timeline Stepper
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                            ),
                            Container(
                              width: 2,
                              height: 38,
                              color: const Color(0xFFCBD5E1),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      ride.originName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${ride.departureTime.hour.toString().padLeft(2, '0')}:${ride.departureTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Text(
                                ride.originSubtitle ?? 'Campus Pickup Spot',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      ride.destinationName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Text(
                                    'Est. Dropoff',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Text(
                                ride.destinationSubtitle ?? 'Dropoff Location',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. UNIFIED PASSENGER BOOKING & FARE CARD
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fare Contribution',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '৳${ride.farePerSeat.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '/ seat',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Clean Seat Selector
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: _seats > 1 ? () => setState(() => _seats--) : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _seats > 1 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Icon(Icons.remove, size: 14, color: _seats > 1 ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '$_seats',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                              ),
                              InkWell(
                                onTap: _seats < ride.availableSeats ? () => setState(() => _seats++) : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _seats < ride.availableSeats ? const Color(0xFFE65100) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.add, size: 14, color: _seats < ride.availableSeats ? Colors.white : const Color(0xFFCBD5E1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    // Booking CTA Button
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _isReserved = true);
                        _showToast('Seat Reserved! Driver ${ride.driverName} notified.');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isReserved ? const Color(0xFF16A34A) : const Color(0xFFE65100),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isReserved ? Icons.check_circle : Icons.two_wheeler, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _isReserved ? 'Seat Confirmed • Awaiting Pickup' : 'Reserve Seat (৳$totalFare)',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    if (_isReserved) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: ride.id,
                                      peerName: ride.driverName,
                                      vehicleModel: ride.vehicle.modelName,
                                      peerPhone: ride.driverPhone,
                                      peerRole: 'Driver',
                                      peerId: ride.driverId,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline, size: 15),
                              label: const Text('Chat with Driver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE65100),
                                side: const BorderSide(color: Color(0xFFE65100)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final phone = ride.driverPhone;
                                DirectCallService.showCallOptions(
                                  context,
                                  phoneNumber: (phone != null && phone.isNotEmpty) ? phone : '01712345678',
                                  peerName: ride.driverName,
                                  peerRole: 'Driver',
                                );
                              },
                              icon: const Icon(Icons.call, size: 15),
                              label: const Text('Call Driver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Clean secondary actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () {
                            _showToast('Live tracking link created for Guardian via WhatsApp');
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.share_location, size: 14, color: Color(0xFF64748B)),
                              SizedBox(width: 4),
                              Text(
                                'Share with Guardian',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            RateRideSheet.show(
                              context: context,
                              rideId: ride.id,
                              driverName: ride.driverName,
                              onSubmit: (rating, feedback, tags) {
                                _showToast('Review submitted! Thank you.');
                              },
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.star_outline, size: 14, color: Color(0xFF64748B)),
                              SizedBox(width: 4),
                              Text(
                                'Rate Trip',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmCancelRide(RideModel ride) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Offered Ride?'),
        content: const Text('Are you sure you want to cancel this trip? Any pending requests will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep Trip')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(ridesRepositoryProvider).cancelOfferedRide(ride.id);
              ref.invalidate(departingSoonRidesProvider);
              ref.invalidate(searchRidesResultsProvider);
              ref.invalidate(allAvailableRidesProvider);
              _showToast('Trip cancelled successfully.');
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverMissionControlCard(RideModel ride, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));
    final bookings = bookingsAsync.value ?? [];

    Color statusColor;
    String statusText;
    switch (ride.status) {
      case RideStatus.published:
        statusColor = const Color(0xFFE65100);
        statusText = 'OFFERED & READY';
        break;
      case RideStatus.active:
      case RideStatus.occupied:
        statusColor = const Color(0xFF2E7D32);
        statusText = ride.status == RideStatus.occupied
            ? 'CONFIRMED WITH STUDENT'
            : 'IN PROGRESS (STARTED)';
        break;
      case RideStatus.completed:
        statusColor = const Color(0xFF00897B);
        statusText = 'COMPLETED (SAVED TO CSV)';
        break;
      case RideStatus.cancelled:
        statusColor = const Color(0xFFD32F2F);
        statusText = 'CANCELLED';
        break;
      case RideStatus.suspended:
        statusColor = const Color(0xFFB45309);
        statusText = 'SUSPENDED • NO CONFIRM';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Driver Badge & Trip Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.sports_motorsports, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Mission Control',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF141416),
                        ),
                      ),
                      Text(
                        'Manage your shared trip & passengers',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Passenger Requests & Confirmation Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt, size: 16, color: Color(0xFFE65100)),
                        const SizedBox(width: 6),
                        Text(
                          'Passenger Bookings (${bookings.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ],
                    ),
                    Text(
                      '${ride.availableSeats} of ${ride.totalSeats} seats left',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (bookings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Waiting for DIU peers to request seats on this trip.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                  )
                else
                  ...bookings.map((b) {
                    final isPending = b.status == BookingStatus.requested;
                    final isAccepted = b.status == BookingStatus.accepted;

                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAccepted
                              ? const Color(0xFF4CAF50).withOpacity(0.5)
                              : isPending
                                  ? const Color(0xFFFF9800).withOpacity(0.5)
                                  : const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                                child: Text(
                                  b.passengerName.isNotEmpty ? b.passengerName[0].toUpperCase() : 'P',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.passengerName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Pickup: ${b.pickupPoint} • ${b.seatsBooked} seat(s) • ৳${b.totalFare.toInt()}',
                                      style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isAccepted
                                      ? const Color(0xFFE8F5E9)
                                      : isPending
                                          ? const Color(0xFFFFF3E0)
                                          : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  b.status.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isAccepted
                                        ? const Color(0xFF2E7D32)
                                        : isPending
                                            ? const Color(0xFFE65100)
                                            : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // If pending: Confirm, Chat, or Decline buttons
                          if (isPending) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await ref.read(bookingNotifierProvider.notifier).acceptBooking(
                                            bookingId: b.id,
                                            rideId: ride.id,
                                            driverName: ride.driverName,
                                            pickupPoint: b.pickupPoint,
                                          );
                                      ref.invalidate(rideBookingsProvider(ride.id));
                                      _showToast('Booking Confirmed for ${b.passengerName}!');
                                    },
                                    icon: const Icon(Icons.check, size: 14),
                                    label: const Text('Confirm', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: ride.id,
                                            peerName: b.passengerName,
                                            peerPhone: b.passengerPhone,
                                            peerRole: 'Passenger',
                                            peerId: b.passengerId,
                                            vehicleModel: ride.vehicle.modelName,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                    label: const Text('Chat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFE65100),
                                      side: const BorderSide(color: Color(0xFFE65100)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await ref.read(bookingNotifierProvider.notifier).rejectBooking(
                                          bookingId: b.id,
                                          rideId: ride.id,
                                          driverName: ride.driverName,
                                        );
                                    ref.invalidate(rideBookingsProvider(ride.id));
                                    _showToast('Declined request from ${b.passengerName}.');
                                  },
                                  icon: const Icon(Icons.close, size: 14),
                                  label: const Text('Decline', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD32F2F),
                                    side: const BorderSide(color: Color(0xFFD32F2F)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // If accepted: Chat and Call buttons
                          if (isAccepted) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          rideId: ride.id,
                                          peerName: b.passengerName,
                                          peerPhone: b.passengerPhone,
                                          peerRole: 'Passenger',
                                          peerId: b.passengerId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline, size: 13),
                                  label: const Text('Chat & Ring', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFE65100),
                                    side: const BorderSide(color: Color(0xFFE65100)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    DirectCallService.showCallOptions(
                                      context,
                                      phoneNumber: b.passengerPhone,
                                      peerName: b.passengerName,
                                      peerRole: 'Passenger',
                                    );
                                  },
                                  icon: const Icon(Icons.call, size: 13),
                                  label: const Text('Call', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2E7D32),
                                    side: const BorderSide(color: Color(0xFF2E7D32)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Primary Driver Action Buttons: GPS, Start, End, Cancel
          // 1. Share GPS
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharingLocation ? null : () => _shareMyLocation(ride),
              icon: _isSharingLocation
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.share_location, size: 18),
              label: Text(
                _isSharingLocation ? 'Sharing GPS...' : 'Share My Live GPS with Passenger',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Start Trip or End Trip depending on status
          if (ride.status == RideStatus.published) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startRideWithGps(ride),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text(
                  'Start Trip (Record Start GPS & Time)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancelRide(ride),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Cancel Offered Ride',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD32F2F),
                  side: const BorderSide(color: Color(0xFFD32F2F), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else if (ride.status == RideStatus.active) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _completeRideWithGps(ride),
                icon: const Icon(Icons.flag, size: 20),
                label: const Text(
                  'End Trip (Record End GPS & Auto-save CSV)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else if (ride.status == RideStatus.completed) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip completed successfully. All rider, passenger, GPS & timing data saved to database & completed_trips.csv.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildCompactChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  void _showVehicleSpecsAndSafetySheet(BuildContext context, RideModel ride) {
    final vehicleName = ride.vehicle.modelName.isNotEmpty ? ride.vehicle.modelName : 'Yamaha R15 V4 (Campus Edition)';
    final vehicleColor = ride.vehicle.color.isNotEmpty ? ride.vehicle.color : 'Matte Blue Metallic';
    final licensePlate = ride.vehicle.licensePlate.isNotEmpty ? ride.vehicle.licensePlate : 'Dhaka Metro-HA 24-8891';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              vehicleName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'VERIFIED',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$vehicleColor • $licensePlate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            const Text(
              'Included Amenities & Safety Equipment',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _buildSpecFeatureTile(
              icon: Icons.sports_motorsports,
              iconColor: const Color(0xFF10B981),
              title: 'Fresh & Sanitized Helmet Included 🪖',
              subtitle: 'Disinfected passenger helmet with anti-scratch visor and clean inner padding provided on every trip.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.pan_tool_alt,
              iconColor: const Color(0xFF0284C7),
              title: 'Dual Grab Rails & Foot-pegs 🏍️',
              subtitle: 'Ergonomic pillion seating with sturdy aluminium rear grab rails for high-speed stability and comfort.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.verified_user,
              iconColor: const Color(0xFFE65100),
              title: 'DIU Varsity Security Gate Sticker 🛡️',
              subtitle: 'Authorized campus sticker ensuring seamless transit past university security checkpoints without delays.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.clean_hands,
              iconColor: const Color(0xFFE65100),
              title: 'Sanitized Commute Guarantee 🧼',
              subtitle: 'Contact points, seat, and handles sanitized before every peer journey.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Understood & Verified (সব ঠিক আছে)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerAlertRingFromTracking(RideModel ride) async {
    final user = ref.read(authNotifierProvider).user;
    final senderName = user?.name ?? 'Commuter';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = ride.driverPhone?.isNotEmpty == true
        ? ride.driverPhone!
        : (ride.driverId.isNotEmpty ? ride.driverId : ride.driverName);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 38),
            ),
            const SizedBox(height: 16),
            Text(
              'Ringing ${ride.driverName}...',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Dedicated alert buzzer is ringing on their phone. Tap Stop to cancel at any time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.call_end, size: 20),
                label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: () async {
                  NotificationSoundService.stopRinging();
                  try {
                    await ref.read(ridesRepositoryProvider).stopAlertRing(
                      targetUserId: targetId,
                      senderId: user?.id,
                      ringId: ringId,
                    );
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    _showToast('Ringing stopped.');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: targetId,
        targetName: ride.driverName,
        senderId: user?.id ?? '',
        senderName: senderName,
        rideId: ride.id,
        ringId: ringId,
        message: '🚨 Urgent: $senderName is ringing you for pickup!',
      );
    } catch (_) {}
  }

  static RideModel _defaultRide(String rideId) => RideModel(
    id: rideId,
    driverId: '',
    driverName: 'DIU Verified Driver',
    driverDept: 'DIU Student Commuter',
    driverRating: 5.0,
    driverRideCount: 1,
    originName: 'Daffodil Knowledge City',
    originSubtitle: 'Campus Main Gate (DSC)',
    originLat: 23.8769,
    originLng: 90.3204,
    destinationName: 'Destination',
    destinationSubtitle: 'Dhaka',
    destinationLat: 23.8710,
    destinationLng: 90.3800,
    departureTime: DateTime.now().add(const Duration(minutes: 15)),
    farePerSeat: 50.0,
    totalSeats: 3,
    availableSeats: 2,
    vehicle: const VehicleModel(
      id: 'v_campus',
      type: VehicleType.bike,
      modelName: 'Campus Commute Vehicle',
      color: 'Green',
      licensePlate: 'Verified DIU',
      hasAc: false,
    ),
    distanceKm: 12.0,
    durationMinutes: 25,
  );

  Set<Marker> _buildTrackingMarkers(RideModel ride) {
    final markers = <Marker>{};

    // Driver live position (compact micro-marker)
    markers.add(
      Marker(
        markerId: const MarkerId('driver_live'),
        position: LatLng(_driverLat, _driverLng),
        icon: _bikerMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: '🏍️ ${ride.driverName} (Live Biker)',
          snippet: 'ETA: $_etaMinutes mins away • ${_distanceKm.toStringAsFixed(1)} km',
        ),
      ),
    );

    // Origin / Pickup (compact micro-marker)
    markers.add(
      Marker(
        markerId: const MarkerId('origin_pin'),
        position: LatLng(ride.originLat, ride.originLng),
        icon: _pickupMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: '🟢 Pickup: ${ride.originName}',
        ),
      ),
    );

    // Destination (compact micro-marker)
    markers.add(
      Marker(
        markerId: const MarkerId('destination_pin'),
        position: LatLng(ride.destinationLat, ride.destinationLng),
        icon: _destMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: '🏁 Destination: ${ride.destinationName}',
        ),
      ),
    );

    // Peer shared GPS if any
    if (_peerSharedLat != null && _peerSharedLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('peer_shared_gps'),
          position: LatLng(_peerSharedLat!, _peerSharedLng!),
          icon: _passengerMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: '📍 ${_peerSharedName ?? "Peer"} (Live GPS)',
            snippet: _peerSharedRole ?? 'Passenger',
          ),
        ),
      );
    }

    // My shared GPS if any
    if (_mySharedLat != null && _mySharedLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_shared_gps'),
          position: LatLng(_mySharedLat!, _mySharedLng!),
          icon: _passengerMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(
            title: '👤 My Live GPS',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildTrackingPolylines(RideModel ride) {
    final points = _routePolyline.isNotEmpty
        ? _routePolyline
        : [
            LatLng(ride.originLat, ride.originLng),
            LatLng(ride.destinationLat, ride.destinationLng),
          ];

    return {
      Polyline(
        polylineId: const PolylineId('ride_active_route'),
        points: points,
        color: const Color(0xFFE65100),
        width: 4,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }
}
