import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

/// LiveRideStatusCard
/// Displays real-time ride and booking status directly on the Home Screen,
/// keeping ongoing commute status easily visible and instantly accessible.
class LiveRideStatusCard extends ConsumerWidget {
  final Function(int tabIndex) onNavigateTab;

  const LiveRideStatusCard({
    super.key,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appMode = ref.watch(appModeProvider);
    final bookingsAsync = ref.watch(myBookingsProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final allRides = allRidesAsync.value ?? [];
    final myPostedRidesAsync = ref.watch(myPostedRidesProvider);
    final myPostedRides = myPostedRidesAsync.value ?? [];

    // Find active booking for passenger:
    // In Rider mode, passenger bookings are strictly ignored so biker only sees ride sharing status!
    final activeBooking = appMode.isRider
        ? null
        : bookingsAsync.value?.cast<BookingModel?>().firstWhere(
              (b) => b?.status == BookingStatus.accepted || b?.status == BookingStatus.requested,
              orElse: () => null,
            );

    final currentUser = ref.watch(authNotifierProvider).user;

    // Find active offered ride for biker/driver:
    // In Passenger mode, driver offered rides are ignored.
    final activeOfferedRide = appMode.isPassenger
        ? null
        : (myPostedRides.cast<RideModel?>().firstWhere(
              (r) => (r?.status == RideStatus.active || r?.status == RideStatus.published),
              orElse: () => null,
            ) ??
            allRides.cast<RideModel?>().firstWhere(
              (r) => (r?.status == RideStatus.active || r?.status == RideStatus.published) &&
                     currentUser != null &&
                     (r?.driverId == currentUser.id || r?.driverId == currentUser.studentId || (currentUser.phone.isNotEmpty && r?.driverPhone == currentUser.phone)),
              orElse: () => null,
            ));

    // 1. PASSENGER VIEW: Toplist Confirmed Commute / Requested Seat
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
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFFFF9800)).withOpacity(0.14),
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
                        isConfirmed ? 'CONFIRMED COMMUTE (DRIVER ASSIGNED)' : 'SEAT REQUESTED (PENDING)',
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
                        'Route: ${activeBooking.pickupPoint} ➔ ${activeBooking.dropoffPoint}',
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
                  label: const Text('Chat & Ring', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Direct Call Driver',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
                    foregroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    DirectCallService.showCallOptions(
                      context,
                      phoneNumber: matchingRide.driverPhone ?? '',
                      peerName: matchingRide.driverName,
                      peerRole: 'Driver',
                    );
                  },
                  icon: const Icon(Icons.phone, size: 18),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 2. DRIVER VIEW: Toplist Booked Passenger / Active Offered Ride
    if (activeOfferedRide != null) {
      final driverBookingsAsync = ref.watch(rideBookingsProvider(activeOfferedRide.id));
      final bookedPassenger = driverBookingsAsync.value?.cast<BookingModel?>().firstWhere(
            (b) => b?.status == BookingStatus.accepted || b?.status == BookingStatus.requested,
            orElse: () => null,
          );

      final hasBookedPassenger = bookedPassenger != null;
      final isAccepted = bookedPassenger?.status == BookingStatus.accepted;

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasBookedPassenger
                ? (isAccepted ? const Color(0xFF10B981) : const Color(0xFFFF9800))
                : const Color(0xFF2E7D32).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: hasBookedPassenger
                  ? (isAccepted ? const Color(0xFF10B981) : const Color(0xFFFF9800)).withOpacity(0.14)
                  : const Color(0xFF2E7D32).withOpacity(0.12),
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
                    color: hasBookedPassenger
                        ? (isAccepted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0))
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hasBookedPassenger
                              ? (isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100))
                              : const Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasBookedPassenger
                            ? (isAccepted ? 'CONFIRMED COMMUTE (PASSENGER BOOKED)' : 'NEW SEAT BOOKING REQUEST')
                            : 'ACTIVE RIDER POOL',
                        style: TextStyle(
                          color: hasBookedPassenger
                              ? (isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100))
                              : const Color(0xFF2E7D32),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  hasBookedPassenger
                      ? '৳${bookedPassenger.totalFare.toInt()}'
                      : '৳${activeOfferedRide.farePerSeat.toInt()} / seat',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: hasBookedPassenger ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasBookedPassenger) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFDCFCE7),
                    child: Text(
                      bookedPassenger.passengerName.isNotEmpty
                          ? bookedPassenger.passengerName[0].toUpperCase()
                          : 'P',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
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
                                bookedPassenger.passengerName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.school, size: 14, color: Color(0xFF16A34A)),
                          ],
                        ),
                        Text(
                          '${bookedPassenger.passengerDept} • ${bookedPassenger.seatsBooked} Seat(s) Booked',
                          style: TextStyle(color: Colors.grey[700], fontSize: 11.5),
                        ),
                        Text(
                          'Pickup: ${bookedPassenger.pickupPoint} ➔ ${bookedPassenger.dropoffPoint}',
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
              if (!isAccepted) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final success = await ref.read(bookingNotifierProvider.notifier).acceptBooking(
                                bookingId: bookedPassenger.id,
                                rideId: activeOfferedRide.id,
                                driverName: currentUser?.name ?? 'Rider',
                                pickupPoint: bookedPassenger.pickupPoint,
                              );
                          if (context.mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Booking accepted for ${bookedPassenger.passengerName}!'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Accept Booking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(bookingNotifierProvider.notifier).rejectBooking(
                              bookingId: bookedPassenger.id,
                              rideId: activeOfferedRide.id,
                              driverName: currentUser?.name ?? 'Rider',
                            );
                      },
                      icon: const Icon(Icons.close, size: 15),
                      label: const Text('Decline', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RideDetailsTrackingScreen(rideId: activeOfferedRide.id),
                            ),
                          );
                        },
                        icon: const Icon(Icons.share_location, size: 15),
                        label: const Text('Live GPS Track', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
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
                              rideId: activeOfferedRide.id,
                              peerName: bookedPassenger.passengerName,
                              peerPhone: bookedPassenger.passengerPhone,
                              peerRole: 'Passenger',
                              peerId: bookedPassenger.passengerId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 15),
                      label: const Text('Chat & Ring', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Direct Call Passenger',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
                        foregroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        DirectCallService.showCallOptions(
                          context,
                          phoneNumber: bookedPassenger.passengerPhone,
                          peerName: bookedPassenger.passengerName,
                          peerRole: 'Passenger',
                        );
                      },
                      icon: const Icon(Icons.phone, size: 18),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text(
                'Your Ride: ${activeOfferedRide.originName} ➔ ${activeOfferedRide.destinationName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RideDetailsTrackingScreen(rideId: activeOfferedRide.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_location, size: 15),
                      label: const Text('Live Trip Tracking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => onNavigateTab(3),
                    icon: const Icon(Icons.message, size: 15),
                    label: const Text('Messages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // In Rider Mode: Dedicated Ride Sharing Status Check Card when no active trip is running
    if (appMode.isRider) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE65100).withOpacity(0.08),
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
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                      SizedBox(width: 6),
                      Text(
                        'RIDE SHARING STATUS: IDLE',
                        style: TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Biker Ready',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'No active bike ride shared for today yet',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Post your commute route to take campus peers, earn fuel fare, and track passenger booking statuses right here.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onNavigateTab(2),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text(
                      'Offer / Share Bike Ride',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => onNavigateTab(1),
                  icon: const Icon(Icons.assignment_outlined, size: 15),
                  label: const Text('Past Rides', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default status when no active ride: Realtime status badge
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Campus Network Live Syncing',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  'Realtime messages, rings & live peer tracking active',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => onNavigateTab(1),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rides',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 14, color: Color(0xFFE65100)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
