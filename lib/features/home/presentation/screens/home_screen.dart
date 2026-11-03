import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/home/presentation/widgets/unified_commute_card.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/rides/presentation/widgets/rider_route_fare_setup_sheet.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';
import 'package:diu_ride/features/home/presentation/widgets/commute_corridor_matching_sheet.dart';
import 'package:diu_ride/shared/widgets/liquid_glass_3d_toggle.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_expiry_extension_dialog.dart';
import 'package:diu_ride/features/ai_assistant/presentation/widgets/mini_floating_ai_badge.dart';
import 'package:diu_ride/features/map/presentation/screens/full_screen_commute_map_screen.dart';


class HomeScreen extends ConsumerStatefulWidget {
  final Function(int tabIndex) onNavigateTab;
  final Function(String query) onSearchQuery;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
    required this.onSearchQuery,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _activeSearchQuery = '';
  String _activeRiderDestination = '';
  String _currentLocation = 'DIU Smart City, Ashulia';
  Uint8List? _profilePhotoBytes;

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('profile_photo_b64');
    if (b64 != null && b64.isNotEmpty) {
      try {
        if (mounted) {
          setState(() => _profilePhotoBytes = base64Decode(b64));
        }
      } catch (_) {}
    }
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Campus Pickup Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose your current boarding spot on DIU Campus',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ...CampusLocations.allCampusSpots.map((spot) => ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place, color: Color(0xFFE65100), size: 20),
              ),
              title: Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(spot.subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
              trailing: _currentLocation == spot.name
                  ? const Icon(Icons.check_circle, color: Color(0xFFE65100))
                  : null,
              onTap: () {
                setState(() => _currentLocation = spot.name);
                Navigator.pop(ctx);
                _showToast('Location Updated', 'Pickup set to ${spot.name}');
              },
            )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showToast(String title, String subtitle) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD84315), Color(0xFFFFA000)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.two_wheeler, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLg.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.labelSm.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRequestSeat(RideModel ride) {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'book a seat')) return;
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        _showToast(
          'Moto Seat Requested!',
          'Booking sent to ${ride.driverName} • Fare: ৳${ride.farePerSeat.toInt()} (1 seat)',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final appMode = ref.watch(appModeProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final List<RideModel> allRides = allRidesAsync.value ?? [];

    final unreadNotificationCount = ref.watch(unreadNotificationCountProvider);



    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: const MiniFloatingAiBadge(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            color: const Color(0xFFE65100),
            onRefresh: () async {
              ref.invalidate(departingSoonRidesStreamProvider);
              ref.invalidate(departingSoonRidesProvider);
              ref.invalidate(allAvailableRidesProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              // 1. Radiant Sunset Amber Header (Directly Matching Reference Images)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFFE65100), // Rich Sunset Amber
                      Color(0xFFF57C00), // Vibrant Orange
                      Color(0xFFFFB74D), // Golden Peach Glow
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x28E65100),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 10,
                  20,
                  22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: User Avatar, Current Location & Glass Action Buttons (Mobile-Responsive)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: User Avatar + Current Location Dropdown (Auto-flexing for mobile)
                        Expanded(
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                  ).then((_) => _loadProfilePhoto());
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: CircleAvatar(
                                        radius: 19,
                                        backgroundColor: const Color(0xFF141416),
                                        backgroundImage: _profilePhotoBytes != null
                                            ? MemoryImage(_profilePhotoBytes!)
                                            : null,
                                        child: _profilePhotoBytes == null
                                            ? Text(
                                                user?.name.isNotEmpty == true
                                                    ? user!.name[0].toUpperCase()
                                                    : 'S',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF006699),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          size: 9,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showLocationPicker,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Current Location',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _currentLocation,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          const Icon(Icons.keyboard_arrow_down, size: 15, color: Color(0xFFE65100)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Right: Notification Bell, 3D Mode Toggle & AI Guide Button
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Translucent Glass Notification Bell Button with badge
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                                );
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x28E65100),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(Icons.notifications_none, size: 19, color: Color(0xFF0F172A)),
                                    if (unreadNotificationCount > 0)
                                      Positioned(
                                        top: 5,
                                        right: 5,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF3B30),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Modern 3D Liquid Glass Mode Toggle (Passenger ↔ Rider)
                            const LiquidGlass3DToggle(width: 120, height: 32),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Greeting Headline on Sunset Gradient with dedicated Live Map Action
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ProfileScreen()),
                              ).then((_) => _loadProfilePhoto());
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Hello, ${user?.name.split(" ").first ?? "Student"}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Profile', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                      SizedBox(width: 2),
                                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 9),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Dedicated Live Map Action Pill
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const FullScreenCommuteMapScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.35)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 5),
                                Text(
                                  'Live Map',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appMode.isPassenger
                          ? 'Passenger Mode • Instant corridor & ride matching'
                          : 'Rider Mode • Ready to offer rides & pick up peers',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Active Trip Passport Floating Banner (If in active ride session)
              // Unified Elegant Commute Card (Shared seamlessly between Passenger and Rider)
              UnifiedCommuteCard(
                initialPickup: _currentLocation,
                initialDropoff: appMode.isRider ? _activeRiderDestination : _activeSearchQuery,
                onShowLocationPicker: _showLocationPicker,
                onPostCustomRequest: () => PostRideRequestSheet.show(context),
                onBrowseStudentGigs: () => widget.onNavigateTab(1),
                onPassengerSearch: ({
                  required String pickup,
                  required String dropoff,
                  required DateTime departureTime,
                  required bool isNow,
                }) {
                  setState(() {
                    _currentLocation = pickup;
                    _activeSearchQuery = dropoff;
                  });
                  CommuteCorridorMatchingSheet.show(
                    context,
                    pickupName: pickup,
                    destinationName: dropoff,
                    requestedTime: departureTime,
                    allAvailableRides: allRides,
                    onSelectRide: (ride) {
                      _handleRequestSeat(ride);
                    },
                  );
                },
                onRiderOfferProceed: ({
                  required String pickup,
                  required String dropoff,
                  required DateTime departureTime,
                  required bool isNow,
                }) async {
                  final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
                  if (!ok || !context.mounted) return;
                  setState(() {
                    _currentLocation = pickup;
                    _activeRiderDestination = dropoff;
                  });
                  if (!context.mounted) return;
                  RiderRouteFareSetupSheet.show(
                    context,
                    originName: pickup,
                    destinationName: dropoff,
                    departureTime: departureTime,
                    onRidePublished: () {
                      setState(() {
                        _activeRiderDestination = dropoff;
                      });
                      ref.invalidate(myPostedRidesProvider);
                      ref.invalidate(allAvailableRidesProvider);
                    },
                  );
                },
              ),

              // 4. Rider Mode: Biker's Posted Rides & Live Status Checking Section (Only shown if active shared rides exist)
              if (appMode.isRider)
                _buildRiderPostedRidesSection(),

              // 5. Booked / Confirmed Rides for Later (Placed at bottom, only shown when user has a booked/confirmed ride)
              _buildBookedConfirmedRidesBottomSection(),

              // Pushes the banner all the way down to the bottom of the viewport
              const Spacer(),

              // 6. Official DIU University Campus Footer Banner (Anchored cleanly at bottom)
              _buildCampusFooterBanner(),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    ),
  );
},
),
);
  }

  /// Official DIU University Campus Footer Banner
  Widget _buildCampusFooterBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/diu_footer_banner.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/diu_footer_banner.jpg',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          );
        },
      ),
    );
  }

  /// Booked or Confirmed Rides for Later (Rendered at bottom of Home Screen)
  /// Only renders when the student has a real booked or confirmed ride for later.
  Widget _buildBookedConfirmedRidesBottomSection() {
    final appMode = ref.watch(appModeProvider);
    final bookingsAsync = ref.watch(myBookingsProvider);
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];
    final currentUser = ref.watch(authNotifierProvider).user;
    final myPostedRides = ref.watch(myPostedRidesProvider).value ?? [];

    // 1. Passenger: Check if there is an active booked or requested ride
    final activeBooking = appMode.isRider
        ? null
        : bookingsAsync.value?.cast<BookingModel?>().firstWhere(
              (b) {
                if (b == null) return false;
                if (b.status != BookingStatus.accepted && b.status != BookingStatus.requested) return false;
                // Verify the underlying ride is still valid and not cancelled
                final ride = allRides.cast<RideModel?>().firstWhere(
                  (r) => r?.id == b.rideId,
                  orElse: () => null,
                );
                if (ride != null && (ride.status == RideStatus.cancelled || ride.status == RideStatus.completed)) {
                  return false;
                }
                return true;
              },
              orElse: () => null,
            );

    // 2. Rider: Check if biker has an active / scheduled ride with confirmed passengers
    final activeOfferedRide = appMode.isPassenger
        ? null
        : (myPostedRides.cast<RideModel?>().firstWhere(
              (r) => (r?.status == RideStatus.active),
              orElse: () => null,
            ) ??
            allRides.cast<RideModel?>().firstWhere(
              (r) => r?.status == RideStatus.active &&
                     currentUser != null &&
                     (r?.driverId == currentUser.id || r?.driverId == currentUser.studentId || (currentUser.phone.isNotEmpty && r?.driverPhone == currentUser.phone)),
              orElse: () => null,
            ));

    final myRequests = appMode.isRider
        ? []
        : (ref.watch(myPassengerRequestsProvider).value ?? []);
    final activePassengerReq = myRequests.isNotEmpty ? myRequests.first : null;

    // If neither exists, DO NOT show anything (no fake card, no idle clutter!)
    if (activeBooking == null && activeOfferedRide == null && activePassengerReq == null) {
      return const SizedBox.shrink();
    }

    if (activePassengerReq != null && activeBooking == null && activeOfferedRide == null) {
      return _buildActivePassengerRequestHomeCard(activePassengerReq);
    }

    if (activeBooking != null) {
      final matchingRide = allRides.firstWhere(
        (r) => r.id == activeBooking.rideId,
        orElse: () => RideModel(
          id: activeBooking.rideId,
          driverId: 'drv',
          driverName: 'Assigned Rider',
          driverDept: 'CSE',
          vehicle: const VehicleModel(
            id: 'veh_01',
            type: VehicleType.bike,
            modelName: 'Motorbike',
            color: 'Black',
            licensePlate: 'Dhaka Metro',
          ),
          originName: activeBooking.pickupPoint,
          originLat: 23.8765,
          originLng: 90.3204,
          destinationName: activeBooking.dropoffPoint,
          destinationLat: 23.8728,
          destinationLng: 90.3984,
          departureTime: DateTime.now(),
          farePerSeat: activeBooking.totalFare,
          totalSeats: 1,
          availableSeats: 0,
        ),
      );

      final isConfirmed = activeBooking.status == BookingStatus.accepted;

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFFF9800),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFFFF9800)).withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConfirmed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConfirmed ? 'CONFIRMED RIDE FOR LATER' : 'SEAT REQUEST PENDING',
                        style: TextStyle(
                          color: isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '৳${activeBooking.totalFare.toInt()}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Cancel & Dismiss Request',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFF9E9E9E)),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Cancel Ride Request?', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('Are you sure you want to cancel and remove this assigned rider request?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Cancel Request'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(bookingNotifierProvider.notifier).cancelBooking(activeBooking.id);
                      ref.invalidate(myBookingsProvider);
                      ref.invalidate(allAvailableRidesProvider);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ride request cancelled and removed.'),
                          backgroundColor: Color(0xFFD32F2F),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFFFE0B2),
                  child: Text(
                    matchingRide.driverName.isNotEmpty ? matchingRide.driverName[0].toUpperCase() : 'D',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
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
                              matchingRide.driverName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: Color(0xFF10B981)),
                        ],
                      ),
                      Text(
                        '${matchingRide.driverDept} • ${matchingRide.vehicle.modelName} (${matchingRide.vehicle.color})',
                        style: TextStyle(color: Colors.grey[700], fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${activeBooking.pickupPoint} ➔ ${activeBooking.dropoffPoint}',
                        style: const TextStyle(color: Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideDetailsTrackingScreen(rideId: activeBooking.rideId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.location_on, size: 15),
                    label: const Text('Track Live GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: activeBooking.rideId,
                          peerName: matchingRide.driverName,
                          driverName: matchingRide.driverName,
                          peerPhone: matchingRide.driverPhone,
                          peerRole: 'Driver',
                          peerId: matchingRide.driverId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Cancel Request?', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('Cancel and remove this assigned rider request?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(bookingNotifierProvider.notifier).cancelBooking(activeBooking.id);
                      ref.invalidate(myBookingsProvider);
                      ref.invalidate(allAvailableRidesProvider);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request cancelled.'),
                          backgroundColor: Color(0xFFD32F2F),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD32F2F),
                    side: const BorderSide(color: Color(0xFFFFCDD2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Active Ride for Rider
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.two_wheeler, size: 14, color: Color(0xFF2E7D32)),
                    SizedBox(width: 6),
                    Text(
                      'ACTIVE TRIP IN PROGRESS',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '৳${activeOfferedRide!.farePerSeat.toInt()}/seat',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Route: ${activeOfferedRide.originName} ➔ ${activeOfferedRide.destinationName}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RideDetailsTrackingScreen(rideId: activeOfferedRide.id),
                ),
              );
            },
            icon: const Icon(Icons.share_location, size: 16),
            label: const Text('Live Trip Tracking & Complete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(double.infinity, 40),
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildActivePassengerRequestHomeCard(dynamic rawReq) {
    final PassengerRequestModel req = rawReq is PassengerRequestModel
        ? rawReq
        : PassengerRequestModel.fromJson(Map<String, dynamic>.from(rawReq as Map));
    final isAccepted = req.status == 'accepted';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAccepted ? const Color(0xFF10B981) : const Color(0xFFFF9800),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isAccepted ? const Color(0xFF10B981) : const Color(0xFFFF9800)).withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Status Badge & Proposed Fare
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAccepted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAccepted ? Icons.check_circle : Icons.sensors,
                      size: 13,
                      color: isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isAccepted ? 'BIKER ACCEPTED' : 'BROADCASTING TO BIKERS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '৳${req.proposedFare.toInt()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Route: Pickup -> Dropoff
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const SizedBox(height: 3),
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                  Container(width: 2, height: 22, color: const Color(0xFFD1D5DB)),
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFE65100))),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.pickup,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      req.dropoff,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isAccepted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler, size: 18, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Biker: ${req.acceptedByDriverName ?? "Peer Rider"} (${req.acceptedByDriverBike ?? "Bike"})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF14532D)),
                    ),
                  ),
                  if (req.acceptedByDriverPhone != null && req.acceptedByDriverPhone!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone, size: 18, color: Color(0xFF16A34A)),
                      onPressed: () {
                        DirectCallService.showCallOptions(
                          context,
                          phoneNumber: req.acceptedByDriverPhone!,
                          peerName: req.acceptedByDriverName ?? 'Biker',
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF0284C7)),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            rideId: req.id,
                            peerName: req.acceptedByDriverName ?? 'Biker',
                            vehicleModel: req.acceptedByDriverBike ?? 'Bike',
                            peerPhone: req.acceptedByDriverPhone ?? '',
                            peerRole: 'Driver',
                            peerId: req.acceptedByDriverId,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // Actions: Edit & Cancel
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    PostRideRequestSheet.show(context, existingRequest: req);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFFFB74D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Cancel Ride Request?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      content: Text('Are you sure you want to cancel your ride request to ${req.dropoff}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cancel Request', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref.read(ridesRepositoryProvider).deletePassengerRequest(req.id);
                    ref.invalidate(myPassengerRequestsProvider);
                    ref.invalidate(allPassengerRequestsProvider);
                    ref.invalidate(passengerRequestsProvider);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ride request cancelled.'),
                        backgroundColor: Color(0xFFD32F2F),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD32F2F),
                  side: const BorderSide(color: Color(0xFFFFCDD2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildRiderPostedRidesSection() {
    final myPostedRidesAsync = ref.watch(myPostedRidesProvider);

    return myPostedRidesAsync.when(
      data: (rides) {
        if (rides.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.assignment_outlined, color: Color(0xFFE65100), size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'My Shared Rides & Status',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF141416),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => widget.onNavigateTab(1),
                    child: const Text(
                      'Manage All',
                      style: TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                children: rides.take(3).map((ride) => _buildRiderRideStatusItem(ride)).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRiderRideStatusItem(RideModel ride) {
    final isCompleted = ride.status == RideStatus.completed;
    final isActive = ride.status == RideStatus.active;
    final isCancelled = ride.status == RideStatus.cancelled;

    Color statusColor;
    String statusText;
    if (isCompleted) {
      statusColor = const Color(0xFF64748B);
      statusText = 'COMPLETED';
    } else if (isActive) {
      statusColor = const Color(0xFF0284C7);
      statusText = 'TRIP ON THE WAY';
    } else if (isCancelled) {
      statusColor = const Color(0xFFDC2626);
      statusText = 'CANCELLED';
    } else {
      statusColor = ride.availableSeats < ride.totalSeats ? const Color(0xFFD97706) : const Color(0xFF059669);
      statusText = ride.availableSeats < ride.totalSeats ? 'PASSENGER BOOKED' : 'WAITING FOR RIDERS';
    }

    final formattedTime = '${ride.departureTime.hour.toString().padLeft(2, '0')}:${ride.departureTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '৳${ride.farePerSeat.toInt()} / seat',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.navigation, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${ride.originName} ➔ ${ride.destinationName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F2937)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.access_time, size: 13, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                'Leaving at $formattedTime',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.event_seat, size: 13, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                '${ride.totalSeats - ride.availableSeats}/${ride.totalSeats} seats booked',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RideDetailsTrackingScreen(rideId: ride.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                  label: const Text('Status & Tracking', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1F2937),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Extend Departure Time Button
              InkWell(
                onTap: () {
                  PostExpiryExtensionDialog.show(
                    context,
                    postId: ride.id,
                    postType: 'ride',
                    title: 'Extend Departure Time',
                    scheduledTimeStr: ride.departureTime.toIso8601String(),
                  ).then((_) {
                    ref.invalidate(myPostedRidesProvider);
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.more_time, size: 14, color: Color(0xFF0F172A)),
                      SizedBox(width: 4),
                      Text('Extend', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Delete Post Button
              InkWell(
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Posted Ride?'),
                      content: const Text('Are you sure you want to delete this posted ride? This will remove the post permanently.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref.read(ridesRepositoryProvider).deleteRide(ride.id);
                    ref.invalidate(myPostedRidesProvider);
                    ref.invalidate(allAvailableRidesProvider);
                    ref.invalidate(allSystemRidesProvider);
                    ref.invalidate(departingSoonRidesProvider);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Ride post deleted successfully'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: const Color(0xFF1E293B),
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
