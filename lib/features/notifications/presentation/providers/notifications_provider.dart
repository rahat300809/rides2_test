import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/notifications/data/models/notification_model.dart';
import 'package:diu_ride/core/services/system_notification_service.dart';

/// Global notification event bus — receives ride/booking lifecycle events
/// and surfaces them in the notifications screen + badge count.
class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier() : super(_initialNotifications());

  static List<NotificationModel> _initialNotifications() {
    final now = DateTime.now();
    return [
      NotificationModel(
        id: 'n_welcome',
        title: 'Welcome to DIU Ride 🎉',
        body:
            'Find & share campus rides with verified DIU students. Safe, affordable commuting.',
        type: NotificationType.safetyAlert,
        timestamp: now,
        isRead: true,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API — called by BookingProvider / RideProvider after events
  // ---------------------------------------------------------------------------

  /// Driver/user publishes a ride — creates in-app notification confirming ride status & visibility
  void onRidePublishedByMe({
    required String rideId,
    required String origin,
    required String destination,
    required DateTime departureTime,
    required double fare,
  }) {
    _add(NotificationModel(
      id: 'n_pub_${rideId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '🏍️ Your Ride is LIVE!',
      body:
          'Your ride $origin → $destination (৳${fare.toInt()}) is live. DIU passengers can view and book.',
      type: NotificationType.ridePublished,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
    ));
  }

  /// Convenience alias for onRidePublishedByMe
  void notifyDriverPublishedRide({
    required String rideId,
    required String origin,
    required String destination,
    required DateTime departureTime,
    required double fare,
  }) => onRidePublishedByMe(
        rideId: rideId,
        origin: origin,
        destination: destination,
        departureTime: departureTime,
        fare: fare,
      );

  /// Driver receives a new booking request from a passenger
  void onRideRequested({
    required String bookingId,
    required String rideId,
    required String passengerName,
    required String pickup,
    required String dropoff,
    required int seats,
    required double fare,
  }) {
    _add(NotificationModel(
      id: 'n_req_${bookingId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '🔔 New Ride Request!',
      body:
          '$passengerName wants $seats seat(s) • $pickup → $dropoff • ৳${fare.toInt()}',
      type: NotificationType.rideRequest,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
      relatedBookingId: bookingId,
      passengerName: passengerName,
      requiresAction: true,
    ));
  }

  /// Passenger receives confirmation their request was sent
  void onBookingRequestSent({
    required String bookingId,
    required String rideId,
    required String driverName,
    required double fare,
  }) {
    _add(NotificationModel(
      id: 'n_sent_$bookingId',
      title: 'Request Sent to $driverName',
      body:
          'Awaiting driver confirmation for your seat. Fare: ৳${fare.toInt()}',
      type: NotificationType.rideRequest,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
      relatedBookingId: bookingId,
    ));
  }

  /// Passenger's booking was accepted by driver
  void onBookingAccepted({
    required String bookingId,
    required String rideId,
    required String driverName,
    required String pickup,
  }) {
    // Remove the pending action notification for this booking
    state = state
        .where((n) => n.relatedBookingId != bookingId || !n.requiresAction)
        .toList();

    _add(NotificationModel(
      id: 'n_accept_$bookingId',
      title: '✅ Ride Confirmed!',
      body:
          '$driverName accepted your request. Be at $pickup on time.',
      type: NotificationType.rideAccepted,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
      relatedBookingId: bookingId,
    ));
  }

  /// Passenger's booking was rejected by driver
  void onBookingRejected({
    required String bookingId,
    required String rideId,
    required String driverName,
  }) {
    state = state
        .where((n) => n.relatedBookingId != bookingId || !n.requiresAction)
        .toList();

    _add(NotificationModel(
      id: 'n_reject_$bookingId',
      title: '❌ Ride Request Declined',
      body:
          '$driverName could not accommodate your request. Try another ride.',
      type: NotificationType.rideRejected,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
      relatedBookingId: bookingId,
    ));
  }

  /// Ride was started by driver — notify all accepted passengers
  void onRideStarted({
    required String rideId,
    required String driverName,
    required String pickup,
  }) {
    _add(NotificationModel(
      id: 'n_start_${rideId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '🚗 Driver is on the way!',
      body: '$driverName started the ride. Head to $pickup now.',
      type: NotificationType.driverArriving,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
    ));
  }

  /// Ride completed
  void onRideCompleted({
    required String rideId,
    required String driverName,
  }) {
    _add(NotificationModel(
      id: 'n_complete_$rideId',
      title: '🏁 Ride Completed',
      body: 'Trip with $driverName ended. Please rate your experience.',
      type: NotificationType.rideCompleted,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
    ));
  }

  /// Ride cancelled
  void onRideCancelled({
    required String rideId,
    required String reason,
  }) {
    _add(NotificationModel(
      id: 'n_cancel_${rideId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '❌ Ride Cancelled',
      body: reason,
      type: NotificationType.rideCancelled,
      timestamp: DateTime.now(),
      isRead: false,
      relatedRideId: rideId,
    ));
  }

  /// University notice sent from Admin Portal
  void onUniversityNotice({
    required String title,
    required String message,
    String? audience,
    String? id,
  }) {
    final noticeId = id ?? 'n_notice_${DateTime.now().millisecondsSinceEpoch}';
    
    // Prevent duplicate entries
    if (state.any((n) => n.id == noticeId)) return;

    _add(NotificationModel(
      id: noticeId,
      title: '📢 $title',
      body: message,
      type: NotificationType.safetyAlert,
      timestamp: DateTime.now(),
      isRead: false,
    ));
  }

  /// Sync all recent varsity notices from backend
  Future<void> syncNoticesFromServer(Dio dio, String apiBaseUrl) async {
    try {
      final res = await dio.get('$apiBaseUrl/admin/notices');
      if (res.statusCode == 200 && res.data is List) {
        for (final item in res.data as List) {
          if (item is Map) {
            final id = item['id']?.toString() ?? '';
            final title = item['title']?.toString() ?? 'Varsity Announcement';
            final content = item['content']?.toString() ?? item['message']?.toString() ?? '';
            if (id.isNotEmpty && !state.any((n) => n.id == id)) {
              _add(NotificationModel(
                id: id,
                title: '📢 $title',
                body: content,
                type: NotificationType.safetyAlert,
                timestamp: DateTime.tryParse(item['createdAt']?.toString() ?? '') ?? DateTime.now(),
                isRead: false,
              ));
            }
          }
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // READ STATE MANAGEMENT
  // ---------------------------------------------------------------------------

  void markAsRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
  }

  void markAllAsRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  /// Dismiss (remove) a notification completely
  void dismiss(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  int get unreadCount => state.where((n) => !n.isRead).length;

  /// Pending ride requests that need driver action (Accept/Reject)
  List<NotificationModel> get pendingRequests =>
      state.where((n) => n.requiresAction && !n.isRead).toList();

  /// Public method to add an arbitrary system or chat notification
  void addNotification(NotificationModel n) => _add(n);

  void _add(NotificationModel n) {
    // Print to terminal for debugging and verification
    // ignore: avoid_print
    print('[DIU_NOTIFICATION] ${n.title} - ${n.body}');
    // Prepend so newest is at top
    state = [n, ...state];

    // Trigger Mobile Phone Status Bar & Web Browser Notification Tray
    if (!n.isRead) {
      SystemNotificationService.showNotification(
        id: n.id,
        title: n.title,
        body: n.body,
      );
    }
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
        (ref) {
  return NotificationsNotifier();
});

/// Convenience provider for unread count badge
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider);
  return notifications.where((n) => !n.isRead).length;
});

/// Only pending action notifications (for driver alert alarm)
final pendingRideRequestsProvider = Provider<List<NotificationModel>>((ref) {
  final notifications = ref.watch(notificationsProvider);
  return notifications.where((n) => n.requiresAction && !n.isRead).toList();
});
