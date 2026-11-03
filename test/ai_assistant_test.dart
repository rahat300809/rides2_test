import 'package:flutter_test/flutter_test.dart';
import 'package:diu_ride/features/ai_assistant/data/ai_assistant_service.dart';

void main() {
  group('DIU Ride AI Assistant Service Tests', () {
    test('AiChatMessage formats history JSON correctly', () {
      final userMsg = AiChatMessage(
        role: 'user',
        content: 'Mirpur 10 theke 8:30 e bike ache?',
      );
      final asstMsg = AiChatMessage(
        role: 'assistant',
        content: 'Assalamu Alaikum! Haa Tanvir bhai er ride ache.',
      );

      final userJson = userMsg.toHistoryJson();
      final asstJson = asstMsg.toHistoryJson();

      expect(userJson['role'], equals('user'));
      expect(userJson['content'], contains('Mirpur 10'));
      expect(asstJson['role'], equals('assistant'));
      expect(asstJson['content'], contains('Tanvir'));
    });

    test('AiChatResponse correctly holds matched rides and requests', () {
      final response = AiChatResponse(
        reply: 'Assalamu Alaikum! Found 1 match.',
        model: 'openai/gpt-oss-120b',
        matchedRides: [
          {
            'id': 'ride_101',
            'driver_name': 'Tanvir',
            'origin_name': 'Mirpur 10',
            'destination_name': 'Daffodil Smart City',
            'fare_per_seat': 50.0,
            'available_seats': 1,
            'vehicle_model': 'Yamaha FZ-S',
          }
        ],
        matchedRequests: [],
      );

      expect(response.model, equals('openai/gpt-oss-120b'));
      expect(response.matchedRides.length, equals(1));
      expect(response.matchedRides.first['driver_name'], equals('Tanvir'));
      expect(response.matchedRequests, isEmpty);
    });
  });
}
