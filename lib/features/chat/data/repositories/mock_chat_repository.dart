import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';

class MockChatRepository implements ChatRepository {
  final Map<String, List<ChatMessage>> _messages = {};
  final _streamController = StreamController<ChatMessage>.broadcast();

  MockChatRepository() {
    _seedMessages();
  }

  void _seedMessages() {
  }

  @override
  Future<List<ChatMessage>> getMessages(String rideId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _messages[rideId] ?? [];
  }

  @override
  Future<ChatMessage> sendMessage({
    required String rideId,
    required String text,
    bool isLocationShare = false,
    double? sharedLat,
    double? sharedLng,
    String? senderId,
    String? senderName,
    String? receiverId,
    String? senderMode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final msg = ChatMessage(
      id: 'msg_${const Uuid().v4().substring(0, 8)}',
      rideId: rideId,
      senderId: senderId ?? 'usr_diu_tanvir_201',
      senderName: senderName ?? 'Me',
      receiverId: receiverId,
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      isLocationShare: isLocationShare,
      sharedLat: sharedLat,
      sharedLng: sharedLng,
      senderMode: senderMode,
    );

    if (!_messages.containsKey(rideId)) {
      _messages[rideId] = [];
    }
    _messages[rideId]!.add(msg);
    _streamController.add(msg);

    return msg;
  }

  @override
  Stream<ChatMessage> subscribeToMessages(String rideId) {
    return _streamController.stream.where((m) => m.rideId == rideId);
  }

  @override
  Future<List<CampusConversationModel>> getConversations({String? userId}) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    return [
      {
        'id': 'usr_friend_01',
        'name': 'Sabbir Hossain',
        'department': 'CSE',
        'studentId': '211-15-1234',
        'phone': '01812345678',
        'isBiker': true,
        'rating': 4.9,
      },
    ];
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {}

  @override
  Future<ChatMessage?> retryFailedMessage(String rideId, String messageId) async {
    return null;
  }
}

