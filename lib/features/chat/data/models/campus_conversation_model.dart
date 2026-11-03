class CampusConversationModel {
  final String id;
  final String rideId;
  final String peerId;
  final String peerName;
  final String peerRole;
  final String peerPhone;
  final String peerDept;
  final String peerStudentId;
  final String peerEmail;
  final bool peerIsBiker;
  // 'ride' | 'bike' | 'friend'
  final String contextType;
  final String route;
  final String origin;
  final String destination;
  final String vehicleModel;
  final double fare;
  final String status;
  final String bookingId;
  final String lastMessage;
  final String lastTimestamp;
  final String lastSenderName;
  final int unreadCount;

  final String chatContext; // 'peer' | 'from_ride_post' | 'from_passenger_request'
  final String sourcePostId;
  final String sessionState; // 'idle' | 'awaitingConfirm' | 'bothConfirmed' | 'awaitingStart' | 'inProgress' | 'awaitingEnd' | 'completed' | 'cancelled'
  final bool hasActiveTrip;

  const CampusConversationModel({
    String? id,
    required this.rideId,
    required this.peerId,
    required this.peerName,
    required this.peerRole,
    required this.peerPhone,
    required this.peerDept,
    this.peerStudentId = '',
    this.peerEmail = '',
    this.peerIsBiker = false,
    this.contextType = 'ride',
    this.chatContext = 'peer',
    this.sourcePostId = '',
    this.sessionState = 'idle',
    this.hasActiveTrip = false,
    required this.route,
    required this.origin,
    required this.destination,
    required this.vehicleModel,
    required this.fare,
    required this.status,
    required this.bookingId,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.lastSenderName,
    this.unreadCount = 0,
  }) : id = id ?? rideId;

  factory CampusConversationModel.fromJson(Map<String, dynamic> json) {
    final rid = json['rideId']?.toString() ?? '';
    final sState = json['sessionState']?.toString() ?? json['session_state']?.toString() ?? 'idle';
    final hasTrip = json['hasActiveTrip'] as bool? ?? (sState == 'inProgress' || sState == 'awaitingEnd' || sState == 'bothConfirmed');
    return CampusConversationModel(
      id: json['id']?.toString() ?? rid,
      rideId: rid,
      peerId: json['peerId']?.toString() ?? '',
      peerName: json['peerName']?.toString() ?? 'DIU Student',
      peerRole: json['peerRole']?.toString() ?? 'Passenger',
      peerPhone: json['peerPhone']?.toString() ?? '',
      peerDept: json['peerDept']?.toString() ?? 'DIU Department',
      peerStudentId: json['peerStudentId']?.toString() ?? json['peer_student_id']?.toString() ?? '',
      peerEmail: json['peerEmail']?.toString() ?? json['peer_email']?.toString() ?? '',
      peerIsBiker: json['peerIsBiker'] as bool? ?? false,
      contextType: json['contextType']?.toString() ?? 'ride',
      chatContext: json['chatContext']?.toString() ?? json['chat_context']?.toString() ?? 'peer',
      sourcePostId: json['sourcePostId']?.toString() ?? json['source_post_id']?.toString() ?? '',
      sessionState: sState,
      hasActiveTrip: hasTrip,
      route: json['route']?.toString() ?? '',
      origin: json['origin']?.toString() ?? 'Campus Gate',
      destination: json['destination']?.toString() ?? 'Destination Spot',
      vehicleModel: json['vehicleModel']?.toString() ?? 'DIU Verified Bike',
      fare: (json['fare'] as num?)?.toDouble() ?? 35.0,
      status: json['status']?.toString() ?? 'active',
      bookingId: json['bookingId']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? 'Tap to open chat',
      lastTimestamp: json['lastTimestamp']?.toString() ?? '',
      lastSenderName: json['lastSenderName']?.toString() ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether this conversation is a biker (bike-mode) conversation
  bool get isBikerConversation => peerIsBiker || contextType == 'bike' || peerRole.toLowerCase().contains('biker');
  /// Whether this conversation is a ride-sharing (car/ride mode) conversation
  bool get isRideConversation => !isBikerConversation && (contextType == 'ride' || peerRole.toLowerCase().contains('rider') || peerRole.toLowerCase().contains('passenger'));
  /// Whether this is a direct friend conversation (no ride)
  bool get isFriendConversation => contextType == 'friend';
}
