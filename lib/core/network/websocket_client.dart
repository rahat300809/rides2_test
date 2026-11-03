import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';

final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  final client = WebSocketClient();

  // 1. If user is already authenticated at startup, connect with user_id immediately
  final currentUser = ref.read(authNotifierProvider).user;
  final initialUid = currentUser != null && currentUser.id.isNotEmpty
      ? currentUser.id
      : (currentUser != null && currentUser.studentId.isNotEmpty ? currentUser.studentId : null);
  client.connect(userId: initialUid);

  // 2. Listen to auth changes: whenever a user logs in, identify on the active socket
  ref.listen(authNotifierProvider, (previous, next) {
    final nextUser = next.user;
    if (nextUser != null) {
      if (nextUser.id.isNotEmpty) {
        client.identify(nextUser.id);
      }
      if (nextUser.studentId.isNotEmpty) {
        client.identify(nextUser.studentId);
      }
    }
  });

  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

enum WebSocketConnectionStatus { connecting, connected, disconnected }

class WebSocketClient {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<WebSocketConnectionStatus>.broadcast();
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isDisposed = false;
  final bool _useFallback = false;
  String? _currentUserId;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WebSocketConnectionStatus> get status => _statusController.stream;
  bool get isConnected => _channel != null;

  void identify(String userId) {
    final clean = userId.trim();
    if (clean.isEmpty) return;
    _currentUserId = clean;
    if (_channel != null) {
      send('identify', {'userId': clean});
      debugPrint('[WebSocket] Identified user: $clean');
    }
  }

  void connect({String? customUrl, String? userId}) {
    if (userId != null && userId.trim().isNotEmpty) {
      _currentUserId = userId.trim();
    }
    if (AppConfig.current.useMockData) {
      _statusController.add(WebSocketConnectionStatus.connected);
      return;
    }

    var url = customUrl ??
        (_useFallback ? AppConfig.fallbackWsUrl : AppConfig.current.wsBaseUrl);
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url${sep}user_id=${Uri.encodeComponent(_currentUserId!)}';
    }

    try {
      _statusController.add(WebSocketConnectionStatus.connecting);
      debugPrint('[WebSocket] Connecting to $url');
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _statusController.add(WebSocketConnectionStatus.connected);

      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        send('identify', {'userId': _currentUserId!});
      }

      _startPing();

      _channel?.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString()) as Map<String, dynamic>;
            _messageController.add(decoded);
          } catch (e) {
            debugPrint('WebSocket parse error: $e');
          }
        },
        onError: (err) {
          debugPrint('WebSocket error on $url: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed on $url');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed on $url: $e');
      _handleDisconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    // 10-second heartbeat ping prevents mobile carriers and Cloudflare from terminating idle sockets
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_channel != null && !_isDisposed) {
        try {
          _channel?.sink.add(jsonEncode({'event': 'ping', 'timestamp': DateTime.now().toIso8601String()}));
        } catch (_) {}
      }
    });
  }

  void _handleDisconnect() {
    _statusController.add(WebSocketConnectionStatus.disconnected);
    _pingTimer?.cancel();
    _channel = null;

    if (!_isDisposed) {
      _reconnectTimer?.cancel();
      // Fast 1.5-second reconnect so users never experience stalled messaging
      _reconnectTimer = Timer(const Duration(milliseconds: 1500), () {
        connect();
      });
    }
  }

  void send(String event, Map<String, dynamic> data) {
    final payload = jsonEncode({'event': event, 'data': data});
    if (_channel != null) {
      try {
        _channel?.sink.add(payload);
        return;
      } catch (e) {
        debugPrint('WebSocket send failed: $e');
      }
    }
    debugPrint('[WS Offline send buffer] Event: $event Payload: $payload');
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _messageController.close();
    _statusController.close();
  }
}
