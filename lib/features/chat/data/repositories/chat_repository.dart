import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';

abstract class ChatRepository {
  Future<List<ChatMessage>> getMessages(String rideId);
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
  });
  Stream<ChatMessage> subscribeToMessages(String rideId);
  Future<List<CampusConversationModel>> getConversations({String? userId});
  Future<List<Map<String, dynamic>>> searchUsers(String query);
  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  });
  Future<ChatMessage?> retryFailedMessage(String rideId, String messageId);
}
