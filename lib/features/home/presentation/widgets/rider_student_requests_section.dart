import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/all_passenger_requests_gig_sheet.dart';

class RiderStudentRequestsSection extends ConsumerWidget {
  final VoidCallback onSeeAll;
  final String? riderDestination;

  const RiderStudentRequestsSection({
    super.key,
    required this.onSeeAll,
    this.riderDestination,
  });

  bool _isRouteMatch(PassengerRequestModel req, String? destination) {
    if (destination == null || destination.trim().isEmpty) return false;
    final d = destination.toLowerCase().trim();
    final drop = req.dropoff.toLowerCase();
    final pick = req.pickup.toLowerCase();

    // 1. Direct match
    if (drop.contains(d) || d.contains(drop)) return true;

    // 2. Corridors with waypoints (e.g. Birulia is on the way to Uttara and Mirpur from DIU)
    final corridors = [
      ['ashulia', 'birulia', 'diabari', 'uttara', 'house building', 'airport', 'khilkhet', 'kuril', 'banani', 'gulshan'],
      ['ashulia', 'birulia', 'beribadh', 'mirpur', 'kazipara', 'shewrapara', 'agargaon', 'ecb'],
      ['ashulia', 'birulia', 'mirpur', 'farmgate', 'karwan bazar', 'shahbagh', 'dhaka university', 'motijheel'],
      ['ashulia', 'savar', 'aminbazar', 'gabtoli', 'shyamoli', 'dhanmondi'],
    ];

    for (final corridor in corridors) {
      final destInCorridor = corridor.any((w) => d.contains(w) || w.contains(d));
      final dropInCorridor = corridor.any((w) => drop.contains(w) || w.contains(drop));
      if (destInCorridor && dropInCorridor) {
        return true;
      }
    }

    final keywords = ['mirpur', 'uttara', 'dhanmondi', 'farmgate', 'savar', 'motijheel', 'ecb', 'mohammadpur', 'banani', 'gulshan', 'birulia'];
    for (final kw in keywords) {
      if (d.contains(kw) && (drop.contains(kw) || pick.contains(kw))) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(passengerRequestsProvider);
    final user = ref.watch(authNotifierProvider).user;
    final ridesRepo = ref.watch(ridesRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
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
                    child: const Icon(Icons.hail_rounded, color: Color(0xFFE65100), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Student Pickup Requests',
                    style: AppTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: const Color(0xFF141416),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  AllPassengerRequestsGigSheet.show(
                    context,
                    initialFilterDestination: riderDestination,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Gig Board',
                        style: TextStyle(
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFE65100), size: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Part-Time Gig Promotion Banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments_outlined, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Part-Time Campus Gig',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Earn ৳50-৳120 per ride by picking up students',
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    AllPassengerRequestsGigSheet.show(
                      context,
                      initialFilterDestination: riderDestination,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('View All', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Horizontal List of Requests (Sorted: Matching Route First!)
        requestsAsync.when(
          data: (rawRequests) {
            final requests = rawRequests.map((e) {
              if (e is PassengerRequestModel) return e;
              return PassengerRequestModel.fromJson(Map<String, dynamic>.from(e as Map));
            }).where((r) => r.status != 'cancelled' && r.status != 'completed').toList();

            // Sort so route matches are first
            requests.sort((a, b) {
              final aMatch = _isRouteMatch(a, riderDestination);
              final bMatch = _isRouteMatch(b, riderDestination);
              if (aMatch && !bMatch) return -1;
              if (!aMatch && bMatch) return 1;
              return 0;
            });

            if (requests.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0F0F2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF8E8E93), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No pending student ride requests right now. Publish your ride so peers can book your seat!',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              height: 195,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final req = requests[index];
                  final isAccepted = req.isAccepted ||
                      (user != null && req.acceptedByDriverId == user.id);
                  final isMatch = _isRouteMatch(req, riderDestination);

                  return Container(
                    width: 290,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isMatch ? const Color(0xFFE65100) : const Color(0xFFE5E7EB),
                        width: isMatch ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMatch ? const Color(0xFFE65100).withOpacity(0.12) : const Color(0x0A000000),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Row with Passenger info, badge & Fare
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                                  child: Text(
                                    req.passengerName.isNotEmpty ? req.passengerName[0] : 'S',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 110),
                                  child: Text(
                                    req.passengerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMatch)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFFA000)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.near_me, size: 9, color: Color(0xFFE65100)),
                                        SizedBox(width: 2),
                                        Text(
                                          'On Route',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFE65100),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '৳${req.proposedFare.toInt()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Route pickup & dropoff
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${req.pickup} → ${req.dropoff}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Time: ${req.requestedTime}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),

                        // Action button
                        Row(
                          children: [
                            if (isAccepted)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          rideId: req.id,
                                          peerName: req.passengerName,
                                          vehicleModel: 'Motorbike Commute',
                                          peerPhone: req.passengerPhone,
                                          peerRole: 'Passenger',
                                          peerId: req.passengerId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                  label: const Text('Chat with Passenger', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E7D32),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              )
                            else ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (SameAccountGuard.blockOwnPassengerAccept(context, user, req)) {
                                      return;
                                    }
                                    final currentUserId = user?.id ?? 'drv_peer';
                                    final currentUserName = user?.name ?? 'Campus Biker';
                                    final currentUserPhone = user?.phone ?? '01712345678';

                                    try {
                                      final ok = await ridesRepo.acceptPassengerRequest(
                                        requestId: req.id,
                                        driverId: currentUserId,
                                        driverName: currentUserName,
                                        driverPhone: currentUserPhone,
                                        driverBike: user?.vehicleInfo ?? 'Campus Motorcycle',
                                        driverStudentId: user?.studentId,
                                      );

                                      ref.invalidate(passengerRequestsProvider);

                                      if (ok && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: const Color(0xFF2E7D32),
                                            content: Text('Accepted! You are commuting with ${req.passengerName}.'),
                                          ),
                                        );
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              rideId: req.id,
                                              peerName: req.passengerName,
                                              vehicleModel: 'Motorbike Commute',
                                              peerPhone: req.passengerPhone,
                                              peerRole: 'Passenger',
                                              peerId: req.passengerId,
                                            ),
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
                                  icon: const Icon(Icons.check, size: 14),
                                  label: const Text('Accept & Give Ride', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
