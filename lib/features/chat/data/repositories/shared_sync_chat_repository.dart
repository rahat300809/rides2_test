import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/utils/peer_dm_id.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';

class SharedSyncChatRepository implements ChatRepository {
  final PreferencesService? preferences;
  final WebSocketClient? wsClient;
  final _streamController = StreamController<ChatMessage>.broadcast();
  final Map<String, List<ChatMessage>> _cache = {};
  Timer? _pollingTimer;
  WebSocketConnectionStatus _wsStatus = WebSocketConnectionStatus.disconnected;
  StreamSubscription? _wsStatusSub;
  StreamSubscription? _wsMsgSub;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
  ));

  SharedSyncChatRepository({this.preferences, this.wsClient}) {
    _listenWebSocket();
    _listenWsStatus();
    _startPolling();
  }

  /// Dedupe by durable id only (WhatsApp keeps intentional "ok" / "ok" repeats).
  bool _isDuplicate(ChatMessage a, ChatMessage b) => a.id == b.id;

  void _listenWsStatus() {
    _wsStatusSub = wsClient?.status.listen((s) {
      _wsStatus = s;
      if (s == WebSocketConnectionStatus.connected) {
        // Catch-up sync after reconnect
        for (final rideId in _cache.keys.toList()) {
          unawaited(_syncThread(rideId));
        }
      }
    });
  }

  void _listenWebSocket() {
    _wsMsgSub = wsClient?.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      final data = msg['data'];
      if ((event == 'chat_message' || event == 'new_message' || event == 'message_sent') &&
          data is Map) {
        try {
          final chatMsg = ChatMessage.fromJson(
            Map<String, dynamic>.from(data),
            _currentUserId,
          ).copyWith(deliveryStatus: MessageDeliveryStatus.delivered);

          final targetKeys = <String>{chatMsg.rideId};
          for (final key in _cache.keys) {
            if (key == chatMsg.rideId ||
                (key.startsWith('peer_dm_') &&
                    chatMsg.rideId.startsWith('peer_dm_') &&
                    isSamePeerDm(key, chatMsg.rideId))) {
              targetKeys.add(key);
            }
          }

          for (final key in targetKeys) {
            final list = _cache.putIfAbsent(key, () => []);
            final idx = list.indexWhere((m) => m.id == chatMsg.id);
            final mapped = key != chatMsg.rideId
                ? chatMsg.copyWith(rideId: key)
                : chatMsg;
            if (idx >= 0) {
              // Upgrade optimistic/sending → delivered
              list[idx] = mapped.copyWith(
                deliveryStatus: list[idx].isMe
                    ? MessageDeliveryStatus.sent
                    : MessageDeliveryStatus.delivered,
              );
            } else {
              list.add(mapped);
            }
            list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            _streamController.add(list.lastWhere((m) => m.id == mapped.id));
          }
        } catch (_) {}
      } else if (event == 'messages_read' && data is Map) {
        final convId = (data['conversationId'] ?? data['rideId'] ?? '').toString();
        final readerId = (data['readerId'] ?? '').toString();
        if (convId.isEmpty) return;
        for (final key in _cache.keys) {
          if (key != convId && !isSamePeerDm(key, convId)) continue;
          final list = _cache[key]!;
          for (var i = 0; i < list.length; i++) {
            if (list[i].isMe && readerId.isNotEmpty && readerId != _currentUserId) {
              list[i] = list[i].copyWith(
                isRead: true,
                deliveryStatus: MessageDeliveryStatus.read,
              );
              _streamController.add(list[i]);
            }
          }
        }
      }
    });
  }

  String get _currentUserId {
    final cached = preferences?.getUserJson();
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        return decoded['id']?.toString() ?? 'usr_current';
      } catch (_) {}
    }
    return 'usr_current';
  }

  String get _apiBase => AppConfig.current.apiBaseUrl;

  void _startPolling() {
    // Poll only as WhatsApp-style catch-up when WS is down (not every 3s forever).
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (_wsStatus == WebSocketConnectionStatus.connected) return;
      for (final rideId in _cache.keys.toList()) {
        await _syncThread(rideId);
      }
    });
  }

  Future<void> _syncThread(String rideId) async {
    try {
      final res = await _dio.get('$_apiBase/messages?ride_id=$rideId');
      if (res.statusCode == 200 && res.data is List) {
        final serverMsgs = (res.data as List)
            .map((m) => ChatMessage.fromJson(
                Map<String, dynamic>.from(m as Map), _currentUserId))
            .toList();
        final currentKnown = _cache.putIfAbsent(rideId, () => []);
        for (final msg in serverMsgs) {
          final idx = currentKnown.indexWhere((e) => e.id == msg.id);
          if (idx < 0) {
            currentKnown.add(msg);
            _streamController.add(msg);
          } else if (currentKnown[idx].deliveryStatus == MessageDeliveryStatus.sending ||
              currentKnown[idx].deliveryStatus == MessageDeliveryStatus.failed) {
            currentKnown[idx] = msg.copyWith(deliveryStatus: MessageDeliveryStatus.sent);
            _streamController.add(currentKnown[idx]);
          }
        }
        currentKnown.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    } catch (_) {}
  }

  @override
  Future<List<ChatMessage>> getMessages(String rideId) async {
    try {
      final response = await _dio.get('$_apiBase/messages?ride_id=$rideId');
      if (response.statusCode == 200 && response.data is List) {
        final list = (response.data as List)
            .map((item) => ChatMessage.fromJson(
                Map<String, dynamic>.from(item as Map), _currentUserId))
            .toList();

        // Keep local pending/failed (Messenger: unsent stay until retry)
        final local = _cache[rideId] ?? [];
        final pending = local
            .where((m) =>
                m.deliveryStatus == MessageDeliveryStatus.sending ||
                m.deliveryStatus == MessageDeliveryStatus.failed)
            .where((m) => !list.any((s) => s.id == m.id))
            .toList();
        final merged = [...list, ...pending]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _cache[rideId] = merged;
        return merged;
      }
    } catch (e) {
      debugPrint('Get messages error (fallback to local cache): $e');
    }
    return _cache[rideId] ?? [];
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
    final msg = ChatMessage(
      id: 'msg_${const Uuid().v4()}',
      rideId: rideId,
      senderId: senderId ?? _currentUserId,
      senderName: (senderName != null &&
              senderName.trim().isNotEmpty &&
              senderName != 'Me')
          ? senderName.trim()
          : 'DIU Student',
      receiverId: receiverId,
      text: text,
      timestamp: DateTime.now().toUtc(),
      isMe: true,
      isRead: false,
      isLocationShare: isLocationShare,
      sharedLat: sharedLat,
      sharedLng: sharedLng,
      senderMode: senderMode,
      deliveryStatus: MessageDeliveryStatus.sending,
    );

    final currentList = _cache.putIfAbsent(rideId, () => []);
    if (!currentList.any((m) => m.id == msg.id)) {
      currentList.add(msg);
      currentList.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _streamController.add(msg);
    }

    // Persist-first (server broadcasts once) — like WhatsApp.
    try {
      await _dio.post('$_apiBase/messages', data: msg.toJson());
      final idx = currentList.indexWhere((m) => m.id == msg.id);
      final sent = msg.copyWith(deliveryStatus: MessageDeliveryStatus.sent);
      if (idx >= 0) currentList[idx] = sent;
      _streamController.add(sent);
      return sent;
    } catch (e) {
      debugPrint('[Chat] REST persist failed: $e');
      final idx = currentList.indexWhere((m) => m.id == msg.id);
      final failed = msg.copyWith(deliveryStatus: MessageDeliveryStatus.failed);
      if (idx >= 0) currentList[idx] = failed;
      _streamController.add(failed);
      return failed;
    }
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _dio.post('$_apiBase/messages/mark-read', data: {
        'conversationId': conversationId,
        'rideId': conversationId,
        'userId': userId,
      });
    } catch (e) {
      debugPrint('[Chat] mark-read failed: $e');
    }
  }

  @override
  Future<ChatMessage?> retryFailedMessage(String rideId, String messageId) async {
    final list = _cache[rideId];
    if (list == null) return null;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return null;
    final old = list[idx];
    if (old.deliveryStatus != MessageDeliveryStatus.failed) return old;

    list[idx] = old.copyWith(deliveryStatus: MessageDeliveryStatus.sending);
    _streamController.add(list[idx]);
    try {
      await _dio.post('$_apiBase/messages', data: old.toJson());
      list[idx] = old.copyWith(deliveryStatus: MessageDeliveryStatus.sent);
      _streamController.add(list[idx]);
      return list[idx];
    } catch (_) {
      list[idx] = old.copyWith(deliveryStatus: MessageDeliveryStatus.failed);
      _streamController.add(list[idx]);
      return list[idx];
    }
  }

  @override
  Stream<ChatMessage> subscribeToMessages(String rideId) {
    _cache.putIfAbsent(rideId, () => []);
    return _streamController.stream.where((m) {
      if (m.rideId == rideId) return true;
      if (rideId.startsWith('peer_dm_') && m.rideId.startsWith('peer_dm_')) {
        return isSamePeerDm(rideId, m.rideId);
      }
      return false;
    });
  }

  @override
  Future<List<CampusConversationModel>> getConversations({String? userId}) async {
    try {
      final uid = userId ?? _currentUserId;
      final response = await _dio.get('$_apiBase/conversations?user_id=$uid');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CampusConversationModel.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('SharedSyncChatRepository: getConversations failed: $e');
    }
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final res = await _dio.get(
          '$_apiBase/users/search?q=${Uri.encodeComponent(query)}&exclude_id=$_currentUserId');
      if (res.statusCode == 200 && res.data is List) {
        return List<Map<String, dynamic>>.from(
          (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (e) {
      debugPrint('searchUsers error: $e');
    }
    return [];
  }

  void dispose() {
    _pollingTimer?.cancel();
    _wsStatusSub?.cancel();
    _wsMsgSub?.cancel();
    _streamController.close();
  }
}
