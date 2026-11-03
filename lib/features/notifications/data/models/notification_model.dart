enum NotificationType {
  rideRequest,
  rideAccepted,
  rideRejected,
  rideCancelled,
  driverArriving,
  rideStarted,
  rideCompleted,
  chatMessage,
  safetyAlert,
  ridePublished,
}

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final String? relatedRideId;
  final String? relatedBookingId;
  final String? passengerName;

  /// If true, this notification needs a driver action (Accept / Reject)
  final bool requiresAction;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.relatedRideId,
    this.relatedBookingId,
    this.passengerName,
    this.requiresAction = false,
  });

  NotificationModel copyWith({
    bool? isRead,
    bool? requiresAction,
  }) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      type: type,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      relatedRideId: relatedRideId,
      relatedBookingId: relatedBookingId,
      passengerName: passengerName,
      requiresAction: requiresAction ?? this.requiresAction,
    );
  }
}
