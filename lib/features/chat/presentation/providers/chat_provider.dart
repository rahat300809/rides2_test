import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';
import 'package:diu_ride/features/chat/data/repositories/shared_sync_chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final prefs = ref.watch(preferencesProvider);
  final ws = ref.watch(webSocketClientProvider);
  return SharedSyncChatRepository(preferences: prefs, wsClient: ws);
});

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isConnected;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isConnected = true,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isConnected,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final Ref _ref;
  final String _rideId;
  StreamSubscription? _sub;
  StreamSubscription? _wsStatusSub;

  ChatNotifier(this._repository, this._ref, this._rideId) : super(const ChatState()) {
    Future.microtask(() async {
      await loadMessages(showLoading: true);
      _subscribe();
      await markRead();
      _wsStatusSub = _ref.read(webSocketClientProvider).status.listen((s) {
        if (!mounted) return;
        state = state.copyWith(
          isConnected: s == WebSocketConnectionStatus.connected,
        );
      });
    });
  }

  bool get mounted => true; // StateNotifier always "mounted" until disposed

  Future<void> markRead() async {
    final user = _ref.read(authNotifierProvider).user;
    if (user == null) return;
    await _repository.markConversationRead(
      conversationId: _rideId,
      userId: user.id,
    );
    // Locally mark peer→me messages as read in UI
    final updated = state.messages.map((m) {
      if (!m.isMe) return m.copyWith(isRead: true);
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
    _ref.invalidate(campusConversationsProvider);
  }

  Future<void> loadMessages({bool showLoading = false}) async {
    if (showLoading || state.messages.isEmpty) {
      state = state.copyWith(isLoading: true);
    }
    final msgs = await _repository.getMessages(_rideId);
    final currentUserId = _ref.read(authNotifierProvider).user?.id ?? 'current_user';
    final adjusted = msgs
        .map((m) => m.copyWith(
              // ensure isMe for current session
            ))
        .map((m) => ChatMessage(
              id: m.id,
              rideId: m.rideId,
              senderId: m.senderId,
              senderName: m.senderName,
              receiverId: m.receiverId,
              text: m.text,
              timestamp: m.timestamp,
              isMe: m.senderId == currentUserId,
              isRead: m.isRead,
              isLocationShare: m.isLocationShare,
              sharedLat: m.sharedLat,
              sharedLng: m.sharedLng,
              senderMode: m.senderMode,
              deliveryStatus: m.deliveryStatus,
            ))
        .toList();

    // Preserve in-flight sending/failed from current state
    for (final local in state.messages) {
      if ((local.deliveryStatus == MessageDeliveryStatus.sending ||
              local.deliveryStatus == MessageDeliveryStatus.failed) &&
          !adjusted.any((m) => m.id == local.id)) {
        adjusted.add(local);
      }
    }

    adjusted.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = state.copyWith(isLoading: false, messages: adjusted);
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _repository.subscribeToMessages(_rideId).listen((newMsg) {
      final currentUserId = _ref.read(authNotifierProvider).user?.id ?? 'current_user';
      final formatted = ChatMessage(
        id: newMsg.id,
        rideId: newMsg.rideId,
        senderId: newMsg.senderId,
        senderName: newMsg.senderName,
        receiverId: newMsg.receiverId,
        text: newMsg.text,
        timestamp: newMsg.timestamp,
        isMe: newMsg.senderId == currentUserId,
        isRead: newMsg.isRead,
        isLocationShare: newMsg.isLocationShare,
        sharedLat: newMsg.sharedLat,
        sharedLng: newMsg.sharedLng,
        senderMode: newMsg.senderMode,
        deliveryStatus: newMsg.deliveryStatus,
      );

      final idx = state.messages.indexWhere((m) => m.id == formatted.id);
      if (idx >= 0) {
        final updated = [...state.messages];
        updated[idx] = formatted;
        state = state.copyWith(messages: updated);
      } else {
        final updated = [...state.messages, formatted]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        state = state.copyWith(messages: updated);
      }
    });
  }

  Future<void> sendMessage(String text, {String? receiverId, String? senderMode}) async {
    if (text.trim().isEmpty) return;
    final user = _ref.read(authNotifierProvider).user;
    final currentAppMode = _ref.read(appModeProvider);
    final effectiveMode = senderMode ??
        (currentAppMode == AppMode.rider
            ? 'rider'
            : (currentAppMode == AppMode.passenger ? 'passenger' : 'chat'));
    final msg = await _repository.sendMessage(
      rideId: _rideId,
      text: text.trim(),
      senderId: user?.id ?? 'usr_peer',
      senderName: user?.name ?? 'DIU Student',
      receiverId: receiverId,
      senderMode: effectiveMode,
    );

    final idx = state.messages.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      final updated = [...state.messages];
      updated[idx] = msg;
      state = state.copyWith(messages: updated);
    } else {
      final updated = [...state.messages, msg]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      state = state.copyWith(messages: updated);
    }
    _ref.invalidate(campusConversationsProvider);
  }

  Future<void> retryMessage(String messageId) async {
    final msg = await _repository.retryFailedMessage(_rideId, messageId);
    if (msg == null) return;
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final updated = [...state.messages];
      updated[idx] = msg;
      state = state.copyWith(messages: updated);
    }
  }

  Future<void> shareLocation(double lat, double lng, {String? receiverId}) async {
    final user = _ref.read(authNotifierProvider).user;
    final msg = await _repository.sendMessage(
      rideId: _rideId,
      text: '📍 Shared current campus coordinates',
      isLocationShare: true,
      sharedLat: lat,
      sharedLng: lng,
      senderId: user?.id ?? 'usr_peer',
      senderName: user?.name ?? 'DIU Student',
      receiverId: receiverId,
    );

    final idx = state.messages.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      final updated = [...state.messages];
      updated[idx] = msg;
      state = state.copyWith(messages: updated);
    } else {
      state = state.copyWith(messages: [...state.messages, msg]);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wsStatusSub?.cancel();
    super.dispose();
  }
}

final chatNotifierProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>((ref, rideId) {
  final repo = ref.watch(chatRepositoryProvider);
  return ChatNotifier(repo, ref, rideId);
});

final campusConversationsProvider =
    FutureProvider<List<CampusConversationModel>>((ref) async {
  final repo = ref.watch(chatRepositoryProvider);
  final user = ref.watch(authNotifierProvider).user;
  return repo.getConversations(userId: user?.id);
});
