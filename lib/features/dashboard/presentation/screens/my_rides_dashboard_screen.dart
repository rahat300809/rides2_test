import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';

class MyRidesDashboardScreen extends ConsumerStatefulWidget {
  const MyRidesDashboardScreen({super.key});

  @override
  ConsumerState<MyRidesDashboardScreen> createState() =>
      _MyRidesDashboardScreenState();
}

class _MyRidesDashboardScreenState
    extends ConsumerState<MyRidesDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = ref.watch(pendingRideRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'My Campus Commutes',
          style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          labelStyle:
              AppTypography.labelLg.copyWith(fontWeight: FontWeight.bold),
          tabs: [
            const Tab(text: 'As Passenger'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('As Driver'),
                  if (pendingRequests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pendingRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPassengerDashboard(),
          _buildDriverDashboard(),
          _buildRideRequestsPanel(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASSENGER TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPassengerDashboard() {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      data: (bookings) {
        if (bookings.isEmpty) {
          return _buildEmptyState(
            icon: Icons.bookmark_border,
            title: 'No Active Bookings',
            subtitle: 'Search campus rides to reserve a seat.',
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(myBookingsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) =>
                _PassengerBookingCard(booking: bookings[index]),
          ),
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DRIVER TAB
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildDriverDashboard() {
    final ridesRepo = ref.watch(ridesRepositoryProvider);
    final user = ref.watch(authNotifierProvider).user;

    return FutureBuilder<List<RideModel>>(
      future: ridesRepo.getMyOfferedRides(user?.id ?? ''),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }

        final myRides = snapshot.data ?? [];
        if (myRides.isEmpty) {
          return _buildEmptyState(
            icon: Icons.two_wheeler_outlined,
            title: 'No Offered Rides',
            subtitle: 'Offer a ride to help DIU peers commute.',
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: myRides.length,
            itemBuilder: (context, index) {
              final ride = myRides[index];
              return _DriverRideCard(
                ride: ride,
                ridesRepo: ridesRepo,
                onStateChanged: () => setState(() {}),
              );
            },
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RIDE REQUESTS TAB — incoming passenger requests (Uber driver style)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildRideRequestsPanel() {
    final pendingRequests = ref.watch(pendingRideRequestsProvider);
    final user = ref.watch(authNotifierProvider).user;

    // Also load bookings for driver's rides
    final ridesRepo = ref.watch(ridesRepositoryProvider);

    if (pendingRequests.isEmpty) {
      return FutureBuilder<List<RideModel>>(
        future: ridesRepo.getMyOfferedRides(user?.id ?? ''),
        builder: (context, snapshot) {
          final myRides = snapshot.data ?? [];
          if (myRides.isEmpty) {
            return _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No Incoming Requests',
              subtitle:
                  'When passengers request seats on your rides, they\'ll appear here.',
            );
          }
          // Show all bookings for all driver's rides
          return _AllRideBookingsView(rideIds: myRides.map((r) => r.id).toList());
        },
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Alarm header
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6F00), Color(0xFFE65100)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pendingRequests.length} Pending Ride Request(s)',
                        style: AppTypography.bodyLgMedium.copyWith(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Accept or decline each request below.',
                        style: AppTypography.labelSm
                            .copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Request cards
          ...pendingRequests.map((n) => _InlineRequestCard(notification: n)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: AppColors.outlineVariant),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppTypography.headlineSm),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.bodyMd.copyWith(color: AppColors.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PASSENGER BOOKING CARD
// =============================================================================

class _PassengerBookingCard extends ConsumerWidget {
  final BookingModel booking;
  const _PassengerBookingCard({required this.booking});

  Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.accepted:
        return AppColors.primary;
      case BookingStatus.requested:
        return const Color(0xFFE65100);
      case BookingStatus.rejected:
      case BookingStatus.cancelled:
        return AppColors.error;
      case BookingStatus.completed:
        return AppColors.tertiary;
    }
  }

  String _statusLabel(BookingStatus status) {
    switch (status) {
      case BookingStatus.requested:
        return 'AWAITING DRIVER';
      case BookingStatus.accepted:
        return 'CONFIRMED ✓';
      case BookingStatus.rejected:
        return 'DECLINED';
      case BookingStatus.cancelled:
        return 'CANCELLED';
      case BookingStatus.completed:
        return 'COMPLETED';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(booking.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: booking.status == BookingStatus.accepted
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.surfaceContainer,
        ),
        boxShadow: const [
          BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusLabel(booking.status),
                  style: AppTypography.labelSm.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                CurrencyFormatter.formatBdt(booking.totalFare),
                style: AppTypography.headlineSm.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.trip_origin, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(booking.pickupPoint,
                    style: AppTypography.bodyMdMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(booking.dropoffPoint,
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${booking.seatsBooked} seat(s) • ${DateTimeUtils.formatRelativeTime(booking.requestedAt)}',
            style:
                AppTypography.labelSm.copyWith(color: AppColors.outline),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (booking.status == BookingStatus.accepted ||
                  booking.status == BookingStatus.requested)
                TextButton(
                  onPressed: () {
                    ref
                        .read(bookingNotifierProvider.notifier)
                        .cancelBooking(booking.id);
                  },
                  child: Text(
                    'Cancel',
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.error),
                  ),
                ),
              if (booking.status == BookingStatus.accepted) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: booking.rideId,
                          driverName: 'Ride Driver',
                          vehicleModel: 'Campus Ride',
                          peerRole: 'Driver',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                  label: const Text('Chat', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () {
                    CampusVoiceCallDialog.show(
                      context,
                      peerName: 'Ride Driver',
                      peerPhone: '01712345678',
                      peerRole: 'Driver',
                    );
                  },
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('Call', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            RideDetailsTrackingScreen(rideId: booking.rideId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Track Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DRIVER RIDE CARD
// =============================================================================

// =============================================================================
// DRIVER RIDE CARD (Enhanced with Post Checking, Responses & Post Removal)
// =============================================================================

class _DriverRideCard extends ConsumerWidget {
  final RideModel ride;
  final dynamic ridesRepo;
  final VoidCallback onStateChanged;

  const _DriverRideCard({
    required this.ride,
    required this.ridesRepo,
    required this.onStateChanged,
  });

  void _confirmRemovePost(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_forever, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Remove Ride Post?')),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove this ride post? It will be permanently removed from DIU Ride and any pending requests will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Post'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ridesRepo.deleteRide(ride.id);
              ref.invalidate(departingSoonRidesProvider);
              ref.invalidate(searchRidesResultsProvider);
              ref.invalidate(allAvailableRidesProvider);
              onStateChanged();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    content: Text('Ride post removed successfully.'),
                  ),
                );
              }
            },
            child: const Text('Remove Post'),
          ),
        ],
      ),
    );
  }

  void _openManageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _ManageRidePostSheet(
        ride: ride,
        ridesRepo: ridesRepo,
        onStateChanged: onStateChanged,
        onRemovePost: () => _confirmRemovePost(context, ref),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));

    return InkWell(
      onTap: () => _openManageSheet(context, ref),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ride.status == RideStatus.active
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.surfaceContainer,
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Fare
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusBg(ride.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ride.status.name.toUpperCase(),
                    style: AppTypography.labelSm.copyWith(
                      color: _statusFg(ride.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatBdt(ride.farePerSeat)}/seat',
                  style: AppTypography.headlineSm.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Origin -> Destination
            Row(
              children: [
                const Icon(Icons.trip_origin, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ride.originName,
                    style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ride.destinationName,
                    style: AppTypography.labelMd.copyWith(color: AppColors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Vehicle and Time Info
            Row(
              children: [
                const Icon(
                  Icons.two_wheeler,
                  size: 13,
                  color: AppColors.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  ride.vehicle.modelName,
                  style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.two_wheeler, size: 13, color: AppColors.outline),
                const SizedBox(width: 4),
                Text(
                  '${ride.availableSeats} moto seat',
                  style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.access_time_outlined, size: 13, color: AppColors.outline),
                const SizedBox(width: 4),
                Text(
                  DateTimeUtils.formatTime(ride.departureTime),
                  style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                ),
              ],
            ),

            // -----------------------------------------------------------------
            // PASSENGER RESPONSES SUMMARY PILL
            // -----------------------------------------------------------------
            const SizedBox(height: 10),
            bookingsAsync.when(
              data: (bookings) {
                final pending = bookings.where((b) => b.status == BookingStatus.requested).length;
                final accepted = bookings.where((b) => b.status == BookingStatus.accepted).length;

                if (bookings.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline, size: 14, color: AppColors.outline),
                        const SizedBox(width: 6),
                        Text(
                          'No passenger requests yet • Tap to check post',
                          style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pending > 0
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: pending > 0
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFFA5D6A7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        pending > 0 ? Icons.notification_important : Icons.check_circle,
                        size: 15,
                        color: pending > 0 ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        pending > 0
                            ? '$pending Passenger Request(s) Pending!'
                            : '$accepted Passenger(s) Confirmed ✓',
                        style: AppTypography.labelSm.copyWith(
                          color: pending > 0 ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'View Responses →',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),

            const Divider(height: 20),

            // Action Buttons Row
            Row(
              children: [
                // Check post & responses button
                OutlinedButton.icon(
                  onPressed: () => _openManageSheet(context, ref),
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text('Check Post & Responses'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const Spacer(),

                // Remove post button
                IconButton(
                  onPressed: () => _confirmRemovePost(context, ref),
                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                  tooltip: 'Remove Post',
                ),

                // Start or End ride
                if (ride.status == RideStatus.published)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ridesRepo.startRide(ride.id);
                      if (!context.mounted) return;
                      onStateChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🚗 Ride Started! Passengers notified.')),
                      );
                    },
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else if (ride.status == RideStatus.active)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ridesRepo.completeRide(ride.id);
                      if (!context.mounted) return;
                      onStateChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🏁 Ride Completed! Thank you for driving.')),
                      );
                    },
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('End'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.tertiary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusBg(RideStatus status) {
    switch (status) {
      case RideStatus.published:
        return AppColors.primaryFixed;
      case RideStatus.active:
      case RideStatus.occupied:
        return AppColors.secondary.withOpacity(0.15);
      case RideStatus.completed:
        return AppColors.tertiary.withOpacity(0.1);
      case RideStatus.cancelled:
        return AppColors.errorContainer;
      case RideStatus.suspended:
        return const Color(0xFFFFF7ED);
    }
  }

  Color _statusFg(RideStatus status) {
    switch (status) {
      case RideStatus.published:
        return AppColors.onPrimaryFixed;
      case RideStatus.active:
      case RideStatus.occupied:
        return AppColors.secondary;
      case RideStatus.completed:
        return AppColors.tertiary;
      case RideStatus.cancelled:
        return AppColors.error;
      case RideStatus.suspended:
        return const Color(0xFFB45309);
    }
  }
}

// =============================================================================
// MANAGE RIDE POST & RESPONSES BOTTOM SHEET (Uber Driver Style)
// =============================================================================

class _ManageRidePostSheet extends ConsumerWidget {
  final RideModel ride;
  final dynamic ridesRepo;
  final VoidCallback onStateChanged;
  final VoidCallback onRemovePost;

  const _ManageRidePostSheet({
    required this.ride,
    required this.ridesRepo,
    required this.onStateChanged,
    required this.onRemovePost,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));
    final bookingNotifier = ref.read(bookingNotifierProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ride Post Details & Responses',
                          style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Manage your post, passenger requests, and ride status',
                          style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    // Post Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceContainer),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ROUTE DETAILS', style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              Text(
                                '${CurrencyFormatter.formatBdt(ride.farePerSeat)} per seat',
                                style: AppTypography.headlineSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.trip_origin, size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(ride.originName, style: AppTypography.bodyMdMedium),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(ride.destinationName, style: AppTypography.bodyMdMedium),
                              ),
                            ],
                          ),
                          if (ride.waypointName != null && ride.waypointName!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.alt_route, size: 16, color: AppColors.secondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('Via: ${ride.waypointName!}', style: AppTypography.labelSm),
                                ),
                              ],
                            ),
                          ],
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🚗 ${ride.vehicle.modelName} (${ride.vehicle.licensePlate})',
                                style: AppTypography.labelSm,
                              ),
                              Text(
                                '⏰ ${DateTimeUtils.formatTime(ride.departureTime)}',
                                style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Available Seats: ${ride.availableSeats} of ${ride.totalSeats} remaining',
                            style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Responses & Requests Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Passenger Requests & Responses',
                          style: AppTypography.bodyLgMedium.copyWith(fontWeight: FontWeight.bold),
                        ),
                        bookingsAsync.when(
                          data: (b) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${b.length} total',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Bookings list for this ride
                    bookingsAsync.when(
                      data: (bookings) {
                        if (bookings.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.people_outline, size: 40, color: AppColors.outlineVariant),
                                const SizedBox(height: 10),
                                Text(
                                  'No Passenger Requests Yet',
                                  style: AppTypography.headlineSm.copyWith(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'When DIU students book a seat on this ride, their requests and contact info will appear here.',
                                  style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: bookings.map((booking) {
                            return _SinglePassengerResponseCard(
                              booking: booking,
                              rideId: ride.id,
                              onAccept: () async {
                                await bookingNotifier.acceptBooking(
                                  bookingId: booking.id,
                                  rideId: ride.id,
                                  driverName: ride.driverName,
                                  pickupPoint: booking.pickupPoint,
                                );
                                ref.invalidate(rideBookingsProvider(ride.id));
                                onStateChanged();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.primary,
                                      content: Text('Accepted ${booking.passengerName}\'s seat request!'),
                                    ),
                                  );
                                }
                              },
                              onDecline: () async {
                                await bookingNotifier.rejectBooking(
                                  bookingId: booking.id,
                                  rideId: ride.id,
                                  driverName: ride.driverName,
                                );
                                ref.invalidate(rideBookingsProvider(ride.id));
                                onStateChanged();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.error,
                                      content: Text('Declined ${booking.passengerName}\'s request.'),
                                    ),
                                  );
                                }
                              },
                            );
                          }).toList(),
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      ),
                      error: (err, _) => Text('Error loading requests: $err'),
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Post Management Actions
                    Text('POST ACTIONS', style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        // Remove post button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              onRemovePost();
                            },
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            label: const Text('Remove Post', style: TextStyle(color: AppColors.error)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.error, width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Start / End ride button
                        if (ride.status == RideStatus.published)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await ridesRepo.startRide(ride.id);
                                onStateChanged();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('🚗 Ride Started! Passengers notified.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Start Ride'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          )
                        else if (ride.status == RideStatus.active)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await ridesRepo.completeRide(ride.id);
                                onStateChanged();
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('🏁 Ride Completed!')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.flag_outlined, size: 18),
                              label: const Text('Complete Ride'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.tertiary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// SINGLE PASSENGER RESPONSE CARD IN DRIVER'S POST MANAGEMENT
// =============================================================================

class _SinglePassengerResponseCard extends StatelessWidget {
  final BookingModel booking;
  final String rideId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SinglePassengerResponseCard({
    required this.booking,
    required this.rideId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = booking.status == BookingStatus.requested;
    final isAccepted = booking.status == BookingStatus.accepted;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? const Color(0xFFFFB74D)
              : (isAccepted ? const Color(0xFFA5D6A7) : AppColors.surfaceContainer),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  booking.passengerName.isNotEmpty ? booking.passengerName[0] : 'P',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.passengerName,
                      style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${booking.passengerDept} • 📞 ${booking.passengerPhone}',
                      style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPending
                      ? const Color(0xFFFFF3E0)
                      : (isAccepted ? const Color(0xFFE8F5E9) : AppColors.surfaceContainerLow),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  booking.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isPending
                        ? const Color(0xFFE65100)
                        : (isAccepted ? const Color(0xFF2E7D32) : AppColors.outline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${booking.seatsBooked} Seat(s) • Pickup: ${booking.pickupPoint}',
                style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
              ),
              Text(
                CurrencyFormatter.formatBdt(booking.totalFare),
                style: AppTypography.bodyMdMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          // Accept / Decline action buttons for pending request
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Accept Seat'),
                  ),
                ),
              ],
            ),
          ],

          if (isAccepted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 14, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text(
                    'Passenger confirmed • Ready for pickup',
                    style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],

          // Quick contact buttons for driver to communicate with passenger
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: rideId,
                          peerName: booking.passengerName,
                          vehicleModel: 'Passenger Chat',
                          peerPhone: booking.passengerPhone,
                          peerRole: 'Passenger',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    CampusVoiceCallDialog.show(
                      context,
                      peerName: booking.passengerName,
                      peerPhone: booking.passengerPhone,
                      peerRole: 'Passenger',
                      peerDept: booking.passengerDept,
                    );
                  },
                  icon: const Icon(Icons.call, size: 15),
                  label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ALL RIDE BOOKINGS VIEW (for Requests tab when no pending actions)
// =============================================================================

class _AllRideBookingsView extends ConsumerWidget {
  final List<String> rideIds;
  const _AllRideBookingsView({required this.rideIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rideIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 52, color: AppColors.outlineVariant),
            const SizedBox(height: 12),
            Text('No Incoming Requests',
                style: AppTypography.headlineSm),
            const SizedBox(height: 4),
            Text(
              'Passengers who book your rides will appear here.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rideIds.length,
      itemBuilder: (context, i) {
        final bookingsAsync = ref.watch(rideBookingsProvider(rideIds[i]));
        return bookingsAsync.when(
          data: (bookings) {
            if (bookings.isEmpty) return const SizedBox();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Ride ${i + 1}',
                    style: AppTypography.bodyLgMedium
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...bookings.map((b) => _BookingRequestMiniCard(
                    booking: b, rideId: rideIds[i])),
                const SizedBox(height: 12),
              ],
            );
          },
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        );
      },
    );
  }
}

class _BookingRequestMiniCard extends ConsumerWidget {
  final BookingModel booking;
  final String rideId;
  const _BookingRequestMiniCard(
      {required this.booking, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: booking.status == BookingStatus.requested
            ? const Color(0xFFFFF8F0)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: booking.status == BookingStatus.requested
              ? const Color(0xFFFF9800).withOpacity(0.3)
              : AppColors.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryFixed,
            child: Text(
              booking.passengerName.isNotEmpty
                  ? booking.passengerName[0].toUpperCase()
                  : 'P',
              style: AppTypography.bodyMdMedium
                  .copyWith(color: AppColors.onPrimaryFixed),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.passengerName,
                    style: AppTypography.bodyMdMedium
                        .copyWith(fontWeight: FontWeight.w700)),
                Text(
                  '${booking.seatsBooked} seat(s) • ${CurrencyFormatter.formatBdt(booking.totalFare)}',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (booking.status == BookingStatus.requested) ...[
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.error, size: 18),
              onPressed: bookingState.isLoading
                  ? null
                  : () async {
                      await ref
                          .read(bookingNotifierProvider.notifier)
                          .rejectBooking(
                            bookingId: booking.id,
                            rideId: rideId,
                            driverName: 'You',
                          );
                    },
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: bookingState.isLoading
                  ? null
                  : () async {
                      await ref
                          .read(bookingNotifierProvider.notifier)
                          .acceptBooking(
                            bookingId: booking.id,
                            rideId: rideId,
                            driverName: 'You',
                            pickupPoint: booking.pickupPoint,
                          );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(70, 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Accept', style: TextStyle(fontSize: 12)),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(booking.status).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                booking.status.name.toUpperCase(),
                style: TextStyle(
                  color: _statusColor(booking.status),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Message Passenger',
              icon: const Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 18),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      rideId: rideId,
                      peerName: booking.passengerName,
                      vehicleModel: 'Passenger Chat',
                      peerPhone: booking.passengerPhone,
                      peerRole: 'Passenger',
                    ),
                  ),
                );
              },
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              tooltip: 'Call Passenger',
              icon: const Icon(Icons.call, color: Color(0xFF2E7D32), size: 18),
              onPressed: () {
                CampusVoiceCallDialog.show(
                  context,
                  peerName: booking.passengerName,
                  peerPhone: booking.passengerPhone,
                  peerRole: 'Passenger',
                  peerDept: booking.passengerDept,
                );
              },
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.accepted:
        return AppColors.primary;
      case BookingStatus.rejected:
      case BookingStatus.cancelled:
        return AppColors.error;
      default:
        return AppColors.secondary;
    }
  }
}

// =============================================================================
// INLINE REQUEST CARD (used in Requests tab when there are pending actions)
// =============================================================================

class _InlineRequestCard extends ConsumerWidget {
  final dynamic notification; // NotificationModel
  const _InlineRequestCard({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF9800).withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.title,
            style: AppTypography.bodyLgMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFFBF360C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            notification.body,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurface, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: bookingState.isLoading
                      ? null
                      : () async {
                          if (notification.relatedBookingId == null) return;
                          await ref
                              .read(bookingNotifierProvider.notifier)
                              .rejectBooking(
                                bookingId: notification.relatedBookingId!,
                                rideId: notification.relatedRideId ?? '',
                                driverName: 'You',
                              );
                          ref
                              .read(notificationsProvider.notifier)
                              .dismiss(notification.id);
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: bookingState.isLoading
                      ? null
                      : () async {
                          if (notification.relatedBookingId == null) return;
                          await ref
                              .read(bookingNotifierProvider.notifier)
                              .acceptBooking(
                                bookingId: notification.relatedBookingId!,
                                rideId: notification.relatedRideId ?? '',
                                driverName: 'You',
                                pickupPoint: '',
                              );
                          ref
                              .read(notificationsProvider.notifier)
                              .dismiss(notification.id);
                        },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Accept Rider'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
