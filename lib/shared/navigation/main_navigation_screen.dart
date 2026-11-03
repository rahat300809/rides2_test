import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/home/presentation/screens/home_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/all_shared_rides_screen.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:dio/dio.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/services/system_notification_service.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_expiry_extension_dialog.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/providers/mode_session_provider.dart';
import 'package:diu_ride/shared/widgets/diu_app_header.dart';
import 'package:diu_ride/shared/widgets/diu_bottom_nav.dart';
import 'package:diu_ride/shared/widgets/mode_bootstrap_overlay.dart';
import 'package:diu_ride/features/feed/presentation/providers/feed_provider.dart';
import 'package:diu_ride/features/feed/presentation/screens/campus_feed_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentTab = 0;
  int _unreadChatCount = 0;
  int _lastModeGeneration = 0;
  StreamSubscription? _wsSubscription;
  DateTime? _lastBackPressTime;
  Map<String, dynamic>? _activeTripInfo;

  // Tab index mapping:
  // 0 → Home
  // 1 → All Shared Rides (Location filters, price sort, card details)
  // 2 → Offer Ride (Create bike ride)
  // 3 → Campus SMS & Community Messages
  // 4 → Campus News Feed

  final List<String> _titles = [
    'Home',
    'All Shared Rides',
    'Offer Ride',
    'Campus Messages',
    'Campus News Feed',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupWebSocketLiveUpdates();
      _syncInitialVarsityNotices();
      _checkActiveUserTrip();
    });
  }

  Future<void> _checkActiveUserTrip() async {
    try {
      final user = ref.read(authNotifierProvider).user;
      if (user == null || user.id.isEmpty) return;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final apiBase = AppConfig.current.apiBaseUrl;
      final res = await dio.get('$apiBase/chat/session/active-user-trip', queryParameters: {'user_id': user.id});
      if (res.statusCode == 200 && res.data is Map) {
        final d = Map<String, dynamic>.from(res.data as Map);
        if (mounted) {
          setState(() {
            if (d['hasActiveTrip'] == true) {
              _activeTripInfo = d;
            } else {
              _activeTripInfo = null;
            }
          });
        }
      }
    } catch (_) {}
  }

  void _showDivergeAlertFromMain(Map<String, dynamic> data) {
    if (!mounted) return;
    NotificationSoundService.playMessageChime();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Are you end the ride?'),
          ],
        ),
        content: const Text(
          'You and your companion are not in the same location for the last 2 minutes. Did you arrive at your destination?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Still on Ride'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final user = ref.read(authNotifierProvider).user;
                final dio = Dio();
                await dio.post('${AppConfig.current.apiBaseUrl}/chat/session/end', data: {
                  'conversationId': data['conversationId'],
                  'userId': user?.id ?? '',
                  'userName': user?.name ?? 'Student',
                });
                _checkActiveUserTrip();
              } catch (_) {}
            },
            child: const Text('Yes, End Trip'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTripBanner() {
    if (_activeTripInfo == null) return const SizedBox();
    final pName = _activeTripInfo!['peerName'] ?? 'Companion';
    final origin = _activeTripInfo!['origin'] ?? 'Campus';
    final dest = _activeTripInfo!['destination'] ?? 'Destination';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF065F46)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF047857).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                rideId: _activeTripInfo!['conversationId'] ?? '',
                peerName: pName,
                peerRole: 'Companion',
                peerId: _activeTripInfo!['peerId'],
              ),
            ),
          ).then((_) => _checkActiveUserTrip());
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.two_wheeler, color: Color(0xFF047857), size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🟢 YOU ARE ON A RIDE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    'With $pName • $origin ➔ $dest • Tap to open chat & map',
                    style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  void _syncInitialVarsityNotices() async {
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final apiBase = AppConfig.current.apiBaseUrl;
      await ref.read(notificationsProvider.notifier).syncNoticesFromServer(dio, apiBase);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    NotificationSoundService.stopRinging();
    super.dispose();
  }

  void _setupWebSocketLiveUpdates() {
    try {
      final wsClient = ref.read(webSocketClientProvider);
      _wsSubscription?.cancel();
      _wsSubscription = wsClient.messages.listen((msg) {
        final event = msg['event'] ?? msg['type'];
        final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : msg;
        final modeSession = ref.read(modeSessionProvider);
        if (modeSession.isBootstrapping) return;

        final appMode = ref.read(appModeProvider);

        // 1. Live rides updates (New ride published, booked, started, completed, or deleted)
        if (event == 'ride_created' ||
            event == 'new_ride' ||
            event == 'ride_updated' ||
            event == 'ride_started' ||
            event == 'ride_completed' ||
            event == 'ride_cancelled' ||
            event == 'ride_deleted' ||
            event == 'post_deleted' ||
            event == 'booking_created' ||
            event == 'booking_status_updated') {
          debugPrint('[Live WS] Received $event - refreshing live rides cache');
          ref.invalidate(allAvailableRidesProvider);
          ref.invalidate(allSystemRidesProvider);
          ref.invalidate(departingSoonRidesProvider);
          if (appMode.isRider) {
            ref.invalidate(myPostedRidesProvider);
          }
          if (appMode.isPassenger) {
            ref.invalidate(myBookingsProvider);
          }
          ref.invalidate(searchRidesResultsProvider);
        }

        // 1b. Live ride booking request alert for rider only
        if (event == 'ride_booking_request' && appMode.isRider) {
          _handleRideBookingRequest(data);
        }

        // 1c. Live booking accepted alert for passenger only
        if (event == 'ride_booking_accepted' && appMode.isPassenger) {
          _handleRideBookingAccepted(data);
        }

        // 1d. Ride session status changed (Confirm / Cancel / Complete)
        if (event == 'ride_session_status_changed' || event == 'chat_session_state_changed') {
          _handleRideSessionStatusChanged(data);
          final sState = data['sessionState']?.toString() ?? data['status']?.toString();
          if (sState == 'inProgress' || sState == 'in_progress' || sState == 'awaitingEnd') {
            _checkActiveUserTrip();
          } else if (sState == 'completed' || sState == 'cancelled') {
            if (mounted) setState(() => _activeTripInfo = null);
          }
        }

        // 1e. GPS Divergence Alert (separated by 800m for 2 minutes)
        if (event == 'trip_diverge_alert') {
          _showDivergeAlertFromMain(data);
        }

        // 2. Live student requests — Biker watches incoming; Student refreshes own list
        if (event == 'passenger_request_created' ||
            event == 'new_passenger_request' ||
            event == 'passenger_request_accepted') {
          debugPrint('[Live WS] Received $event - refreshing passenger requests');
          if (appMode.isRider) {
            ref.invalidate(passengerRequestsProvider);
            ref.invalidate(allPassengerRequestsProvider);
          } else if (appMode.isPassenger) {
            ref.invalidate(myPassengerRequestsProvider);
          }
        }

        // 2b. Live Campus Feed Updates
        if (event.startsWith('campus_feed_')) {
          ref.read(feedProvider.notifier).handleWebSocketEvent(event, data);
        }

        // 3. Urgent dedicated alert ring buzzer
        if (event == 'alert_ring') {
          _showAlertRingBuzzer(data);
        }

        // 4. Remote stop ring signal from caller
        if (event == 'stop_ring') {
          _handleRemoteStopRing(data);
        }

        // 5. Live incoming chat message notification
        if (event == 'chat_message') {
          _handleIncomingChatMessage(data);
        }

        // 6. University Varsity Authority Notice
        if (event == 'university_notice' || event == 'announcement') {
          _handleUniversityNotice(data);
        }

        // 7. Scheduled ride / request time arrived - prompt extension
        if (event == 'schedule_time_expired_needs_extension') {
          _handleScheduleTimeExpiredNeedsExtension(data);
        }

        // 8. Post expired and deleted from server/database
        if (event == 'post_expired_and_deleted') {
          _handlePostExpiredAndDeleted(data);
        }

        // 9. Mutual confirm took the post — notify other chatting students
        if (event == 'ride_taken_by_other') {
          _handleRideTakenByOther(data);
        }

        // 10. Confirm reminders (2 min x 3) / auto-suspend
        if (event == 'confirm_reminder') {
          _handleConfirmReminder(data);
        }
        if (event == 'ride_suspended') {
          _handleRideSuspended(data);
        }
      });
    } catch (e) {
      debugPrint('[MainNavigation] WebSocket live update init error: $e');
    }
  }

  void _handleRideTakenByOther(Map<String, dynamic> data) {
    if (!mounted) return;
    final msg = (data['message'] ??
            'The rider accepted another student. Please find a new rider.')
        .toString();
    NotificationSoundService.playMessageChime();
    SystemNotificationService.showNotification(
      title: 'Ride taken by another companion',
      body: msg,
      id: 'taken_${data['sourcePostId'] ?? DateTime.now().millisecondsSinceEpoch}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFB45309),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myPostedRidesProvider);
    ref.invalidate(myBookingsProvider);
    ref.invalidate(passengerRequestsProvider);
  }

  void _handleConfirmReminder(Map<String, dynamic> data) {
    if (!mounted) return;
    final count = data['reminderCount'] ?? '?';
    final max = data['maxReminders'] ?? 3;
    final msg = (data['message'] ??
            'Please confirm the ride. Reminder $count/$max')
        .toString();
    NotificationSoundService.playMessageChime();
    SystemNotificationService.showNotification(
      title: (data['title'] ?? 'Confirm ride reminder').toString(),
      body: msg,
      id: 'confirm_rem_${data['conversationId'] ?? count}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0369A1),
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  void _handleRideSuspended(Map<String, dynamic> data) {
    if (!mounted) return;
    final msg = (data['message'] ??
            'Ride post suspended because confirmation was not completed.')
        .toString();
    NotificationSoundService.playMessageChime();
    SystemNotificationService.showNotification(
      title: 'Ride post suspended',
      body: msg,
      id: 'susp_${data['sourcePostId'] ?? DateTime.now().millisecondsSinceEpoch}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFB45309),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myPostedRidesProvider);
    ref.invalidate(allSystemRidesProvider);
  }

  void _handleScheduleTimeExpiredNeedsExtension(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final targetUserId = (data['userId'] ?? '').toString().trim();
    final targetUserName = (data['userName'] ?? '').toString().trim();
    final isOwner = targetUserId.isNotEmpty && (
      targetUserId == currentAuth.id ||
      targetUserId == currentAuth.studentId ||
      (currentAuth.phone.isNotEmpty && targetUserId == currentAuth.phone) ||
      (targetUserName.isNotEmpty && targetUserName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isOwner) return;

    final postId = (data['id'] ?? '').toString();
    final postType = (data['post_type'] ?? 'ride').toString();
    final title = (data['title'] ?? 'Commute Post').toString();
    final timeStr = data['time_str']?.toString();
    final minutesRemaining = (data['minutes_remaining'] as num?)?.toInt() ?? 30;

    NotificationSoundService.playMessageChime();
    SystemNotificationService.showNotification(
      title: '⚠️ Scheduled Ride Time Reached: Extend Time',
      body: 'Your post ($title) reached its departure time. Please extend within 30 mins or it will be deleted.',
      id: 'ext_$postId',
    );

    PostExpiryExtensionDialog.show(
      context,
      postId: postId,
      postType: postType,
      title: title,
      scheduledTimeStr: timeStr,
      initialMinutesRemaining: minutesRemaining,
    );
  }

  void _handlePostExpiredAndDeleted(Map<String, dynamic> data) {
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(departingSoonRidesProvider);
    ref.invalidate(passengerRequestsProvider);

    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final targetUserId = (data['userId'] ?? '').toString().trim();
    final isOwner = targetUserId.isNotEmpty && (
      targetUserId == currentAuth.id ||
      targetUserId == currentAuth.studentId ||
      (currentAuth.phone.isNotEmpty && targetUserId == currentAuth.phone)
    );

    if (isOwner) {
      final title = (data['title'] ?? 'Post').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Scheduled post "$title" expired after 30 mins and was automatically removed.'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleUniversityNotice(Map<String, dynamic> data) {
    if (!mounted) return;
    final title = data['title']?.toString() ?? 'Official Varsity Notice';
    final message = data['message']?.toString() ??
        data['content']?.toString() ??
        data['body']?.toString() ??
        '';
    final audience = data['audience']?.toString() ??
        data['targetAudience']?.toString() ??
        'all';
    final noticeId = data['id']?.toString() ?? 'notc_${DateTime.now().millisecondsSinceEpoch}';

    // ignore: avoid_print
    print('[DIU_NOTIFICATION] Varsity Authority Notice received: $title | $message | Audience: $audience');
    NotificationSoundService.playMessageChime();

    try {
      ref.read(notificationsProvider.notifier).onUniversityNotice(
        title: title,
        message: message,
        audience: audience,
        id: noticeId,
      );
    } catch (_) {}

    // Invoke native Android Status Bar Notification
    SystemNotificationService.showNotification(
      title: '📢 DIU Notice: $title',
      body: message,
      id: noticeId,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign, color: Color(0xFFE65100), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Varsity Authority Notice',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  Text(
                    'Daffodil International University',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.45),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
  }

  BuildContext? _activeRingDialogContext;

  void _handleRemoteStopRing(Map<String, dynamic> msg) {
    NotificationSoundService.stopRinging();
    if (_activeRingDialogContext != null && mounted) {
      try {
        Navigator.of(_activeRingDialogContext!).pop();
      } catch (_) {}
      _activeRingDialogContext = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ringing was cancelled by caller.'),
          backgroundColor: Color(0xFFD84315),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAlertRingBuzzer(Map<String, dynamic> msg) {
    if (!mounted) return;

    final targetUserId = (msg['targetUserId'] ?? '').toString().trim();
    final targetName = (msg['targetName'] ?? '').toString().trim();
    final senderId = (msg['senderId'] ?? '').toString().trim();
    final sender = (msg['senderName'] ?? 'Campus Peer').toString();
    final alertMsg = msg['message'] ?? '🚨 Urgent: Attention requested for pickup!';
    final rideId = msg['rideId']?.toString() ?? 'general';
    final ringId = (msg['ringId'] ?? msg['id'] ?? '').toString();

    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    // Check if current user is the sender (NEVER ring the caller themselves!)
    final isSender = senderId.isNotEmpty && (
        senderId == currentAuth.id ||
        senderId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && senderId == currentAuth.phone) ||
        (currentAuth.email.isNotEmpty && senderId.toLowerCase() == currentAuth.email.toLowerCase()) ||
        (sender.isNotEmpty && sender.toLowerCase() == currentAuth.name.toLowerCase())
    );
    if (isSender) return; // Do not ring yourself

    // Dedicated ring check: only ring if this user is explicitly targeted
    final tIdLower = targetUserId.toLowerCase();
    final tNameLower = targetName.toLowerCase();
    final cNameLower = currentAuth.name.toLowerCase();
    final cIdLower = currentAuth.id.toLowerCase();
    final cStudentLower = currentAuth.studentId.toLowerCase();
    final cPhone = currentAuth.phone.replaceAll(RegExp(r'[^\d]'), '');
    final tPhone = targetUserId.replaceAll(RegExp(r'[^\d]'), '');

    final bool phoneMatch = (cPhone.isNotEmpty && tPhone.isNotEmpty && (cPhone == tPhone || (cPhone.length >= 8 && tPhone.endsWith(cPhone.substring(cPhone.length - 8)))));
    final bool nameMatch = (tNameLower.isNotEmpty && (cNameLower.contains(tNameLower) || tNameLower.contains(cNameLower))) ||
                           (tIdLower.isNotEmpty && (cNameLower.contains(tIdLower) || tIdLower.contains(cNameLower)));
    final bool idMatch = (tIdLower.isNotEmpty && (tIdLower == cIdLower || tIdLower == cStudentLower));

    final isTarget = phoneMatch || nameMatch || idMatch || targetUserId == 'all';

    if (!isTarget) return; // Dedicated! Ignore rings targeted at other students

    // Play loud dedicated ringing buzzer sound + continuous vibration
    NotificationSoundService.playRingAlert(durationSeconds: 25);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _activeRingDialogContext = ctx;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBE6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active, color: Color(0xFFD84315), size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Incoming Ring Alert!',
                  style: TextStyle(color: Color(0xFFD84315), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$sender is ringing you!',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  alertMsg,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      side: const BorderSide(color: Color(0xFFD32F2F)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.call_end, size: 18),
                    label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      NotificationSoundService.stopRinging();
                      _activeRingDialogContext = null;
                      Navigator.pop(ctx);
                      try {
                        ref.read(ridesRepositoryProvider).stopAlertRing(
                          targetUserId: targetUserId,
                          senderId: senderId,
                          ringId: ringId,
                        );
                      } catch (_) {}
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('Answer Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      NotificationSoundService.stopRinging();
                      _activeRingDialogContext = null;
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            rideId: rideId,
                            peerName: sender,
                            driverName: sender,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ).then((_) {
      _activeRingDialogContext = null;
      NotificationSoundService.stopRinging();
    });
  }

  void _handleIncomingChatMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
    final senderId = msg['senderId']?.toString() ?? '';

    // Ignore messages sent by self
    if (senderId.isNotEmpty && senderId == currentUserId) return;

    // Play crisp notification chime
    NotificationSoundService.playMessageChime();

    setState(() {
      _unreadChatCount++;
    });

    final senderName = msg['senderName'] ?? 'Campus Peer';
    final text = msg['text'] ?? 'Sent a message';

    // 1. Post to Mobile System Notification Drawer & Lockscreen (Messenger style)
    SystemNotificationService.showNotification(
      title: senderName.toString(),
      body: text.toString(),
      id: 'chat_${msg['id'] ?? DateTime.now().millisecondsSinceEpoch}',
    );

    // 2. Chat messages are not added to notifications list (they stay in Messages tab / DM)
  }

  void _handleRideBookingRequest(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final driverId = (data['driverId'] ?? '').toString().trim();
    final driverName = (data['driverName'] ?? '').toString().trim();

    final isDriver = driverId.isNotEmpty && (
        driverId == currentAuth.id ||
        driverId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && driverId == currentAuth.phone) ||
        (driverName.isNotEmpty && driverName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isDriver) return;

    NotificationSoundService.playMessageChime();
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myBookingsProvider);

    final passengerName = data['passengerName'] ?? 'Student';
    final pickup = data['pickup'] ?? 'Campus';
    final dropoff = data['dropoff'] ?? 'Destination';
    final rideId = data['rideId']?.toString() ?? 'general';
    final bookingId = data['bookingId']?.toString() ?? '';
    final seats = (data['seats'] as num?)?.toInt() ?? 1;
    final fare = (data['totalFare'] as num?)?.toDouble() ?? 0.0;

    // Add to in-app notification system and update bell badge
    ref.read(notificationsProvider.notifier).onRideRequested(
      bookingId: bookingId,
      rideId: rideId,
      passengerName: passengerName,
      pickup: pickup,
      dropoff: dropoff,
      seats: seats,
      fare: fare,
    );

    // Post to Mobile System Notification Drawer & Lockscreen (Messenger style)
    SystemNotificationService.showNotification(
      title: '🏍️ Ride Request from $passengerName',
      body: '$passengerName: $pickup ➔ $dropoff. Tap to coordinate.',
      id: 'req_${bookingId.isNotEmpty ? bookingId : DateTime.now().millisecondsSinceEpoch}',
    );

    // Minimal, professional compact floating snackbar (3s duration)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF141416),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFE65100),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Seat Booking Request',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  Text(
                    passengerName + ' • ' + pickup + ' ➔ ' + dropoff,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Chat',
          textColor: const Color(0xFFFFA000),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: rideId,
                  peerName: passengerName,
                  driverName: currentAuth.name,
                  peerRole: 'Passenger',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleRideBookingAccepted(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final passengerId = (data['passengerId'] ?? '').toString().trim();
    final passengerName = (data['passengerName'] ?? '').toString().trim();

    final isPassenger = passengerId.isNotEmpty && (
        passengerId == currentAuth.id ||
        passengerId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && passengerId == currentAuth.phone) ||
        (passengerName.isNotEmpty && passengerName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isPassenger) return;

    NotificationSoundService.playMessageChime();
    ref.invalidate(myBookingsProvider);
    ref.invalidate(allAvailableRidesProvider);

    final driverName = data['driverName'] ?? 'Rider';
    final rideId = data['rideId']?.toString() ?? 'general';
    final bookingId = data['bookingId']?.toString() ?? '';
    final pickup = data['pickup']?.toString() ?? 'Campus';

    // Add to in-app notification system and update bell badge
    ref.read(notificationsProvider.notifier).onBookingAccepted(
      bookingId: bookingId,
      rideId: rideId,
      driverName: driverName,
      pickup: pickup,
    );

    // Post to Mobile System Notification Drawer & Lockscreen (Messenger style)
    SystemNotificationService.showNotification(
      title: '✅ Ride Accepted by $driverName',
      body: '$driverName accepted your seat request! Tap to coordinate.',
      id: 'acc_${bookingId.isNotEmpty ? bookingId : DateTime.now().millisecondsSinceEpoch}',
    );

    // Minimal, professional compact floating snackbar (3s duration)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF141416),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ride Confirmed by Rider',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  Text(
                    driverName + ' accepted your seat request.',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Chat',
          textColor: const Color(0xFF34D399),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: rideId,
                  peerName: driverName,
                  driverName: driverName,
                  peerRole: 'Rider',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleRideSessionStatusChanged(Map<String, dynamic> data) {
    if (!mounted) return;
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myBookingsProvider);

    final status = data['status']?.toString();
    final rideId = data['rideId']?.toString() ?? 'general';
    final driverName = data['driverName']?.toString() ?? 'Rider';
    final pickup = data['pickup']?.toString() ?? 'Campus';

    if (status == 'in_progress') {
      NotificationSoundService.playMessageChime();
      ref.read(notificationsProvider.notifier).onRideStarted(
        rideId: rideId,
        driverName: driverName,
        pickup: pickup,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🚀 Ride started • Safe commuting!'),
          backgroundColor: const Color(0xFF141416),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else if (status == 'completed') {
      NotificationSoundService.playMessageChime();
      ref.read(notificationsProvider.notifier).onRideCompleted(
        rideId: rideId,
        driverName: driverName,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🏁 Trip Completed! Have a great day!'),
          backgroundColor: const Color(0xFF141416),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else if (status == 'cancelled') {
      final reason = data['cancelReason'] ?? 'Cancelled by user';
      ref.read(notificationsProvider.notifier).onRideCancelled(
        rideId: rideId,
        reason: reason.toString(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ride was cancelled: $reason'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _onTabSelected(int index) async {
    final appMode = ref.read(appModeProvider);
    if (index == 2) {
      if (appMode.isPassenger) {
        PostRideRequestSheet.show(context);
        return;
      } else {
        final ok = await MotorcycleConfigDialog.ensureConfigured(context, ref);
        if (!ok || !mounted) return;
      }
    }
    setState(() {
      _currentTab = index;
      if (index == 3) {
        _unreadChatCount = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modeSession = ref.watch(modeSessionProvider);
    final appMode = ref.watch(appModeProvider);

    // Hard remount: dispose previous mode's IndexedStack tree entirely.
    if (modeSession.generation != _lastModeGeneration) {
      _lastModeGeneration = modeSession.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _currentTab = 0;
          _unreadChatCount = 0;
        });
      });
    }

    // Screens that render their own AppBar (no DiuAppHeader needed)
    final noHeaderTabs = {0, 1, 2, 3, 4}; // All primary tabs (Home, Rides, Offer, Messages, Profile) provide clean dedicated headers
    final shellKey = ValueKey('mode_shell_${modeSession.generation}_${appMode.name}');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (modeSession.isBootstrapping) return;

        // If currently on any sub-tab (Rides, Offer, Messages, Profile),
        // pressing back takes the user back to Home (Tab 0) instead of exiting!
        if (_currentTab != 0) {
          setState(() {
            _currentTab = 0;
          });
          return;
        }

        // On Home Tab: Require double-tap within 2 seconds to exit gracefully
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Press back again to exit DIU Ride',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            ),
          );
          return;
        }

        // Within 2 seconds on home tab: exit app
        SystemNavigator.pop();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.surface,
            appBar: noHeaderTabs.contains(_currentTab)
                ? null
                : DiuAppHeader(
                    title: _titles[_currentTab],
                    onProfileTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    onNotificationsTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
            body: Column(
              children: [
                _buildActiveTripBanner(),
                Expanded(
                  child: IndexedStack(
                    key: shellKey,
                    index: _currentTab,
                    children: [
                      // 0. Home Screen
                      HomeScreen(
                        key: ValueKey('home_$shellKey'),
                        onNavigateTab: _onTabSelected,
                        onSearchQuery: (query) {
                          ref.read(rideSearchFilterProvider.notifier).setDropoff(query);
                        },
                      ),

                      // 1. All Shared Rides Screen
                      AllSharedRidesScreen(key: ValueKey('rides_$shellKey')),

                      // 2. Offer / Create Ride Screen
                      OfferRideScreen(
                        key: ValueKey('offer_$shellKey'),
                        onRidePublished: () {
                          _onTabSelected(1); // Jump to All Rides after publishing
                        },
                      ),

                      // 3. Campus SMS & Direct Messages
                      CampusMessagesScreen(
                        key: ValueKey('messages_$shellKey'),
                        onExploreRides: () => _onTabSelected(1),
                      ),

                      // 4. Campus News Feed
                      CampusFeedScreen(key: ValueKey('feed_$shellKey')),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: DiuBottomNav(
              currentIndex: _currentTab,
              onTap: modeSession.isBootstrapping ? (_) {} : _onTabSelected,
              unreadChats: _unreadChatCount,
            ),
          ),
          const ModeBootstrapOverlay(),
        ],
      ),
    );
  }
}
