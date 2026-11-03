import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/core/utils/peer_dm_id.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

class CampusMessagesScreen extends ConsumerStatefulWidget {
  final VoidCallback onExploreRides;

  const CampusMessagesScreen({
    super.key,
    required this.onExploreRides,
  });

  @override
  ConsumerState<CampusMessagesScreen> createState() => _CampusMessagesScreenState();
}

class _CampusMessagesScreenState extends ConsumerState<CampusMessagesScreen> {
  AppMode? _selectedFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _initWebSocketListener();
  }

  void _initWebSocketListener() {
    try {
      final wsClient = ref.read(webSocketClientProvider);
      _wsSub = wsClient.messages.listen((event) {
        final ev = (event['event'] ?? event['type'] ?? '').toString();
        if (ev == 'chat_message' ||
            ev == 'message_sent' ||
            ev == 'ride_session_status_changed' ||
            ev == 'ride_booked' ||
            ev == 'ride_request_created' ||
            ev == 'booking_created') {
          ref.invalidate(campusConversationsProvider);
          ref.invalidate(myBookingsProvider);
          ref.invalidate(allAvailableRidesProvider);
          if (mounted) setState(() {});
        }
      });
    } catch (e) {
      debugPrint('[CampusMessagesScreen] WebSocket error: $e');
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final convosAsync = ref.watch(campusConversationsProvider);
    final myBookingsAsync = ref.watch(myBookingsProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final ridesRepo = ref.watch(ridesRepositoryProvider);
    // Default to All Chats so user sees all conversations on load, without false empty state
    final effectiveMode = _selectedFilter ?? AppMode.all;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF1F5F9),
              Color(0xFFF8FAFC),
              Color(0xFFEFF6FF),
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFFE65100),
            backgroundColor: Colors.white,
            onRefresh: () async {
              ref.invalidate(campusConversationsProvider);
              ref.invalidate(myBookingsProvider);
              ref.invalidate(allAvailableRidesProvider);
              setState(() {});
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                // 1. Sleek 3D Liquid Glass AppBar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                                color: const Color(0xFFE65100).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Campus Inbox',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'Realtime Peer Chat & Urgent Calls',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Refresh button with 3D glass effect
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref.invalidate(campusConversationsProvider);
                            ref.invalidate(myBookingsProvider);
                            ref.invalidate(allAvailableRidesProvider);
                            setState(() {});
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFFE65100)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _openNewChatDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE65100).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_add_alt_1_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 5),
                                Text(
                                  'Find Friend',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
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

                // 2. Search & Filter Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search conversations or routes...',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 6)),

                // 3. Unified Real-Life Conversation List (No mode segregation, all chats in one place)
                convosAsync.when(
                  data: (convos) {
                    if (convos.isNotEmpty) {
                      final sorted = List<CampusConversationModel>.from(convos);
                      sorted.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));

                      // Strictly ensure 1-to-1 conversation per peer (no duplicates, no system cards)
                      final seenPeers = <String>{};
                      final deduped = <CampusConversationModel>[];
                      for (final c in sorted) {
                        final pLower = c.peerId.toLowerCase().trim();
                        final nameLower = c.peerName.toLowerCase().trim();
                        if (pLower == 'system' || pLower == 'unknown' || pLower == 'drv' || pLower == 'driver' || nameLower == 'system') continue;
                        if (!seenPeers.contains(pLower)) {
                          seenPeers.add(pLower);
                          deduped.add(c);
                        }
                      }

                      List<CampusConversationModel> filtered = deduped;
                      if (_searchQuery.isNotEmpty) {
                        filtered = filtered.where((c) =>
                            c.peerName.toLowerCase().contains(_searchQuery) ||
                            c.lastMessage.toLowerCase().contains(_searchQuery) ||
                            c.vehicleModel.toLowerCase().contains(_searchQuery)).toList();
                      }

                      if (filtered.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(effectiveMode),
                        );
                      }

                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildUnifiedConversationTile(filtered[index]);
                          },
                          childCount: filtered.length,
                        ),
                      );
                    }

                    // Fallback to local bookings & offered rides
                    return myBookingsAsync.when(
                      data: (bookings) {
                        final allRides = allRidesAsync.value ?? [];
                        return FutureBuilder<List<RideModel>>(
                          future: ridesRepo.getMyOfferedRides(user?.id ?? ''),
                          builder: (context, snapshot) {
                            final myOfferedRides = snapshot.data ?? [];
                            final showBookings = (effectiveMode == AppMode.all || effectiveMode == AppMode.passenger) && bookings.isNotEmpty;
                            final showOffered = (effectiveMode == AppMode.all || effectiveMode == AppMode.rider) && myOfferedRides.isNotEmpty;

                            if (!showBookings && !showOffered) {
                              return SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmptyState(effectiveMode),
                              );
                            }

                            return SliverList(
                              delegate: SliverChildListDelegate([
                                if (showBookings)
                                  ...bookings.map((booking) {
                                    final ride = allRides.firstWhere(
                                      (r) => r.id == booking.rideId,
                                      orElse: () => RideModel(
                                        id: booking.rideId,
                                        driverId: 'driver',
                                        driverName: 'Campus Driver',
                                        driverDept: 'DIU Driver',
                                        driverRating: 5.0,
                                        driverRideCount: 1,
                                        originName: booking.pickupPoint,
                                        originSubtitle: 'Pickup',
                                        originLat: 23.8769,
                                        originLng: 90.3204,
                                        destinationName: booking.dropoffPoint,
                                        destinationSubtitle: 'Destination',
                                        destinationLat: 23.8710,
                                        destinationLng: 90.3800,
                                        departureTime: DateTime.now(),
                                        farePerSeat: booking.totalFare,
                                        totalSeats: 1,
                                        availableSeats: 0,
                                        vehicle: const VehicleModel(
                                          id: 'v_ride',
                                          type: VehicleType.bike,
                                          modelName: 'Campus Commute',
                                          color: 'Green',
                                          licensePlate: 'DIU Verified',
                                          hasAc: false,
                                        ),
                                        distanceKm: 12.0,
                                      ),
                                    );
                                    return _buildPassengerConversationTile(booking, ride);
                                  }),
                                if (showOffered)
                                  ...myOfferedRides.map((ride) => _DriverRideConversationsSection(ride: ride)),
                              ]),
                            );
                          },
                        );
                      },
                      loading: () => const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
                      ),
                      error: (_, __) => SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(effectiveMode),
                      ),
                    );
                  },
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
                  ),
                  error: (e, _) => myBookingsAsync.when(
                    data: (bookings) {
                      if (bookings.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(effectiveMode),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final b = bookings[index];
                            final ride = allRidesAsync.value?.firstWhere(
                              (r) => r.id == b.rideId,
                              orElse: () => allRidesAsync.value!.first,
                            ) ?? allRidesAsync.value!.first;
                            return _buildPassengerConversationTile(b, ride);
                          },
                          childCount: bookings.length,
                        ),
                      );
                    },
                    loading: () => const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
                    ),
                    error: (_, __) => SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(effectiveMode),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewChatDialog,
        backgroundColor: const Color(0xFFE65100),
        elevation: 6,
        icon: const Icon(Icons.person_search_rounded, color: Colors.white, size: 20),
        label: const Text(
          'Message Friend',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  void _ringPeer(
    BuildContext context,
    String peerName,
    String rideId, {
    String? peerPhone,
    String? peerId,
  }) async {
    final user = ref.read(authNotifierProvider).user;
    final currentUser = user?.name ?? 'Fellow Student';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 34),
            ),
            const SizedBox(height: 14),
            Text('Ringing $peerName...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              'Dedicated alert buzzer is ringing on $peerName\'s phone. Tap Stop to cancel.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.call_end, size: 18),
                label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  NotificationSoundService.stopRinging();
                  try {
                    await ref.read(ridesRepositoryProvider).stopAlertRing(
                      targetUserId: peerName,
                      senderId: user?.id,
                      ringId: ringId,
                    );
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: (peerId != null && peerId.isNotEmpty)
            ? peerId
            : ((peerPhone != null && peerPhone.isNotEmpty) ? peerPhone : peerName),
        targetName: peerName,
        senderId: user?.id ?? '',
        senderName: currentUser,
        rideId: rideId,
        ringId: ringId,
        message: '🚨 Urgent: $currentUser is ringing you for pickup!',
      );
    } catch (_) {}
  }

  // 3D Liquid Glass Conversation Card
  Widget _buildUnifiedConversationTile(CampusConversationModel c) {
    final hasPassengerRole = c.peerRole.toLowerCase().contains('passenger');
    final hasRiderRole = c.peerRole.toLowerCase().contains('rider') || c.peerRole.toLowerCase().contains('biker');
    final showRoleBadge = hasPassengerRole || hasRiderRole;
    final roleGradient = hasPassengerRole
        ? const [Color(0xFF0284C7), Color(0xFF38BDF8)]
        : (hasRiderRole
            ? const [Color(0xFFE65100), Color(0xFFF97316)]
            : const [Color(0xFF0F766E), Color(0xFF14B8A6)]);
    final roleColor = hasPassengerRole ? const Color(0xFF0284C7) : const Color(0xFFE65100);
    final initialLetter = c.peerName.isNotEmpty ? c.peerName[0].toUpperCase() : (hasPassengerRole ? 'P' : 'D');

    String timeStr = '';
    if (c.lastTimestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(c.lastTimestamp).toLocal();
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 1) {
          timeStr = 'Now';
        } else if (diff.inMinutes < 60) {
          timeStr = '${diff.inMinutes}m';
        } else if (diff.inHours < 24) {
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dt.day}/${dt.month}';
        }
      } catch (_) {
        timeStr = '';
      }
    }

    final user = ref.read(authNotifierProvider).user;
    final hasUnread = c.unreadCount > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasUnread ? const Color(0xFFE65100).withOpacity(0.3) : Colors.white,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            final myId = user?.id ?? '';
            final pId = c.peerId.isNotEmpty ? c.peerId : '';
            String finalChatId = c.rideId;
            if (myId.isNotEmpty && pId.isNotEmpty && myId != pId) {
              finalChatId = canonicalPeerDmId(myId, pId);
            }
            final tileName = c.peerName.isNotEmpty && !c.peerName.startsWith('usr_') && c.peerName.toLowerCase() != 'system'
                ? c.peerName
                : (c.peerStudentId.isNotEmpty ? 'Student ${c.peerStudentId}' : (c.peerId.startsWith('usr_') ? 'Student ${c.peerId.replaceFirst('usr_', '').replaceAll('_', '-')}' : 'DIU Student'));

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: finalChatId,
                  peerName: tileName,
                  vehicleModel: c.vehicleModel,
                  peerPhone: c.peerPhone.isNotEmpty ? c.peerPhone : null,
                  peerRole: c.peerRole,
                  peerId: c.peerId,
                  chatContext: c.chatContext,
                  sourcePostId: c.sourcePostId,
                ),
              ),
            ).then((_) {
              ref.invalidate(campusConversationsProvider);
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 1. 3D Frosted Circular Avatar with Breathing Green Dot
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: roleGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: roleColor.withOpacity(0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initialLetter,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // 2. Peer Info & Latest Message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.peerName.isNotEmpty && !c.peerName.startsWith('usr_') && c.peerName.toLowerCase() != 'system'
                                  ? c.peerName
                                  : (c.peerStudentId.isNotEmpty ? 'Student ${c.peerStudentId}' : (c.peerId.startsWith('usr_') ? 'Student ${c.peerId.replaceFirst('usr_', '').replaceAll('_', '-')}' : 'DIU Student')),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                          if (showRoleBadge) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: roleColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: roleColor.withOpacity(0.25), width: 0.8),
                              ),
                              child: Text(
                                hasPassengerRole ? '🎒 Passenger' : '🏍️ Rider',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: roleColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.lastMessage.isNotEmpty ? c.lastMessage : 'Tap to open chat',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                                color: hasUnread ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: hasUnread ? const Color(0xFFE65100) : const Color(0xFF94A3B8),
                                fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 3. Quick Action Buttons (Call & Buzzer)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasUnread)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${c.unreadCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    _buildFrostedActionButton(
                      icon: Icons.call_rounded,
                      color: const Color(0xFF16A34A),
                      tooltip: 'Call ${c.peerName}',
                      onTap: () {
                        DirectCallService.showCallOptions(
                          context,
                          peerName: c.peerName,
                          phoneNumber: c.peerPhone.isNotEmpty ? c.peerPhone : '01712345678',
                          peerRole: c.peerRole,
                          peerDept: c.peerDept,
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildFrostedActionButton(
                      icon: Icons.notifications_active_rounded,
                      color: const Color(0xFFFF9800),
                      tooltip: 'Buzzer Alert',
                      onTap: () => _ringPeer(
                        context,
                        c.peerName,
                        c.rideId,
                        peerPhone: c.peerPhone,
                        peerId: c.peerId,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrostedActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.2), width: 1.2),
          ),
          child: Center(
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerConversationTile(BookingModel booking, RideModel ride) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: booking.rideId,
                  peerName: ride.driverName,
                  vehicleModel: ride.vehicle.modelName,
                  peerPhone: ride.driverPhone,
                  peerRole: 'Driver',
                  peerId: ride.driverId,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'D',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 20),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ride.driverName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65100).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Biker',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Trip: ${booking.pickupPoint} ➔ ${booking.dropoffPoint}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFrostedActionButton(
                      icon: Icons.call_rounded,
                      color: const Color(0xFF16A34A),
                      tooltip: 'Call Driver',
                      onTap: () {
                        DirectCallService.showCallOptions(
                          context,
                          peerName: ride.driverName,
                          phoneNumber: ride.driverPhone ?? '01712345678',
                          peerRole: 'Driver',
                          peerDept: ride.driverDept,
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildFrostedActionButton(
                      icon: Icons.notifications_active_rounded,
                      color: const Color(0xFFFF9800),
                      tooltip: 'Buzzer Driver',
                      onTap: () => _ringPeer(context, ride.driverName, booking.rideId, peerPhone: ride.driverPhone),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppMode mode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFE65100).withOpacity(0.15),
                      const Color(0xFFFF9800).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 34,
                  color: Color(0xFFE65100),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                mode == AppMode.rider
                    ? 'No Rider Messages'
                    : mode == AppMode.passenger
                        ? 'No Passenger Messages'
                        : 'No Active Messages Yet',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'When you search, book, or offer rides, instant direct chats, live GPS negotiations, and calls will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (mode != AppMode.all)
                    OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _selectedFilter = AppMode.all;
                        });
                      },
                      icon: const Icon(Icons.forum_outlined, size: 16),
                      label: const Text('Show All Chats'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE65100),
                        side: const BorderSide(color: Color(0xFFE65100), width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onExploreRides();
                    },
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text('Find Rides'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _openNewChatDialog();
                    },
                    icon: const Icon(Icons.person_search_rounded, size: 17),
                    label: const Text('Find Friend'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNewChatDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewChatSearchSheet(
        onUserSelected: (selectedUser) {
          final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
          final peerId = selectedUser['id']?.toString() ?? '';
          final convId = canonicalPeerDmId(currentUserId, peerId);
          final sName = selectedUser['name']?.toString() ?? 'DIU Student';
          final sPhone = selectedUser['phone']?.toString();
          final isBiker = selectedUser['isBiker'] == true;

          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                rideId: convId,
                peerId: peerId,
                peerName: sName,
                peerPhone: sPhone != null && sPhone.isNotEmpty ? sPhone : null,
                vehicleModel: isBiker ? 'DIU Biker' : 'Campus Chat',
                peerRole: isBiker ? 'Biker' : 'Student',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DriverRideConversationsSection extends ConsumerWidget {
  final RideModel ride;
  const _DriverRideConversationsSection({required this.ride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));

    return bookingsAsync.when(
      data: (bookings) {
        if (bookings.isEmpty) return const SizedBox();

        return Column(
          children: bookings.map((booking) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: ride.id,
                          peerName: booking.passengerName,
                          vehicleModel: 'Passenger Chat',
                          peerPhone: booking.passengerPhone,
                          peerRole: 'Passenger',
                          peerId: booking.passengerId,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              booking.passengerName.isNotEmpty ? booking.passengerName[0].toUpperCase() : 'P',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      booking.passengerName,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Passenger',
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Pickup: ${booking.pickupPoint} ➔ ${booking.dropoffPoint}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call_rounded, size: 18, color: Color(0xFF16A34A)),
                          onPressed: () {
                            DirectCallService.showCallOptions(
                              context,
                              peerName: booking.passengerName,
                              phoneNumber: booking.passengerPhone.isNotEmpty ? booking.passengerPhone : '01712345678',
                              peerRole: 'Passenger',
                              peerDept: booking.passengerDept,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _NewChatSearchSheet extends ConsumerStatefulWidget {
  final ValueChanged<Map<String, dynamic>> onUserSelected;

  const _NewChatSearchSheet({required this.onUserSelected});

  @override
  ConsumerState<_NewChatSearchSheet> createState() => _NewChatSearchSheetState();
}

class _NewChatSearchSheetState extends ConsumerState<_NewChatSearchSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  Timer? _debounce;
  String _searchFilter = 'all'; // 'all', 'id', 'email', 'name'

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    try {
      final list = await ref.read(chatRepositoryProvider).searchUsers(query.trim());
      if (mounted) {
        List<Map<String, dynamic>> filtered = list;
        if (query.trim().isNotEmpty) {
          final q = query.trim().toLowerCase();
          final qNorm = q.replaceAll('-', '').replaceAll(' ', '');
          if (_searchFilter == 'id') {
            filtered = list.where((u) {
              final sId = (u['studentId'] ?? u['student_id'] ?? '').toString().toLowerCase();
              return sId.contains(q) || sId.replaceAll('-', '').contains(qNorm);
            }).toList();
          } else if (_searchFilter == 'email') {
            filtered = list.where((u) {
              final em = (u['email'] ?? '').toString().toLowerCase();
              return em.contains(q);
            }).toList();
          } else if (_searchFilter == 'name') {
            filtered = list.where((u) {
              final nm = (u['name'] ?? '').toString().toLowerCase();
              return nm.contains(q);
            }).toList();
          }
        }
        setState(() {
          _results = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _hintText {
    switch (_searchFilter) {
      case 'id':
        return 'Enter Student ID (e.g. 252-15-234, 253-15-789)...';
      case 'email':
        return 'Enter Gmail / DIU Email (e.g. user@diu.edu.bd)...';
      case 'name':
        return 'Enter Student Name (e.g. Rahat, Abud)...';
      default:
        return 'Search by Student ID, Gmail, or Name...';
    }
  }

  Widget _buildFilterChip(String filterKey, String label, IconData icon) {
    final isSelected = _searchFilter == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _searchFilter = filterKey;
        });
        _search(_ctrl.text);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65100) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65100) : const Color(0xFFCBD5E1),
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFE65100).withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String textVal, {String? label}) {
    return GestureDetector(
      onTap: () {
        _ctrl.text = textVal;
        _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: textVal.length));
        _search(textVal);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFEDD5)),
        ),
        child: Text(
          label ?? textVal,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFFC2410C),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_search_rounded, color: Color(0xFFE65100), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find DIU Students & Bikers',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Search by Student ID, Gmail, or Name',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Filter Selector Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                _buildFilterChip('all', 'All Fields', Icons.grid_view_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('id', 'Student ID', Icons.badge_outlined),
                const SizedBox(width: 8),
                _buildFilterChip('email', 'Gmail / Email', Icons.mail_outline_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('name', 'Student Name', Icons.person_outline_rounded),
              ],
            ),
          ),

          // Search Input Field
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: false,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: _hintText,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _ctrl.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE65100), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Quick Suggestions Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 13, color: Color(0xFFE65100)),
                const SizedBox(width: 5),
                const Text(
                  'Suggestions: ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSuggestionChip('CSE', label: '🎓 Dept of CSE'),
                        _buildSuggestionChip('SWE', label: '💻 Dept of SWE'),
                        _buildSuggestionChip('EEE', label: '⚡ Dept of EEE'),
                        _buildSuggestionChip('BBA', label: '💼 Dept of BBA'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 14, color: Color(0xFFF1F5F9)),

          // Results list or loading
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE65100)),
              ),
            )
          else if (_results.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_search_rounded, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      _ctrl.text.isEmpty
                          ? 'No registered DIU peers available'
                          : 'No students found matching "${_ctrl.text}"',
                      style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Try searching by Student ID, Gmail, or Full Name above',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (ctx, index) {
                  final user = _results[index];
                  final name = user['name']?.toString() ?? 'DIU Student';
                  final dept = user['department']?.toString() ?? user['dept']?.toString() ?? 'DIU';
                  final sId = user['studentId']?.toString() ?? user['student_id']?.toString() ?? '';
                  final email = user['email']?.toString() ?? '';
                  final phone = user['phone']?.toString() ?? '';
                  final isBiker = user['isBiker'] == true;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: isBiker ? const Color(0xFFE65100) : const Color(0xFF0284C7),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBiker ? const Color(0xFFFFF8E1) : const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isBiker ? const Color(0xFFFDBA74) : const Color(0xFFBAE6FD),
                            ),
                          ),
                          child: Text(
                            isBiker ? '🏍️ Biker' : '🎓 Student',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isBiker ? const Color(0xFFC2410C) : const Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (sId.isNotEmpty) ...[
                                Text(
                                  'ID: $sId',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0284C7)),
                                ),
                                const Text(' • ', style: TextStyle(color: Color(0xFF94A3B8))),
                              ],
                              Text(
                                dept,
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email.isNotEmpty ? email : (phone.isNotEmpty ? '📞 $phone' : ''),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFE65100), size: 15),
                          SizedBox(width: 4),
                          Text(
                            'Chat',
                            style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    onTap: () => widget.onUserSelected(user),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
