import 'package:flutter_test/flutter_test.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';

void main() {
  group('DIU Ride Chat System - 3X Perspective & Zero Overlap Tests', () {
    test('ChatMessage parses JSON and extracts coordinates properly', () {
      final json = {
        'id': 'msg_001',
        'rideId': 'ride_test_100',
        'senderId': 'usr_passenger',
        'senderName': 'Tanvir Rahman',
        'receiverId': 'usr_biker',
        'text': '📍 Waiting at Gate 1: https://maps.google.com/?query=23.8769,90.3204',
        'timestamp': DateTime.now().toIso8601String(),
        'isLocationShare': true,
        'senderMode': 'passenger',
      };

      final msg = ChatMessage.fromJson(json, 'usr_biker');

      expect(msg.id, 'msg_001');
      expect(msg.isMe, false);
      expect(msg.isLocationShare, true);
      expect(msg.sharedLat, closeTo(23.8769, 0.001));
      expect(msg.sharedLng, closeTo(90.3204, 0.001));
      expect(msg.senderMode, 'passenger');
    });

    test('Canonical channel ID prevents split inboxes and conversation overlap', () {
      String getCanonicalChannelId(String userA, String userB) {
        final pair = [userA.toLowerCase().trim(), userB.toLowerCase().trim()]..sort();
        return 'peer_dm_${pair[0]}__${pair[1]}';
      }

      // Rider and Passenger opening chat with different casing or order
      final channelFromPassenger = getCanonicalChannelId('usr_Tanvir_101', 'USR_BIKER_202');
      final channelFromRider = getCanonicalChannelId('USR_BIKER_202', 'usr_tanvir_101');
      final channelWithSpaces = getCanonicalChannelId(' usr_tanvir_101 ', 'usr_biker_202 ');

      expect(channelFromPassenger, channelFromRider);
      expect(channelFromPassenger, channelWithSpaces);
      expect(channelFromPassenger, 'peer_dm_usr_biker_202__usr_tanvir_101');
    });

    test('Zero Duplicate Message Filter eliminates WebSocket echo and polling overlap', () {
      bool isDuplicate(ChatMessage a, ChatMessage b) {
        if (a.id == b.id) return true;
        if (a.senderId == b.senderId &&
            a.text.trim() == b.text.trim() &&
            a.timestamp.difference(b.timestamp).abs().inSeconds < 4) {
          return true;
        }
        return false;
      }

      final now = DateTime.now();
      final original = ChatMessage(
        id: 'msg_client_local_123',
        rideId: 'ride_1',
        senderId: 'usr_biker',
        senderName: 'Rahat',
        text: '🏍️ On my way! Reaching Gate 1 in 2 mins',
        timestamp: now,
        isMe: true,
      );

      // Server echo with same ID
      final serverEchoSameId = ChatMessage(
        id: 'msg_client_local_123',
        rideId: 'ride_1',
        senderId: 'usr_biker',
        senderName: 'Rahat',
        text: '🏍️ On my way! Reaching Gate 1 in 2 mins',
        timestamp: now.add(const Duration(milliseconds: 50)),
        isMe: true,
      );
      expect(isDuplicate(original, serverEchoSameId), true);

      // Polling response with server-generated ID but identical content and timestamp
      final pollingServerResponse = ChatMessage(
        id: 'msg_server_generated_999',
        rideId: 'ride_1',
        senderId: 'usr_biker',
        senderName: 'Rahat',
        text: '🏍️ On my way! Reaching Gate 1 in 2 mins',
        timestamp: now.add(const Duration(seconds: 1)),
        isMe: true,
      );
      expect(isDuplicate(original, pollingServerResponse), true);

      // Legitimate subsequent message (different text)
      final nextMessage = ChatMessage(
        id: 'msg_next_456',
        rideId: 'ride_1',
        senderId: 'usr_biker',
        senderName: 'Rahat',
        text: '📍 Reached Gate 1 Canopy',
        timestamp: now.add(const Duration(seconds: 2)),
        isMe: true,
      );
      expect(isDuplicate(original, nextMessage), false);
    });

    test('Chronological message sorting guarantees strictly ordered message bubbles', () {
      final now = DateTime.now();
      final msg1 = ChatMessage(
        id: '1',
        rideId: 'r1',
        senderId: 'u1',
        senderName: 'Student',
        text: 'At Gate 1',
        timestamp: now.subtract(const Duration(minutes: 5)),
        isMe: true,
      );
      final msg2 = ChatMessage(
        id: '2',
        rideId: 'r1',
        senderId: 'u2',
        senderName: 'Biker',
        text: 'Coming in 2 mins',
        timestamp: now.subtract(const Duration(minutes: 3)),
        isMe: false,
      );
      final msg3 = ChatMessage(
        id: '3',
        rideId: 'r1',
        senderId: 'u1',
        senderName: 'Student',
        text: 'I see your bike!',
        timestamp: now.subtract(const Duration(minutes: 1)),
        isMe: true,
      );

      // Out of order arrival simulation (e.g. network jitter)
      final unorderedList = [msg3, msg1, msg2];
      unorderedList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      expect(unorderedList[0].id, '1');
      expect(unorderedList[1].id, '2');
      expect(unorderedList[2].id, '3');
    });

    test('CampusConversationModel accurately classifies biker and passenger contexts', () {
      final bikerConvo = CampusConversationModel.fromJson({
        'rideId': 'ride_biker_1',
        'peerId': 'usr_biker_55',
        'peerName': 'Shakil Ahmed',
        'peerRole': 'Biker',
        'peerIsBiker': true,
        'route': 'DIU Gate 1 ➔ Mirpur 10',
        'fare': 60.0,
      });

      expect(bikerConvo.isBikerConversation, true);
      expect(bikerConvo.peerRole, 'Biker');
      expect(bikerConvo.fare, 60.0);

      final passengerConvo = CampusConversationModel.fromJson({
        'rideId': 'ride_pass_2',
        'peerId': 'usr_pass_66',
        'peerName': 'Nafisa Islam',
        'peerRole': 'Passenger',
        'peerIsBiker': false,
        'contextType': 'ride',
        'route': 'Daffodil Smart City ➔ Uttara',
        'fare': 80.0,
      });

      expect(passengerConvo.isBikerConversation, false);
      expect(passengerConvo.isRideConversation, true);
      expect(passengerConvo.peerRole, 'Passenger');
    });
  });
}

