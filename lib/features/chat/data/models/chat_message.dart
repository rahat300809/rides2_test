enum MessageDeliveryStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  final String id;
  final String rideId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final bool isLocationShare;
  final double? sharedLat;
  final double? sharedLng;
  final String? receiverId;
  final String? senderMode;
  final MessageDeliveryStatus deliveryStatus;

  const ChatMessage({
    required this.id,
    required this.rideId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
    this.isRead = false,
    this.isLocationShare = false,
    this.sharedLat,
    this.sharedLng,
    this.receiverId,
    this.senderMode,
    this.deliveryStatus = MessageDeliveryStatus.sent,
  });

  ChatMessage copyWith({
    bool? isRead,
    MessageDeliveryStatus? deliveryStatus,
    String? rideId,
  }) {
    return ChatMessage(
      id: id,
      rideId: rideId ?? this.rideId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      timestamp: timestamp,
      isMe: isMe,
      isRead: isRead ?? this.isRead,
      isLocationShare: isLocationShare,
      sharedLat: sharedLat,
      sharedLng: sharedLng,
      receiverId: receiverId,
      senderMode: senderMode,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    double? lat = (json['sharedLat'] as num?)?.toDouble();
    double? lng = (json['sharedLng'] as num?)?.toDouble();
    final text = (json['text'] as String?) ?? '';
    bool isLoc = json['isLocationShare'] as bool? ?? false;

    // Auto-detect & parse coordinates from Google Maps URL or text
    if ((lat == null || lng == null) && (isLoc || text.contains('google.com/maps') || text.contains('maps.google.com') || text.contains('📍'))) {
      final match = RegExp(r'query=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text) ??
          RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})').firstMatch(text);
      if (match != null) {
        lat = double.tryParse(match.group(1)!);
        lng = double.tryParse(match.group(2)!);
        isLoc = true;
      }
    }

    final mode = json['senderMode'] as String? ??
        json['sender_mode'] as String? ??
        json['senderRole'] as String?;

    final isMe = json['senderId'] == currentUserId;
    final isRead = json['isRead'] as bool? ?? false;
    return ChatMessage(
      id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      rideId: json['rideId'] as String? ?? 'general',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'DIU Commuter',
      receiverId: json['receiverId'] as String?,
      text: text,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isMe: isMe,
      isRead: isRead,
      isLocationShare: isLoc,
      sharedLat: lat,
      sharedLng: lng,
      senderMode: mode,
      deliveryStatus: isMe
          ? (isRead ? MessageDeliveryStatus.read : MessageDeliveryStatus.sent)
          : MessageDeliveryStatus.delivered,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rideId': rideId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'isLocationShare': isLocationShare,
      'sharedLat': sharedLat,
      'sharedLng': sharedLng,
      'senderMode': senderMode,
    };
  }
}
