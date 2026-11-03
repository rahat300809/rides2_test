import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/config/app_config.dart';

class AiChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final List<Map<String, dynamic>> matchedRides;
  final List<Map<String, dynamic>> matchedRequests;

  AiChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.matchedRides = const [],
    this.matchedRequests = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, String> toHistoryJson() {
    return {
      'role': role,
      'content': content,
    };
  }
}

class AiChatResponse {
  final String reply;
  final String model;
  final List<Map<String, dynamic>> matchedRides;
  final List<Map<String, dynamic>> matchedRequests;

  AiChatResponse({
    required this.reply,
    required this.model,
    this.matchedRides = const [],
    this.matchedRequests = const [],
  });
}

class AiAssistantService {
  final Dio _dio;

  AiAssistantService([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  String get _apiBase => AppConfig.current.apiBaseUrl;

  Future<AiChatResponse> sendMessage({
    required String message,
    required String userName,
    String? userId,
    String userRole = 'passenger',
    List<AiChatMessage> history = const [],
  }) async {
    final url = '$_apiBase/ai/chat';

    final historyList = history
        .take(6)
        .map((m) => m.toHistoryJson())
        .toList();

    final payload = {
      'user_id': userId ?? '',
      'user_name': userName,
      'user_role': userRole,
      'message': message,
      'history': historyList,
    };

    try {
      final response = await _dio.post(url, data: payload);
      final data = response.data as Map<String, dynamic>;

      final reply = data['reply'] as String? ?? 'আসসালামু আলাইকুম! কোনো প্রতিক্রিয়া পাওয়া যায়নি।';
      final model = data['model'] as String? ?? 'Groq';

      final rawRides = data['matched_rides'] as List? ?? [];
      final matchedRides = rawRides.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final rawRequests = data['matched_requests'] as List? ?? [];
      final matchedRequests = rawRequests.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      return AiChatResponse(
        reply: reply,
        model: model,
        matchedRides: matchedRides,
        matchedRequests: matchedRequests,
      );
    } catch (e) {
      debugPrint('[AI Assistant Service Error]: $e');
      return AiChatResponse(
        reply: 'আসসালামু আলাইকুম $userName ভাইয়া/আপু! 🌸 সার্ভারের সাথে সংযোগ স্থাপনে সাময়িক সমস্যা হচ্ছে। অনুগ্রহ করে একটু পর পুনরায় চেষ্টা করুন অথবা সরাসরি হোমপেইজ থেকে রাইড অনুসন্ধান করুন।',
        model: 'Offline Fallback',
      );
    }
  }
}

final aiAssistantServiceProvider = Provider<AiAssistantService>((ref) {
  return AiAssistantService();
});
