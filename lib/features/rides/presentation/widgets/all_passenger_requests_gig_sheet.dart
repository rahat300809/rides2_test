import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class AllPassengerRequestsGigSheet extends ConsumerStatefulWidget {
  final String? initialFilterDestination;

  const AllPassengerRequestsGigSheet({
    super.key,
    this.initialFilterDestination,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialFilterDestination,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AllPassengerRequestsGigSheet(
        initialFilterDestination: initialFilterDestination,
      ),
    );
  }

  @override
  ConsumerState<AllPassengerRequestsGigSheet> createState() => _AllPassengerRequestsGigSheetState();
}

class _AllPassengerRequestsGigSheetState extends ConsumerState<AllPassengerRequestsGigSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCorridor = 'All';
  String _searchQuery = '';

  final List<String> _corridors = [
    'All',
    'Mirpur',
    'Uttara',
    'Dhanmondi',
    'Farmgate',
    'Savar',
    'Motijheel',
    'ECB Chattar',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialFilterDestination != null && widget.initialFilterDestination!.isNotEmpty) {
      final dest = widget.initialFilterDestination!;
      for (final c in _corridors) {
        if (dest.toLowerCase().contains(c.toLowerCase())) {
          _selectedCorridor = c;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(passengerRequestsProvider);
    final user = ref.watch(authNotifierProvider).user;
    final ridesRepo = ref.watch(ridesRepositoryProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 25,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.work_outline_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'Campus Gig Board',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.stars, color: Color(0xFFE65100), size: 16),
                        ],
                      ),
                      Text(
                        'Pick up peers, share empty seats & earn on your commute',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search dropoff location or student name...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFE65100)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ),

          // Corridor Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: _corridors.map((c) {
                final isSelected = _selectedCorridor == c;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedCorridor = c);
                    },
                    selectedColor: const Color(0xFFE65100),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFFE65100) : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 6),

          // List of Passenger Requests
          Expanded(
            child: requestsAsync.when(
              data: (rawRequests) {
                final allReqs = rawRequests.map((e) {
                  if (e is PassengerRequestModel) return e;
                  return PassengerRequestModel.fromJson(Map<String, dynamic>.from(e as Map));
                }).where((r) => r.status != 'cancelled' && r.status != 'completed').toList();

                // Apply Filters
                final filtered = allReqs.where((r) {
                  if (_selectedCorridor != 'All') {
                    final cLow = _selectedCorridor.toLowerCase();
                    final match = r.dropoff.toLowerCase().contains(cLow) ||
                        r.pickup.toLowerCase().contains(cLow);
                    if (!match) return false;
                  }
                  if (_searchQuery.isNotEmpty) {
                    final match = r.dropoff.toLowerCase().contains(_searchQuery) ||
                        r.pickup.toLowerCase().contains(_searchQuery) ||
                        r.passengerName.toLowerCase().contains(_searchQuery) ||
                        r.passengerDept.toLowerCase().contains(_searchQuery);
                    if (!match) return false;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.hail_rounded, size: 48, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        const Text(
                          'No passenger requests found',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check back soon or select another campus corridor',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final req = filtered[index];
                    final isAccepted = req.isAccepted || (user != null && req.acceptedByDriverId == user.id);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isAccepted ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                          width: isAccepted ? 1.5 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
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
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                                    child: Text(
                                      req.passengerName.isNotEmpty ? req.passengerName[0].toUpperCase() : 'S',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE65100),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        req.passengerName,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        'Dept of ${req.passengerDept} • DIU Student',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFE65100).withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '৳${req.proposedFare.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF1F5F9)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.radio_button_checked, size: 14, color: Color(0xFF10B981)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Pickup: ${req.pickup}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      height: 10,
                                      child: VerticalDivider(color: Color(0xFFCBD5E1), thickness: 1.5),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 14, color: Color(0xFFE65100)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Dropoff: ${req.dropoff}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                'Time: ${req.requestedTime}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              if (req.notes.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                const Icon(Icons.info_outline, size: 13, color: Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    req.notes,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              if (isAccepted)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
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
                                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                                    label: const Text('Open Chat with Passenger', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                )
                              else ...[
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      if (checkAndEnforceVisitorMode(context, ref, actionName: 'accept passenger ride requests')) return;
                                      if (SameAccountGuard.blockOwnPassengerAccept(context, user, req)) return;
                                      HapticFeedback.mediumImpact();
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
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: const Color(0xFF2E7D32),
                                              content: Text('Accepted! Commuting with ${req.passengerName} for ৳${req.proposedFare.toInt()}.'),
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
                                    icon: const Icon(Icons.check_circle_outline, size: 16),
                                    label: Text(
                                      'Accept & Pick Up (৳${req.proposedFare.toInt()})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFE65100)),
              ),
              error: (err, _) => Center(
                child: Text('Error loading requests: $err', style: AppTypography.bodyMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
