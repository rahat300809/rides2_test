import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String driverName;
  final String? peerName;
  final String vehicleModel;
  final String? peerPhone;
  final String? peerRole;
  final String? peerId;
  final String? chatContext; // 'peer' | 'from_ride_post' | 'from_passenger_request'
  final String? sourcePostId;

  const ChatScreen({
    super.key,
    required this.rideId,
    this.driverName = 'Ride Companion',
    this.peerName,
    this.vehicleModel = 'Campus Ride',
    this.peerPhone,
    this.peerRole,
    this.peerId,
    this.chatContext,
    this.sourcePostId,
  });

  String get displayName {
    if (peerName != null && peerName!.isNotEmpty && !peerName!.startsWith('usr_') && peerName!.toLowerCase() != 'system') {
      return peerName!;
    }
    if (driverName != 'Campus Driver' && !driverName.startsWith('usr_')) {
      return driverName;
    }
    final raw = peerName ?? peerId ?? '';
    if (raw.startsWith('usr_')) {
      return 'Student ${raw.replaceFirst('usr_', '').replaceAll('_', '-')}';
    }
    return 'DIU Student';
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription? _wsSessionSub;
  Timer? _rideProgressTimer;
  int _rideElapsedSeconds = 0;
  bool _isLoadingSession = false;
  final bool _isPureChatMode = false; // Toggle between pure messaging app and ride mode
  bool _hasActiveTrip = false; // True ONLY if connected via orders or posts
  bool _showQuickReplies = true; // Toggle quick replies chips bar

  // Realtime peer typing indicator state
  bool _isPeerTyping = false;
  Timer? _typingTimer;
  Timer? _debounceTypingTimer;

  String get baseRideId {
    if (widget.rideId.contains('__')) {
      return widget.rideId.split('__')[0];
    }
    return widget.rideId;
  }

  String get effectiveChatId {
    if (widget.rideId.startsWith('peer_dm_')) {
      final clean = widget.rideId.replaceFirst('peer_dm_', '').split('__');
      if (clean.length == 2) {
        final pair = [clean[0].toLowerCase().trim(), clean[1].toLowerCase().trim()]..sort();
        return 'peer_dm_${pair[0]}__${pair[1]}';
      }
      return widget.rideId;
    }
    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
    final pId = widget.peerId;
    if (pId != null && pId.isNotEmpty && currentUserId.isNotEmpty && pId != currentUserId) {
      final sorted = [currentUserId.toLowerCase().trim(), pId.toLowerCase().trim()]..sort();
      return 'peer_dm_${sorted[0]}__${sorted[1]}';
    }
    if (widget.rideId.contains('__')) {
      final parts = widget.rideId.split('__');
      if (parts.length >= 3) {
        final sorted = [parts[1].toLowerCase().trim(), parts[2].toLowerCase().trim()]..sort();
        return 'peer_dm_${sorted[0]}__${sorted[1]}';
      }
      return widget.rideId;
    }
    return widget.rideId;
  }

  // Session state variables
  String _sessionStatus = 'idle'; // 'idle', 'awaitingConfirm', 'bothConfirmed', 'awaitingStart', 'inProgress', 'awaitingEnd', 'completed', 'cancelled'
  bool _riderConfirmed = false;
  bool _passengerConfirmed = false;
  bool _tripStarterA = false;
  bool _tripStarterB = false;
  bool _tripEnderA = false;
  bool _tripEnderB = false;
  Timer? _proximityTimer;
  DateTime? _rideStartTime;
  String _cancelReason = '';
  double _rideFare = 60.0;
  String _originName = 'DIU Campus';
  String _destinationName = 'Destination';
  double _totalDurationMinutes = 0.0;
  String? _resolvedPeerPhone;
  String? _resolvedPeerName;
  String? _resolvedStudentId;
  String? _resolvedDept;
  String? _resolvedEmail;

  String get effectiveDisplayName {
    if (_resolvedPeerName != null && _resolvedPeerName!.isNotEmpty && !_resolvedPeerName!.startsWith('usr_')) {
      return _resolvedPeerName!;
    }
    return widget.displayName;
  }

  String get effectivePhone => _resolvedPeerPhone ?? widget.peerPhone ?? '';
  String get effectiveStudentId => _resolvedStudentId ?? (widget.peerId?.startsWith('usr_') == true ? widget.peerId!.replaceFirst('usr_', '').replaceAll('_', '-') : '');

  // Live GPS Map Tracking state (Rider & Passenger Live Radar)
  LatLng? _riderLocation;
  LatLng? _passengerLocation;
  LatLng? _destLocation;
  List<LatLng> _liveRoutePoints = [];
  double _riderToPassengerDistanceKm = 0.0;
  int _riderToPassengerEtaMins = 0;

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateDivider(DateTime dt) {
    final now = DateTime.now();
    if (_isSameDay(dt, now)) return 'Today';
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onMessageInputChanged);
    Future.microtask(() {
      final curUser = ref.read(authNotifierProvider).user;
      if (curUser != null) {
        final ws = ref.read(webSocketClientProvider);
        if (curUser.id.isNotEmpty) ws.identify(curUser.id);
        if (curUser.studentId.isNotEmpty) ws.identify(curUser.studentId);
      }
      _loadSessionStatus();
      _fetchPeerUserProfile();
      _listenWebSocketSession();
      _loadSharedLocationsAndComputeRoute();
    });
  }

  Future<void> _fetchPeerUserProfile() async {
    final peerId = widget.peerId;
    if (peerId == null || peerId.isEmpty) return;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final res = await dio.get('$_apiBase/users/$peerId');
      if (res.statusCode == 200 && res.data is Map) {
        final d = Map<String, dynamic>.from(res.data as Map);
        final phone = d['phone']?.toString();
        final name = d['name']?.toString();
        final studentId = d['student_id']?.toString() ?? d['studentId']?.toString();
        if (mounted) {
          setState(() {
            if (phone != null && phone.isNotEmpty) _resolvedPeerPhone = phone;
            if (name != null && name.isNotEmpty && !name.startsWith('usr_') && name.toLowerCase() != 'system') {
              _resolvedPeerName = name;
            }
            if (studentId != null && studentId.isNotEmpty) _resolvedStudentId = studentId;
          });
        }
      }
    } catch (_) {}
  }

  void _onMessageInputChanged() {
    if (mounted) setState(() {});
    _debounceTypingTimer?.cancel();
    _debounceTypingTimer = Timer(const Duration(milliseconds: 300), () {
      final isTyping = _messageController.text.trim().isNotEmpty;
      _sendTypingEvent(isTyping);
    });
  }

  void _sendTypingEvent(bool isTyping) {
    try {
      final user = ref.read(authNotifierProvider).user;
      final ws = ref.read(webSocketClientProvider);
      ws.send('typing_status', {
        'rideId': effectiveChatId,
        'baseRideId': baseRideId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Companion',
        'peerId': widget.peerId ?? '',
        'isTyping': isTyping,
      });
    } catch (_) {}
  }

  Future<void> _triggerAlertRing() async {
    final user = ref.read(authNotifierProvider).user;
    final senderName = user?.name ?? 'Commuter';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = widget.peerPhone?.isNotEmpty == true
        ? widget.peerPhone!
        : (widget.peerId?.isNotEmpty == true
            ? widget.peerId!
            : (widget.peerName?.isNotEmpty == true ? widget.peerName! : widget.driverName));

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withOpacity(0.15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9500).withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ringing ${widget.displayName}...',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dedicated alert buzzer is ringing on their phone. Tap Stop to cancel at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.call_end, size: 20),
                      label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () async {
                        NotificationSoundService.stopRinging();
                        try {
                          await ref.read(ridesRepositoryProvider).stopAlertRing(
                            targetUserId: targetId,
                            senderId: user?.id,
                            ringId: ringId,
                          );
                        } catch (_) {}
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ringing stopped.'),
                              backgroundColor: Color(0xFFD32F2F),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: targetId,
        targetName: widget.displayName,
        senderId: user?.id ?? '',
        senderName: senderName,
        rideId: widget.rideId,
        ringId: ringId,
        message: '🚨 Urgent: $senderName is ringing you for pickup!',
      );
    } catch (_) {}

    ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(
      '🚨 [Alert Ring] Dedicated attention buzz sent to ${widget.displayName}',
      receiverId: widget.peerId,
    );
    _scrollToBottom();
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _debounceTypingTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.removeListener(_onMessageInputChanged);
    _rideProgressTimer?.cancel();
    _wsSessionSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _apiBase => AppConfig.current.apiBaseUrl;

  Future<void> _loadSessionStatus() async {
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus') {
      if (mounted) setState(() => _hasActiveTrip = false);
      return;
    }
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final targetId = effectiveChatId.isNotEmpty ? effectiveChatId : baseRideId;

      // 1. Check or initiate the persistent state-machine conversation
      final myUser = ref.read(authNotifierProvider).user;
      final myUserId = myUser?.id ?? '';
      String targetPeerId = widget.peerId ?? '';
      if (targetPeerId.isEmpty && widget.rideId.startsWith('peer_dm_')) {
        final pairIds = widget.rideId.replaceFirst('peer_dm_', '').split('__');
        targetPeerId = pairIds.firstWhere((id) => id != myUserId, orElse: () => '');
      }

      if (myUserId.isNotEmpty && targetPeerId.isNotEmpty) {
        try {
          final convRes = await dio.post('$_apiBase/chat/session/get-or-create', data: {
            'userId': myUserId,
            'peerId': targetPeerId,
            'chatContext': widget.chatContext ?? (widget.sourcePostId != null ? 'from_ride_post' : 'peer'),
            'sourcePostId': widget.sourcePostId ?? (widget.rideId.startsWith('peer_dm_') ? '' : widget.rideId),
          });
          if (convRes.statusCode == 200 && convRes.data is Map) {
            final cd = Map<String, dynamic>.from(convRes.data as Map);
            final sState = cd['session_state']?.toString() ?? cd['sessionState']?.toString() ?? 'idle';
            if (mounted) {
              setState(() {
                _sessionStatus = sState;
                _riderConfirmed = cd['rider_confirmed'] == 1 || cd['riderConfirmed'] == true;
                _passengerConfirmed = cd['passenger_confirmed'] == 1 || cd['passengerConfirmed'] == true;
                _tripStarterA = cd['trip_starter_a'] == 1 || cd['tripStarterA'] == true;
                _tripStarterB = cd['trip_starter_b'] == 1 || cd['tripStarterB'] == true;
                _tripEnderA = cd['trip_ender_a'] == 1 || cd['tripEnderA'] == true;
                _tripEnderB = cd['trip_ender_b'] == 1 || cd['tripEnderB'] == true;
                _hasActiveTrip = sState != 'idle' && sState != 'cancelled' && sState != 'completed';
                if (cd['origin'] != null && cd['origin'].toString().isNotEmpty) {
                  _originName = cd['origin'].toString();
                }
                if (cd['destination'] != null && cd['destination'].toString().isNotEmpty) {
                  _destinationName = cd['destination'].toString();
                }
                if (cd['fare'] != null && (cd['fare'] as num) > 0) {
                  _rideFare = (cd['fare'] as num).toDouble();
                }
                if (cd['trip_started_at'] != null) {
                  _rideStartTime = DateTime.tryParse(cd['trip_started_at'].toString());
                }
              });
              if (_sessionStatus == 'inProgress' || _sessionStatus == 'in_progress') {
                _startProgressTimer();
                _startProximityPing();
              }
            }
          }
        } catch (_) {}
      }

      final res = await dio.get('$_apiBase/rides/$targetId/session-status');
      if (res.statusCode == 200 && res.data is Map) {
        final d = Map<String, dynamic>.from(res.data as Map);
        final hasActive = d['hasActiveTrip'] == true ||
            (d['status'] != null && d['status'] != 'none' && d['origin'] != null && d['origin'].toString().isNotEmpty && d['fare'] != null && (d['fare'] as num) > 0);
        if (mounted) {
          setState(() {
            if (_sessionStatus == 'idle' || _sessionStatus == 'none') {
              _hasActiveTrip = hasActive;
              _sessionStatus = d['status']?.toString() ?? (hasActive ? 'pending' : 'none');
            }
            if (!_riderConfirmed) _riderConfirmed = d['riderConfirmed'] == true;
            if (!_passengerConfirmed) _passengerConfirmed = d['passengerConfirmed'] == true;
            if (_originName.isEmpty || _originName == 'DIU Campus') _originName = d['origin']?.toString() ?? (hasActive ? _originName : '');
            if (_destinationName.isEmpty || _destinationName == 'Destination') _destinationName = d['destination']?.toString() ?? (hasActive ? _destinationName : '');
            if (_rideFare <= 0) _rideFare = (d['fare'] as num?)?.toDouble() ?? (hasActive ? _rideFare : 0.0);
            _cancelReason = d['cancelReason']?.toString() ?? _cancelReason;
            _totalDurationMinutes = (d['totalDurationMinutes'] as num?)?.toDouble() ?? 0.0;
            if (d['startTime'] != null && _rideStartTime == null) {
              _rideStartTime = DateTime.tryParse(d['startTime'].toString());
            }
            final myUser = ref.read(authNotifierProvider).user;
            final myUserId = myUser?.id ?? '';
            final isDriver = (d['driverId'] != null && d['driverId'].toString() == myUserId) ||
                (myUser?.isBiker == true && widget.peerRole == 'Passenger');
            if (isDriver) {
              final pPhone = d['passengerPhone'] ?? d['passenger_phone'];
              if (pPhone != null && pPhone.toString().isNotEmpty) {
                _resolvedPeerPhone = pPhone.toString();
              }
            } else {
              final dPhone = d['driverPhone'] ?? d['driver_phone'];
              if (dPhone != null && dPhone.toString().isNotEmpty) {
                _resolvedPeerPhone = dPhone.toString();
              }
            }
            if (_resolvedPeerPhone == null) {
              if (d['passengerPhone'] != null && d['passengerPhone'].toString().isNotEmpty) {
                _resolvedPeerPhone = d['passengerPhone'].toString();
              } else if (d['driverPhone'] != null && d['driverPhone'].toString().isNotEmpty) {
                _resolvedPeerPhone = d['driverPhone'].toString();
              }
            }
          });
          if (_sessionStatus == 'in_progress') {
            _startProgressTimer();
          }
        }
      }

      // Fetch peer profile to get proper verified name, student ID, department and phone
      final currentUid = ref.read(authNotifierProvider).user?.id ?? '';
      targetPeerId = widget.peerId ?? '';
      if (targetPeerId.isEmpty && widget.rideId.startsWith('peer_dm_')) {
        final pairIds = widget.rideId.replaceFirst('peer_dm_', '').split('__');
        targetPeerId = pairIds.firstWhere((id) => id != currentUid, orElse: () => '');
      }
      if (targetPeerId.isNotEmpty) {
        try {
          final uRes = await dio.get('$_apiBase/users/$targetPeerId');
          if (uRes.statusCode == 200 && uRes.data is Map) {
            final uData = Map<String, dynamic>.from(uRes.data as Map);
            if (mounted) {
              setState(() {
                if (uData['name'] != null && uData['name'].toString().isNotEmpty && !uData['name'].toString().startsWith('usr_')) {
                  _resolvedPeerName = uData['name'].toString();
                }
                if (uData['phone'] != null && uData['phone'].toString().isNotEmpty) {
                  _resolvedPeerPhone = uData['phone'].toString();
                }
                if (uData['studentId'] != null || uData['student_id'] != null) {
                  _resolvedStudentId = (uData['studentId'] ?? uData['student_id']).toString();
                }
                if (uData['department'] != null) {
                  _resolvedDept = uData['department'].toString();
                }
                if (uData['email'] != null) {
                  _resolvedEmail = uData['email'].toString();
                }
              });
            }
          }
        } catch (_) {}
      }

      // Also try fetching ride details to get driverPhone if missing
      if (_resolvedPeerPhone == null && widget.peerPhone == null) {
        try {
          final rRes = await dio.get('$_apiBase/rides/$baseRideId');
          if (rRes.statusCode == 200 && rRes.data is Map) {
            final rData = Map<String, dynamic>.from(rRes.data as Map);
            final phone = rData['driverPhone'] ?? rData['driver_phone'];
            if (mounted && phone != null && phone.toString().isNotEmpty) {
              setState(() {
                _resolvedPeerPhone = phone.toString();
              });
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasActiveTrip = false);
      }
    }
  }

  void _listenWebSocketSession() {
    final wsClient = ref.read(webSocketClientProvider);
    _wsSessionSub?.cancel();
    _wsSessionSub = wsClient.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : msg;

      // Handle chat session state machine transitions
      if (event == 'chat_session_state_changed' &&
          (data['conversationId'] == effectiveChatId || data['conversationId'] == widget.rideId || data['conversationId'] == baseRideId)) {
        if (!mounted) return;
        final sState = data['sessionState']?.toString() ?? 'idle';
        setState(() {
          _sessionStatus = sState;
          if (data.containsKey('riderConfirmed')) _riderConfirmed = data['riderConfirmed'] == true;
          if (data.containsKey('passengerConfirmed')) _passengerConfirmed = data['passengerConfirmed'] == true;
          if (data.containsKey('tripStarterA')) _tripStarterA = data['tripStarterA'] == true;
          if (data.containsKey('tripStarterB')) _tripStarterB = data['tripStarterB'] == true;
          if (data.containsKey('tripEnderA')) _tripEnderA = data['tripEnderA'] == true;
          if (data.containsKey('tripEnderB')) _tripEnderB = data['tripEnderB'] == true;
          _hasActiveTrip = sState != 'idle' && sState != 'cancelled' && sState != 'completed';
          if (data['tripStartedAt'] != null) {
            _rideStartTime = DateTime.tryParse(data['tripStartedAt'].toString());
          }
          if (data.containsKey('cancelReason')) {
            _cancelReason = data['cancelReason']?.toString() ?? '';
          }
        });

        if (sState == 'inProgress' || sState == 'in_progress') {
          _startProgressTimer();
          _startProximityPing();
        } else if (sState == 'completed' || sState == 'cancelled') {
          _rideProgressTimer?.cancel();
          _proximityTimer?.cancel();
        }

        ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
        _scrollToBottom();
      }

      // Handle GPS Separation Alert (Separated for 2 mins during ride)
      if (event == 'trip_diverge_alert' &&
          (data['conversationId'] == effectiveChatId || data['conversationId'] == widget.rideId)) {
        _showDivergeAlertDialog(data);
      }
      final evRideId = (data['rideId'] ?? data['ride_id'])?.toString();
      final evChatId = (data['chatId'] ?? data['chat_id'])?.toString();
      final evBaseRideId = (data['baseRideId'] ?? data['base_ride_id'])?.toString();
      final isMatchingSession = evRideId == widget.rideId ||
          evRideId == baseRideId ||
          evRideId == effectiveChatId ||
          (widget.sourcePostId != null && evRideId == widget.sourcePostId) ||
          evChatId == effectiveChatId ||
          evChatId == widget.rideId ||
          evBaseRideId == baseRideId ||
          evBaseRideId == widget.rideId;

      if (event == 'ride_session_status_changed' && isMatchingSession) {
        if (!mounted) return;
        setState(() {
          _sessionStatus = data['status']?.toString() ?? _sessionStatus;
          if (data.containsKey('riderConfirmed')) {
            _riderConfirmed = data['riderConfirmed'] == true;
          }
          if (data.containsKey('passengerConfirmed')) {
            _passengerConfirmed = data['passengerConfirmed'] == true;
          }
          if (data.containsKey('cancelReason')) {
            _cancelReason = data['cancelReason']?.toString() ?? '';
          }
          if (data.containsKey('totalDurationMinutes')) {
            _totalDurationMinutes = (data['totalDurationMinutes'] as num?)?.toDouble() ?? _totalDurationMinutes;
          }
          if (data['startTime'] != null) {
            _rideStartTime = DateTime.tryParse(data['startTime'].toString());
          }
        });

        if (_sessionStatus == 'in_progress') {
          _startProgressTimer();
        } else {
          _rideProgressTimer?.cancel();
        }

        ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
        _scrollToBottom();
      } else if (event == 'ride_acceptance_prompt' && isMatchingSession) {
        if (!mounted) return;
        NotificationSoundService.playMessageChime();
        _loadSessionStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? '🔔 Peer has accepted! Please accept to confirm.'),
            backgroundColor: const Color(0xFF0284C7),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Accept',
              textColor: Colors.white,
              onPressed: _confirmRideSession,
            ),
          ),
        );
      } else if ((event == 'typing_status' || event == 'typing') && 
                 (data['rideId'] == effectiveChatId || (data['rideId'] == widget.rideId && data['userId'] == widget.peerId))) {
        final currentUserId = ref.read(authNotifierProvider).user?.id;
        final senderId = data['userId']?.toString();
        if (senderId != null && senderId != currentUserId) {
          final isTyping = data['isTyping'] == true;
          if (mounted) {
            setState(() => _isPeerTyping = isTyping);
            _typingTimer?.cancel();
            if (isTyping) {
              _typingTimer = Timer(const Duration(seconds: 4), () {
                if (mounted) setState(() => _isPeerTyping = false);
              });
            }
          }
        }
      } else if (event == 'location_shared' || event == 'driver_location_update') {
        final targetRideId = (data['ride_id'] ?? data['rideId'] ?? '').toString();
        final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
        final senderId = (data['userId'] ?? data['driverId'] ?? '').toString();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final role = (data['role'] ?? '').toString().toLowerCase();

        if (lat != null && lng != null &&
            (targetRideId == effectiveChatId ||
             targetRideId == widget.rideId ||
             targetRideId == baseRideId ||
             senderId == widget.peerId ||
             senderId == currentUserId)) {
          final pos = LatLng(lat, lng);
          if (role.contains('driver') || role.contains('rider') || senderId == widget.peerId) {
            _updateRiderLiveLocation(pos);
          } else {
            _updatePassengerLiveLocation(pos);
          }
          ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
        }
      } else if (event == 'new_message' || event == 'chat_message' || event == 'message_received') {
        final targetRideId = (data['ride_id'] ?? data['rideId'] ?? '').toString();
        final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
        final senderId = (data['sender_id'] ?? data['senderId'] ?? '').toString();
        if (targetRideId == effectiveChatId ||
            targetRideId == widget.rideId ||
            targetRideId == baseRideId ||
            (targetRideId.startsWith('peer_dm_') && widget.peerId != null && targetRideId.contains(widget.peerId!))) {
          if (!mounted) return;
          if (senderId != currentUserId) {
            NotificationSoundService.playMessageChime();
          }
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _loadSharedLocationsAndComputeRoute() async {
    // 1. Resolve Destination LatLng
    _destLocation = LocationSearchService.lookupCoordinates(_destinationName);

    // 2. Default origin/pickup LatLng
    final originPos = LocationSearchService.lookupCoordinates(_originName);
    _passengerLocation ??= originPos;
    _riderLocation ??= const LatLng(23.8775, 90.3201); // DIU Central Gate 1

    // 3. Query backend shared locations
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final apiBase = AppConfig.current.apiBaseUrl;
      
      final res = await dio.get('$apiBase/rides/$effectiveChatId/shared-locations');
      if (res.statusCode == 200 && res.data is List && (res.data as List).isNotEmpty) {
        final list = (res.data as List);
        for (final item in list) {
          if (item is Map) {
            final lat = (item['latitude'] as num?)?.toDouble();
            final lng = (item['longitude'] as num?)?.toDouble();
            final role = (item['role'] ?? '').toString().toLowerCase();
            final uId = item['userId']?.toString();
            if (lat != null && lng != null) {
              if (role.contains('driver') || role.contains('rider') || uId == widget.peerId) {
                _riderLocation = LatLng(lat, lng);
              } else {
                _passengerLocation = LatLng(lat, lng);
              }
            }
          }
        }
      }
    } catch (_) {}

    // 4. Also check recent messages in chatState for location shares
    final msgs = ref.read(chatNotifierProvider(effectiveChatId)).messages;
    for (final m in msgs.reversed) {
      if (m.isLocationShare && m.sharedLat != null && m.sharedLng != null) {
        final pos = LatLng(m.sharedLat!, m.sharedLng!);
        if (m.isMe) {
          final isRider = (widget.peerRole ?? '').toLowerCase().contains('passenger');
          if (isRider) {
            _riderLocation ??= pos;
          } else {
            _passengerLocation ??= pos;
          }
        } else {
          final peerIsRider = !(widget.peerRole ?? '').toLowerCase().contains('passenger');
          if (peerIsRider) {
            _riderLocation ??= pos;
          } else {
            _passengerLocation ??= pos;
          }
        }
      }
    }

    if (mounted) {
      _recalculateLiveDistanceAndRoute();
    }
  }

  void _updateRiderLiveLocation(LatLng pos) {
    if (!mounted) return;
    setState(() {
      _riderLocation = pos;
    });
    _recalculateLiveDistanceAndRoute();
  }

  void _updatePassengerLiveLocation(LatLng pos) {
    if (!mounted) return;
    setState(() {
      _passengerLocation = pos;
    });
    _recalculateLiveDistanceAndRoute();
  }

  Future<void> _recalculateLiveDistanceAndRoute() async {
    final rider = _riderLocation ?? const LatLng(23.8775, 90.3201);
    final pass = _passengerLocation ?? const LatLng(23.8765, 90.3204);
    final dest = _destLocation ?? LocationSearchService.lookupCoordinates(_destinationName);

    // Initial straight-line calculation for instant UI feedback
    final dLat = (rider.latitude - pass.latitude).abs() * 111.0;
    final dLng = (rider.longitude - pass.longitude).abs() * 105.0;
    final distKm = math.sqrt(dLat * dLat + dLng * dLng);

    if (mounted) {
      setState(() {
        _riderToPassengerDistanceKm = distKm;
        _riderToPassengerEtaMins = (distKm / 0.4).clamp(1, 45).round(); // ~25 km/h campus speed
      });
    }

    try {
      final routeOrigin = rider;
      final routeTarget = (_sessionStatus == 'in_progress') ? dest : pass;
      final route = await LocationSearchService.getRoute(routeOrigin, routeTarget);
      if (mounted && route.polylinePoints.isNotEmpty) {
        setState(() {
          _liveRoutePoints = route.polylinePoints;
          _riderToPassengerDistanceKm = route.distanceKm;
          _riderToPassengerEtaMins = route.durationMinutes;
        });
      }
    } catch (_) {}
  }

  void _openLiveCommuteMapModal() {
    HapticFeedback.mediumImpact();
    final riderPos = _riderLocation ?? const LatLng(23.8775, 90.3201);
    final passPos = _passengerLocation ?? const LatLng(23.8765, 90.3204);
    final destPos = _destLocation ?? LocationSearchService.lookupCoordinates(_destinationName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final markers = <Marker>{
              Marker(
                markerId: const MarkerId('live_rider_marker'),
                position: riderPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                infoWindow: InfoWindow(
                  title: '🏍️ ${widget.driverName} (Biker)',
                  snippet: _sessionStatus == 'in_progress' ? 'Traveling together' : 'Approaching pickup spot',
                ),
              ),
              Marker(
                markerId: const MarkerId('live_pass_marker'),
                position: passPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(
                  title: '🙋‍♂️ Passenger (Pickup)',
                  snippet: 'Boarding spot: $_originName',
                ),
              ),
              Marker(
                markerId: const MarkerId('live_dest_marker'),
                position: destPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(
                  title: '🏁 Destination Dropoff',
                  snippet: _destinationName,
                ),
              ),
            };

            final polylines = <Polyline>{};
            if (_liveRoutePoints.isNotEmpty) {
              polylines.add(
                Polyline(
                  polylineId: const PolylineId('live_commute_route_casing'),
                  points: _liveRoutePoints,
                  color: const Color(0xFFB23B00),
                  width: 7,
                ),
              );
              polylines.add(
                Polyline(
                  polylineId: const PolylineId('live_commute_route_line'),
                  points: _liveRoutePoints,
                  color: const Color(0xFFFF6D00),
                  width: 5,
                ),
              );
            }

            final isInTrip = _sessionStatus == 'in_progress';

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Top Drag Handle & Title Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isInTrip ? '🟢 Live Ride In Progress' : '🏍️ Live Rider GPS Radar',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      isInTrip
                                          ? 'En route together towards $_destinationName'
                                          : 'Tracking ${widget.driverName} • ${_riderToPassengerDistanceKm > 0 ? '${_riderToPassengerDistanceKm.toStringAsFixed(1)} km away (~$_riderToPassengerEtaMins mins)' : 'Approaching'}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                              onPressed: () => Navigator.pop(modalCtx),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Interactive GoogleMap Area
                  Expanded(
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: passPos,
                            zoom: 14.5,
                          ),
                          markers: markers,
                          polylines: polylines,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          onMapCreated: (ctrl) {
                            final minLat = math.min(riderPos.latitude, math.min(passPos.latitude, destPos.latitude));
                            final maxLat = math.max(riderPos.latitude, math.max(passPos.latitude, destPos.latitude));
                            final minLng = math.min(riderPos.longitude, math.min(passPos.longitude, destPos.longitude));
                            final maxLng = math.max(riderPos.longitude, math.max(passPos.longitude, destPos.longitude));
                            ctrl.animateCamera(
                              CameraUpdate.newLatLngBounds(
                                LatLngBounds(
                                  southwest: LatLng(minLat - 0.003, minLng - 0.003),
                                  northeast: LatLng(maxLat + 0.003, maxLng + 0.003),
                                ),
                                50,
                              ),
                            );
                          },
                        ),

                        // Top Floating Radar Info Card
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isInTrip
                                        ? 'Travelling Together ➔ $_destinationName'
                                        : '${widget.driverName} is coming (${_riderToPassengerDistanceKm.toStringAsFixed(1)} km • ~$_riderToPassengerEtaMins mins)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '৳${_rideFare.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Action Strip
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _shareLocation();
                              setModalState(() {});
                            },
                            icon: const Icon(Icons.satellite_alt_rounded, size: 16),
                            label: const Text('Broadcast My GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE65100),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            DirectCallService.showCallOptions(
                              context,
                              phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                              peerName: widget.displayName,
                              peerRole: widget.peerRole ?? 'Ride Companion',
                            );
                          },
                          icon: const Icon(Icons.call, size: 16),
                          label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }



  Future<void> _recordGpsBreadcrumb() async {
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus' || baseRideId.isEmpty) return;
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      if (pos == null) return;
      final user = ref.read(authNotifierProvider).user;
      final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      await dio.post('$_apiBase/rides/$baseRideId/record-gps', data: {
        'user_id': user?.id ?? 'usr_peer',
        'role': role,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
    } catch (_) {}
  }

  void _startProgressTimer() {
    _rideProgressTimer?.cancel();
    if (_rideStartTime != null) {
      _rideElapsedSeconds = DateTime.now().difference(_rideStartTime!).inSeconds;
      if (_rideElapsedSeconds < 0) _rideElapsedSeconds = 0;
    }
    _recordGpsBreadcrumb();
    _rideProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _rideElapsedSeconds++;
      });
      if (_rideElapsedSeconds % 15 == 0) {
        _recordGpsBreadcrumb();
      }
    });
  }

  void _startProximityPing() {
    _proximityTimer?.cancel();
    _proximityTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || (_sessionStatus != 'inProgress' && _sessionStatus != 'in_progress')) {
        _proximityTimer?.cancel();
        return;
      }
      try {
        final pos = await GpsLocationService.getCurrentLocation();
        if (pos != null) {
          final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
          final user = ref.read(authNotifierProvider).user;
          await dio.post('$_apiBase/chat/session/proximity-ping', data: {
            'conversationId': effectiveChatId,
            'userId': user?.id ?? '',
            'userName': user?.name ?? 'Student',
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          });
        }
      } catch (_) {}
    });
  }

  void _showDivergeAlertDialog(Map<String, dynamic> data) {
    if (!mounted) return;
    NotificationSoundService.playMessageChime();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Are you end the ride?'),
          ],
        ),
        content: const Text(
          'You and your companion are not in the same location for the last 2 minutes. Did you arrive at your destination?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Still on Ride'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _completeRideSession();
            },
            child: const Text('Yes, End Trip'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';
    setState(() {
      _isLoadingSession = true;
      if (role == 'rider') {
        _riderConfirmed = true;
      } else {
        _passengerConfirmed = true;
      }
    });
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/chat/session/confirm', data: {
        'conversationId': effectiveChatId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
        'role': role,
      });
      // Also sync legacy session endpoint for backwards compatibility
      try {
        await dio.post('$_apiBase/rides/confirm-session', data: {
          'rideId': widget.rideId,
          'baseRideId': baseRideId,
          'chatId': effectiveChatId,
          'userId': user?.id ?? '',
          'userName': user?.name ?? 'Student',
          'role': role,
          'latitude': pos?.latitude ?? 23.8765,
          'longitude': pos?.longitude ?? 90.3204,
        });
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ You agreed & accepted this ride!'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accepted locally. (Sync: $e)'), backgroundColor: const Color(0xFF10B981)),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Future<void> _startRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    setState(() => _isLoadingSession = true);
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final lat = pos?.latitude ?? 23.8765;
      final lng = pos?.longitude ?? 90.3204;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/chat/session/start', data: {
        'conversationId': effectiveChatId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
      });
      try {
        await dio.post('$_apiBase/rides/$baseRideId/start', data: {
          'latitude': lat,
          'longitude': lng,
        });
      } catch (_) {}

      ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(
        '🚀 [Trip Started] ${user?.name ?? "Rider"} started the ride! Live GPS tracking is active.',
        receiverId: widget.peerId,
      );

      if (mounted) {
        setState(() {
          _sessionStatus = 'in_progress';
          _rideStartTime = DateTime.now();
        });
        _startProgressTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 Trip started! Live timer and GPS active.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start trip: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  void _showCancelTripDialog() {
    final reasons = [
      'Fare not agreed / ভাড়া বনিবনা হয়নি',
      'Peer not responding / মেসেজ বা কলে উত্তর নেই',
      'Change of travel plans / ভ্রমণ পরিকল্পনা পরিবর্তন',
      'Vehicle or location mismatch / স্থান বা বাহন মিলছে না',
      'Other / অন্যান্য',
    ];
    String selected = reasons[0];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Cancel / Close Trip',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'If contact or fare is not agreed, cancel this trip now. Both parties will be notified and the ride will not be confirmed.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                title: Text(r, style: const TextStyle(fontSize: 13.5)),
                value: r,
                groupValue: selected,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
                onChanged: (val) {
                  if (val != null) setModalState(() => selected = val);
                },
              )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancelRideSession(selected);
                  },
                  child: const Text('Confirm Cancel Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRideSession(String reason) async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';
    setState(() {
      _isLoadingSession = true;
      _sessionStatus = 'cancelled';
      _cancelReason = reason;
      _riderConfirmed = false;
      _passengerConfirmed = false;
    });
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/chat/session/cancel', data: {
        'conversationId': effectiveChatId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
        'reason': reason,
      });
      try {
        await dio.post('$_apiBase/rides/cancel-session', data: {
          'rideId': widget.rideId,
          'baseRideId': baseRideId,
          'chatId': effectiveChatId,
          'userId': user?.id ?? '',
          'userName': user?.name ?? 'Student',
          'role': role,
          'reason': reason,
        });
      } catch (_) {}

      ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(
        '❌ [Deal Cancelled] Trip deal was cancelled by ${user?.name ?? "Student"}. Reason: $reason',
        receiverId: widget.peerId,
      );

      // Invalidate bookings and ride providers so home screen updates immediately
      ref.invalidate(myBookingsProvider);
      ref.invalidate(allAvailableRidesProvider);
      ref.invalidate(myPostedRidesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip deal cancelled: $reason'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip deal closed: $reason'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Future<void> _completeRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Complete Trip?'),
          ],
        ),
        content: const Text(
          'Have you arrived safely at your destination? Marking this trip complete will record the arrival time, calculate total duration, and save the ride record to the database.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not Yet')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Arrived & Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoadingSession = true);
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/chat/session/end', data: {
        'conversationId': effectiveChatId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
      });
      try {
        await dio.post('$_apiBase/rides/complete-session', data: {
          'rideId': widget.rideId,
          'baseRideId': baseRideId,
          'chatId': effectiveChatId,
          'userId': user?.id ?? '',
          'userName': user?.name ?? 'Student',
          'role': role,
          'latitude': pos?.latitude ?? 23.8765,
          'longitude': pos?.longitude ?? 90.3204,
        });
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sessionStatus = 'completed';
      });
      ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🏁 Trip marked as completed! Record saved to database.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionStatus = 'completed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip marked as complete locally.'), backgroundColor: Color(0xFF10B981)),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Widget _buildRideSessionControlBar() {
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus') {
      return const SizedBox();
    }

    final isInProgress = _sessionStatus == 'inProgress' || _sessionStatus == 'in_progress';
    final isBothConfirmed = _sessionStatus == 'bothConfirmed' || (_riderConfirmed && _passengerConfirmed);
    final isCompleted = _sessionStatus == 'completed';
    final isCancelled = _sessionStatus == 'cancelled';
    final isIdle = _sessionStatus == 'idle' || _sessionStatus == 'none';

    // If completely idle with no active post or trip, do not show clutter
    if (isIdle && !_hasActiveTrip && widget.sourcePostId == null && (widget.chatContext == null || widget.chatContext == 'peer')) {
      return const SizedBox();
    }

    final isCurrentRider = (widget.peerRole?.toLowerCase() == 'passenger');
    final iConfirmed = isCurrentRider ? _riderConfirmed : _passengerConfirmed;
    final peerConfirmed = isCurrentRider ? _passengerConfirmed : _riderConfirmed;

    final myUid = ref.read(authNotifierProvider).user?.id.toLowerCase() ?? '';
    final pairParts = effectiveChatId.replaceFirst('peer_dm_', '').split('__');
    final isUserA = pairParts.isNotEmpty && myUid == pairParts[0];
    final iStarted = isUserA ? _tripStarterA : _tripStarterB;
    final peerStarted = isUserA ? _tripStarterB : _tripStarterA;
    final iEnded = isUserA ? _tripEnderA : _tripEnderB;
    final peerEnded = isUserA ? _tripEnderB : _tripEnderA;

    final minutes = (_rideElapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_rideElapsedSeconds % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isInProgress
              ? const Color(0xFF10B981)
              : (isBothConfirmed ? const Color(0xFF0284C7) : const Color(0xFFFF9800).withOpacity(0.5)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row: Route + Fare + Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isInProgress
                      ? const Color(0xFFECFDF5)
                      : (isBothConfirmed ? const Color(0xFFF0F9FF) : const Color(0xFFFFF8E1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isInProgress
                      ? Icons.directions_bike
                      : (isBothConfirmed ? Icons.verified : Icons.handshake_outlined),
                  size: 18,
                  color: isInProgress
                      ? const Color(0xFF047857)
                      : (isBothConfirmed ? const Color(0xFF0284C7) : const Color(0xFFE65100)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_originName ➔ $_destinationName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isInProgress
                          ? 'Trip in Progress ($minutes:$seconds) • GPS Live'
                          : (isBothConfirmed
                              ? 'Ride Confirmed • Ready for Commute'
                              : (isCompleted
                                  ? 'Ride Completed & Recorded'
                                  : (isCancelled
                                      ? 'Cancelled: $_cancelReason'
                                      : 'Communicate & Agree to Ride'))),
                      style: TextStyle(
                        fontSize: 11,
                        color: isInProgress
                            ? const Color(0xFF059669)
                            : (isBothConfirmed ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '৳${_rideFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _openLiveCommuteMapModal,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar_rounded, size: 13, color: Color(0xFF0284C7)),
                      SizedBox(width: 3),
                      Text('Radar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Deal Closed Banner (if cancelled)
          if (isCancelled) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DEAL CLOSED: ${_cancelReason.isNotEmpty ? _cancelReason : "This ride deal was cancelled."}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isCompleted && baseRideId != 'campus_community' && baseRideId != 'support_campus') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final url = 'https://servertest.eu.cc/ride/api/rides/$baseRideId/route-passport-pdf';
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            '📄 View Commute Route PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Minimal & Clean Interactive Trip Action Buttons
          if (!isCompleted && !isCancelled) ...[
            const SizedBox(height: 8),
            if (!isInProgress) ...[
              if (!isBothConfirmed) ...[
                if (peerConfirmed && !iConfirmed) ...[
                  // 1A. Peer has accepted! Prompt current user
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF93C5FD), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: Color(0xFF2563EB), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '🔔 ${widget.displayName} accepted! Tap to confirm.',
                            style: const TextStyle(
                              color: Color(0xFF1E40AF),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton(
                            onPressed: _isLoadingSession ? null : _confirmRideSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(
                              _isLoadingSession ? '…' : '✓ Confirm',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 28,
                          child: OutlinedButton(
                            onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('✕', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (iConfirmed && !peerConfirmed) ...[
                  // 1B. I have confirmed, waiting for peer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFF16A34A), size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '✓ You accepted • Waiting for ${widget.displayName}…',
                            style: const TextStyle(color: Color(0xFF166534), fontSize: 11, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          height: 26,
                          child: TextButton(
                            onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 1C. Neither has confirmed yet -> Minimal buttons
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 32,
                          child: ElevatedButton.icon(
                            onPressed: _isLoadingSession ? null : _confirmRideSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.check_circle_outline, size: 14),
                            label: Text(
                              _isLoadingSession ? 'Saving…' : 'Confirm Ride',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.close, size: 13),
                          label: const Text('Decline', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                // State 2: Both Confirmed -> Start Trip Option (Requires BOTH users to tap Start)
                if (iStarted && !peerStarted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFF16A34A), size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '✓ You tapped Start • Waiting for ${widget.displayName}…',
                            style: const TextStyle(color: Color(0xFF166534), fontSize: 11, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          height: 26,
                          child: TextButton(
                            onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (peerStarted && !iStarted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF93C5FD), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF2563EB), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '🚀 ${widget.displayName} is ready & tapped Start! Tap to begin.',
                            style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.bold, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton(
                            onPressed: _isLoadingSession ? null : _startRideSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(_isLoadingSession ? '…' : 'Start Trip', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ElevatedButton.icon(
                            onPressed: _isLoadingSession ? null : _startRideSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(
                              _isLoadingSession ? 'Starting…' : 'Start Trip (Both Tap When Ready)',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton(
                          onPressed: _showCancelTripDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ] else ...[
              // State 3: Trip In Progress -> End Trip (Requires BOTH users to confirm End)
              if (iEnded && !peerEnded) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '✓ You ended trip • Waiting for ${widget.displayName} to confirm…',
                          style: const TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (peerEnded && !iEnded) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_rounded, color: Color(0xFF2563EB), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '🏁 ${widget.displayName} ended trip! Tap End Trip to confirm completion.',
                          style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.bold, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 28,
                        child: ElevatedButton(
                          onPressed: _isLoadingSession ? null : _completeRideSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(_isLoadingSession ? '…' : 'End Trip', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingSession ? null : _completeRideSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.flag_rounded, size: 16),
                          label: Text(
                            _isLoadingSession ? 'Ending…' : 'End Trip (Arrived Safely)',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: _openLiveCommuteMapModal,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 14),
                        label: const Text('Map', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton(
                        onPressed: _showCancelTripDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }



  void _showNormalChatOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                  child: Text(
                    widget.displayName.isNotEmpty ? widget.displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        '${widget.peerRole ?? "DIU Student"} • Direct Campus Peer',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.call_rounded, color: Color(0xFF16A34A)),
              title: const Text('Direct Call', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                _resolvedPeerPhone?.isNotEmpty == true
                    ? _resolvedPeerPhone!
                    : (widget.peerPhone?.isNotEmpty == true ? widget.peerPhone! : 'Call companion via mobile carrier'),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                DirectCallService.showCallOptions(
                  context,
                  phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                  peerName: widget.displayName,
                  peerRole: widget.peerRole ?? 'Companion',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_rounded, color: Color(0xFFFF9800)),
              title: const Text('Attention Buzzer Ring', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Sound dedicated chime on their phone', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _triggerAlertRing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.my_location_rounded, color: Color(0xFF0284C7)),
              title: const Text('Share Live Location Pin', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Send real-time campus GPS coordinates', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _shareLocation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_city_rounded, color: Color(0xFFE65100)),
              title: const Text('Send Campus Landmark', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Gate 1, AB-4, Cafeteria, Knowledge Tower', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showCampusLandmarkPicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTripManagementSheet() {
    if (!_hasActiveTrip || _sessionStatus == 'none' || _rideFare <= 0) {
      _showNormalChatOptionsSheet();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isInProgress = _sessionStatus == 'in_progress';
        final isCompleted = _sessionStatus == 'completed';
        final isCancelled = _sessionStatus == 'cancelled';
        final minutes = (_rideElapsedSeconds ~/ 60).toString().padLeft(2, '0');
        final seconds = (_rideElapsedSeconds % 60).toString().padLeft(2, '0');

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Trip Details & Controls',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isInProgress ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isInProgress ? 'ACTIVE ($minutes:$seconds)' : _sessionStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isInProgress ? const Color(0xFF16A34A) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_originName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(width: 2, height: 16, color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_destinationName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        Text('৳${_rideFare.toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatusPill(label: 'Driver Ready', isConfirmed: _riderConfirmed),
                  const SizedBox(width: 8),
                  _buildStatusPill(label: 'Passenger Ready', isConfirmed: _passengerConfirmed),
                ],
              ),
              const SizedBox(height: 14),
              if (!isCompleted && !isCancelled) ...[
                if (!isInProgress) ...[
                  if (!_riderConfirmed || !_passengerConfirmed) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF047857),
                        side: const BorderSide(color: Color(0xFF6EE7B7)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoadingSession
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _confirmRideSession();
                            },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Confirm Ride from My Side', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoadingSession
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _startRideSession();
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Commute (Driver on the way)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoadingSession
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _completeRideSession();
                          },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('End Trip (Arrived Safely)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shareLocation();
                        },
                        icon: const Icon(Icons.my_location, size: 15),
                        label: const Text('Share GPS', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCancelTripDialog();
                        },
                        icon: const Icon(Icons.close, size: 15),
                        label: const Text('Cancel Ride', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  isCompleted ? '✓ Ride completed safely and archived.' : '✕ Ride was cancelled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
                if (_cancelReason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Reason: $_cancelReason',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusPill({required String label, required bool isConfirmed}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isConfirmed ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed ? Icons.check_circle : Icons.schedule,
            size: 12,
            color: isConfirmed ? const Color(0xFF047857) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: isConfirmed ? const Color(0xFF047857) : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'send chat messages')) return;
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    _sendTypingEvent(false);
    ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(text, receiverId: widget.peerId);
    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _shareLocation() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'share GPS location')) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📡 Acquiring real-time GPS coordinates...'),
        duration: Duration(seconds: 1),
      ),
    );
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? 23.8765;
    final lng = pos?.longitude ?? 90.3204;
    if (!mounted) return;

    final currentPos = LatLng(lat, lng);
    final isRider = (widget.peerRole ?? '').toLowerCase().contains('passenger');
    if (isRider) {
      _updateRiderLiveLocation(currentPos);
    } else {
      _updatePassengerLiveLocation(currentPos);
    }

    // 1. Post to backend REST API to sync shared_locations and broadcast WebSocket
    try {
      final user = ref.read(authNotifierProvider).user;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final apiBase = AppConfig.current.apiBaseUrl;
      await dio.post('$apiBase/location/share', data: {
        'rideId': effectiveChatId,
        'userId': user?.id ?? 'usr_peer',
        'userName': user?.name ?? 'DIU Commuter',
        'role': isRider ? 'driver' : 'passenger',
        'latitude': lat,
        'longitude': lng,
      });
    } catch (_) {}

    // 2. Post as a location share message in chat
    ref.read(chatNotifierProvider(effectiveChatId).notifier).shareLocation(lat, lng, receiverId: widget.peerId);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider(effectiveChatId));
    final displayName = widget.displayName;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.8,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ((widget.peerRole ?? '').toLowerCase().contains('passenger')
                  ? const Color(0xFFE0F2FE)
                  : const Color(0xFFFFEDD5)),
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ((widget.peerRole ?? '').toLowerCase().contains('passenger')
                      ? const Color(0xFF0284C7)
                      : const Color(0xFFE65100)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          effectiveDisplayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                      if (_hasActiveTrip && ((widget.peerRole ?? '').toLowerCase().contains('passenger') || (widget.peerRole ?? '').toLowerCase().contains('rider') || (widget.peerRole ?? '').toLowerCase().contains('biker'))) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: ((widget.peerRole ?? '').toLowerCase().contains('passenger')
                                ? const Color(0xFF0284C7)
                                : const Color(0xFFE65100)).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: ((widget.peerRole ?? '').toLowerCase().contains('passenger')
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFFE65100)).withOpacity(0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            (widget.peerRole ?? '').toLowerCase().contains('passenger') ? '🎒 Passenger' : '🏍️ Rider',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: (widget.peerRole ?? '').toLowerCase().contains('passenger')
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _hasActiveTrip
                        ? '৳${_rideFare.toStringAsFixed(0)} • Active Commute'
                        : 'DIU Peer • Direct Message',
                    style: TextStyle(
                      color: _hasActiveTrip ? const Color(0xFFE65100) : const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: Color(0xFFE65100), size: 21),
            tooltip: 'Call $effectiveDisplayName',
            onPressed: () {
              final phone = effectivePhone;
              if (DirectCallService.isValidPhone(phone)) {
                DirectCallService.makeDirectPhoneCall(
                  context,
                  phoneNumber: phone,
                  peerName: effectiveDisplayName,
                );
              } else {
                DirectCallService.showCallOptions(
                  context,
                  phoneNumber: phone,
                  peerName: effectiveDisplayName,
                  peerRole: widget.peerRole ?? 'Ride Companion',
                );
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF475569), size: 22),
            tooltip: 'Student Info & Controls',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 10,
            onSelected: (value) {
              switch (value) {
                case 'student_info':
                  _showStudentProfileDialog(context);
                  break;
                case 'radar':
                  _openLiveCommuteMapModal();
                  break;
                case 'share_gps':
                  _shareLocation();
                  break;
                case 'alert_ring':
                  _triggerAlertRing();
                  break;
                case 'landmark':
                  _showCampusLandmarkPicker();
                  break;
                case 'call':
                  final phone = effectivePhone;
                  if (DirectCallService.isValidPhone(phone)) {
                    DirectCallService.makeDirectPhoneCall(
                      context,
                      phoneNumber: phone,
                      peerName: effectiveDisplayName,
                    );
                  } else {
                    DirectCallService.showCallOptions(
                      context,
                      phoneNumber: phone,
                      peerName: effectiveDisplayName,
                      peerRole: widget.peerRole ?? 'Ride Companion',
                    );
                  }
                  break;
                case 'trip_details':
                  _showTripManagementSheet();
                  break;
                case 'cancel_trip':
                  _showCancelTripDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              // 1. Prominent Student Verified Profile Card with Name & Phone Number
              PopupMenuItem<String>(
                value: 'student_info',
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          effectiveDisplayName.isNotEmpty ? effectiveDisplayName[0].toUpperCase() : 'S',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    effectiveDisplayName,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, color: Color(0xFF059669), size: 13),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              effectivePhone.isNotEmpty
                                  ? '📞 $effectivePhone'
                                  : (effectiveStudentId.isNotEmpty ? '🆔 $effectiveStudentId' : 'DIU Verified Student'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: effectivePhone.isNotEmpty ? const Color(0xFF059669) : const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),

              // 2. Direct Phone Call Action
              PopupMenuItem<String>(
                value: 'call',
                child: Row(
                  children: [
                    const Icon(Icons.phone_rounded, color: Color(0xFF059669), size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        effectivePhone.isNotEmpty ? 'Call $effectivePhone' : 'Call Student',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              if (_hasActiveTrip) ...[
                const PopupMenuItem(
                  value: 'radar',
                  child: Row(
                    children: [
                      Icon(Icons.radar_rounded, color: Color(0xFF0284C7), size: 19),
                      SizedBox(width: 10),
                      Text('Live Radar & Map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'trip_details',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 19),
                      SizedBox(width: 10),
                      Text('Trip Details & Controls', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'share_gps',
                child: Row(
                  children: [
                    Icon(Icons.my_location_rounded, color: Color(0xFF10B981), size: 19),
                    SizedBox(width: 10),
                    Text('Share Live GPS Location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'alert_ring',
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, color: Color(0xFFFF9800), size: 19),
                    SizedBox(width: 10),
                    Text('Send Attention Alert Ring', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'landmark',
                child: Row(
                  children: [
                    Icon(Icons.location_city_rounded, color: Color(0xFF6366F1), size: 19),
                    SizedBox(width: 10),
                    Text('Send Campus Landmark', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (_hasActiveTrip && _sessionStatus != 'completed' && _sessionStatus != 'cancelled') ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'cancel_trip',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 19),
                      SizedBox(width: 10),
                      Text('Cancel Commute', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          _buildSmartCommuteHeader(),
          // Messages list
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : chatState.messages.isEmpty
                    ? _buildEmptyChatIntroCard()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final msg = chatState.messages[index];
                          final showDateDivider = index == 0 ||
                              !_isSameDay(msg.timestamp, chatState.messages[index - 1].timestamp);

                          if (_isTripCompletedMessage(msg)) {
                            return Column(
                              children: [
                                if (showDateDivider) _buildDateDivider(msg.timestamp),
                                _buildTripCompletedBox(msg),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment:
                                msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (showDateDivider) _buildDateDivider(msg.timestamp),
                              Align(
                                alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: msg.isMe
                                        ? const LinearGradient(
                                            colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color: msg.isMe ? null : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(msg.isMe ? 18 : 3),
                                      bottomRight: Radius.circular(msg.isMe ? 3 : 18),
                                    ),
                                    border: msg.isMe ? null : Border.all(color: const Color(0xFFE5E7EB)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      if (msg.isLocationShare || msg.text.contains('google.com/maps') || msg.text.contains('maps.google.com') || msg.sharedLat != null) ...[
                                        _buildLocationCard(msg),
                                      ],
                                      if (!msg.isMe && msg.senderName.isNotEmpty) ...[
                                        Text(
                                          msg.senderName,
                                          style: AppTypography.labelSm.copyWith(
                                            color: const Color(0xFFE65100),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                      ],
                                      // Sender Mode Badge: Rider Mode / Passenger Mode / Campus Chat
                                      Builder(
                                        builder: (_) {
                                          final mMode = (msg.senderMode ?? '').toLowerCase();
                                          final isRiderM = mMode.contains('rider') || mMode.contains('biker') || mMode.contains('driver');
                                          final isPassM = mMode.contains('passenger');
                                          final tagText = isRiderM
                                              ? '🏍️ Rider Mode'
                                              : (isPassM ? '🎒 Passenger Mode' : '💬 Campus Chat');
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: msg.isMe
                                                  ? Colors.white.withOpacity(0.22)
                                                  : (isRiderM ? const Color(0xFFFFF8E1) : const Color(0xFFEFF6FF)),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: msg.isMe
                                                    ? Colors.white.withOpacity(0.35)
                                                    : (isRiderM ? const Color(0xFFFFB74D) : const Color(0xFF93C5FD)),
                                                width: 0.6,
                                              ),
                                            ),
                                            child: Text(
                                              tagText,
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                color: msg.isMe
                                                    ? Colors.white
                                                    : (isRiderM ? const Color(0xFFC2410C) : const Color(0xFF1D4ED8)),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      _buildClickableMessageText(msg),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            DateTimeUtils.formatTime(msg.timestamp),
                                            style: TextStyle(
                                              color: msg.isMe
                                                  ? Colors.white.withOpacity(0.85)
                                                  : const Color(0xFF9CA3AF),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (msg.isMe) ...[
                                            const SizedBox(width: 4),
                                            if (msg.deliveryStatus == MessageDeliveryStatus.failed)
                                              GestureDetector(
                                                onTap: () => ref
                                                    .read(chatNotifierProvider(effectiveChatId).notifier)
                                                    .retryMessage(msg.id),
                                                child: const Icon(Icons.error_outline, size: 14, color: Color(0xFFFFCDD2)),
                                              )
                                            else if (msg.deliveryStatus == MessageDeliveryStatus.sending)
                                              const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                                              )
                                            else
                                              Icon(
                                                msg.deliveryStatus == MessageDeliveryStatus.read || msg.isRead
                                                    ? Icons.done_all
                                                    : Icons.done,
                                                size: 14,
                                                color: msg.deliveryStatus == MessageDeliveryStatus.read || msg.isRead
                                                    ? const Color(0xFF81D4FA)
                                                    : Colors.white,
                                              ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Animated Peer Typing Indicator Bubble
          if (_isPeerTyping)
            Align(
              alignment: Alignment.centerLeft,
              child: _TypingBubbleIndicator(peerName: displayName),
            ),

          // Modern Elevated Message Box (Zero overlap, role-adapted, micro-interactions)
          _buildModernMessageBox(),
        ],
      ),
    );
  }

  Widget _buildSmartCommuteHeader() {
    if (_isPureChatMode || !_hasActiveTrip || _sessionStatus == 'none' || _rideFare <= 0 || _originName.isEmpty) {
      return const SizedBox.shrink();
    }
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus') {
      return const SizedBox.shrink();
    }

    return _buildRideSessionControlBar();
  }

  List<String> _getRoleQuickReplies() {
    final role = (widget.peerRole ?? '').toLowerCase();
    final isPeerPassenger = role.contains('passenger');
    final isPeerDriver = role.contains('driver') || role.contains('biker') || role.contains('rider');
    final appMode = ref.read(appModeProvider);

    if (appMode.isRider || isPeerPassenger) {
      // Current user is the Rider (Biker)
      return const [
        '🏍️ On my way!',
        '📍 Reached pickup spot',
        '🪖 Extra helmet ready',
        '⏱️ Reaching in 2 mins',
        '🚦 Stuck in Birulia traffic',
        '👋 Waiting near Gate 1',
        '✅ Trip completed, ride safe!',
      ];
    } else if (appMode.isPassenger || isPeerDriver) {
      // Current user is the Passenger
      return const [
        '📍 Waiting at Gate 1',
        '🏢 In front of AB-4 Building',
        '☕ Near Campus Cafeteria',
        '🪖 Do you have extra helmet?',
        '⏱️ Ready in 2 mins',
        '👋 I see your bike!',
        '📍 Sharing my live location',
        '🙏 Thanks for the safe ride!',
      ];
    } else {
      // Campus Friend / Peer
      return const [
        '👋 Hey, are you at campus?',
        '📍 Where are you right now?',
        '🏍️ Going to campus today?',
        '☕ Free for tea at cafeteria?',
        '👍 Sounds great, see you!',
      ];
    }
  }

  void _showCampusLandmarkPicker() {
    const landmarks = [
      '📍 DIU Gate 1 (Main Entrance & Canopy)',
      '🏢 Academic Building 4 (AB-4)',
      '☕ Central Campus Cafeteria',
      '📚 Knowledge Tower & Library Roundabout',
      '🏟️ Permanent Campus Playground & Pavilion',
      '🚌 Birulia Bus Stand & DIU Counter',
      '🌿 Green Garden Lake Side',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.location_on_rounded, color: Color(0xFFE65100), size: 20),
                SizedBox(width: 8),
                Text(
                  'Select DIU Campus Landmark',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...landmarks.map((spot) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              leading: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pin_drop_rounded, size: 18, color: Color(0xFFE65100)),
              ),
              title: Text(
                spot,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _messageController.text = spot;
                _sendMessage();
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showAttachmentActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFFE65100), size: 22),
                SizedBox(width: 8),
                Text(
                  'Quick Commute Utilities',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionMenuItem(
                  icon: Icons.my_location_rounded,
                  label: 'Share GPS',
                  color: const Color(0xFF0284C7),
                  bgColor: const Color(0xFFF0F9FF),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLocation();
                  },
                ),
                _buildActionMenuItem(
                  icon: Icons.location_city_rounded,
                  label: 'DIU Spot',
                  color: const Color(0xFFE65100),
                  bgColor: const Color(0xFFFFF8E1),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCampusLandmarkPicker();
                  },
                ),
                _buildActionMenuItem(
                  icon: Icons.notifications_active_rounded,
                  label: 'Buzzer',
                  color: const Color(0xFFFF9800),
                  bgColor: const Color(0xFFFFFBEB),
                  onTap: () {
                    Navigator.pop(ctx);
                    _triggerAlertRing();
                  },
                ),
                _buildActionMenuItem(
                  icon: Icons.phone_in_talk_rounded,
                  label: 'Call Direct',
                  color: const Color(0xFF16A34A),
                  bgColor: const Color(0xFFF0FDF4),
                  onTap: () {
                    Navigator.pop(ctx);
                    DirectCallService.showCallOptions(
                      context,
                      phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                      peerName: widget.displayName,
                      peerRole: widget.peerRole ?? 'Companion',
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.2), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernMessageBox() {
    final quickReplies = _getRoleQuickReplies();
    final hasText = _messageController.text.trim().isNotEmpty;
    final role = (widget.peerRole ?? '').toLowerCase();
    final isPeerPassenger = role.contains('passenger');
    final appMode = ref.read(appModeProvider);
    final isRider = appMode.isRider || isPeerPassenger;

    final hintText = isRider
        ? 'Message passenger (e.g. at Gate 1)...'
        : 'Message rider (e.g. near AB-4)...';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick Replies Bar with toggle
            if (_showQuickReplies) ...[
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: quickReplies.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final chip = quickReplies[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _messageController.text = chip;
                          _sendMessage();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withOpacity(0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            chip,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Input Row
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Action Tray Button (+)
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withOpacity(0.09),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE65100).withOpacity(0.2), width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.add_rounded, color: Color(0xFFE65100), size: 22),
                      padding: EdgeInsets.zero,
                      tooltip: 'Commute Utilities & GPS',
                      onPressed: _showAttachmentActionSheet,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Expandable Text Field Box
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          // Toggle Quick Chips button
                          IconButton(
                            icon: Icon(
                              _showQuickReplies ? Icons.bolt_rounded : Icons.bolt_outlined,
                              size: 18,
                              color: _showQuickReplies ? const Color(0xFFE65100) : const Color(0xFF94A3B8),
                            ),
                            tooltip: _showQuickReplies ? 'Hide Quick Replies' : 'Show Quick Replies',
                            padding: const EdgeInsets.only(right: 6, bottom: 8),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _showQuickReplies = !_showQuickReplies);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dynamic Send / Location Button
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(bottom: 1),
                    decoration: BoxDecoration(
                      gradient: hasText
                          ? const LinearGradient(
                              colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: hasText ? null : const Color(0xFFE2E8F0),
                      shape: BoxShape.circle,
                      boxShadow: hasText
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE65100).withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: IconButton(
                      icon: Icon(
                        hasText ? Icons.send_rounded : Icons.my_location_rounded,
                        color: hasText ? Colors.white : const Color(0xFF64748B),
                        size: 19,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: hasText ? 'Send Message' : 'Share Location',
                      onPressed: () {
                        if (hasText) {
                          _sendMessage();
                        } else {
                          _shareLocation();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isTripCompletedMessage(ChatMessage msg) {
    final lower = msg.text.toLowerCase();
    return lower.contains('trip completed') ||
           lower.contains('trip successfully completed') ||
           lower.contains('ride completed') ||
           lower.contains('[trip completed]');
  }

  Widget _buildTripCompletedBox(ChatMessage msg) {
    final timeStr = DateTimeUtils.formatTime(msg.timestamp);
    final text = msg.text
        .replaceAll('🏁', '')
        .replaceAll('[Trip Completed]', '')
        .trim();

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF16A34A).withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                const Text(
                  'TRIP COMPLETED',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Color(0xFF15803D),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 11, color: Color(0xFF16A34A)),
                      const SizedBox(width: 3),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                      height: 1.45,
                    ),
                  ),
                  if (msg.sharedLat != null && msg.sharedLng != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        final url = GpsLocationService.getGoogleMapsLocationUrl(msg.sharedLat!, msg.sharedLng!);
                        GpsLocationService.openGoogleMaps(url);
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'Open Destination in Google Maps',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF15803D),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final url = 'https://servertest.eu.cc/ride/api/rides/$baseRideId/route-passport-pdf';
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE65100).withOpacity(0.2),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 15),
                          SizedBox(width: 6),
                          Text(
                            'Download Commute Route Passport (PDF)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(ChatMessage msg) {
    double lat = msg.sharedLat ?? 23.8765;
    double lng = msg.sharedLng ?? 90.3204;
    if (msg.sharedLat == null || msg.sharedLng == null) {
      final match = RegExp(r'query=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(msg.text) ??
          RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})').firstMatch(msg.text);
      if (match != null) {
        lat = double.tryParse(match.group(1)!) ?? lat;
        lng = double.tryParse(match.group(2)!) ?? lng;
      }
    }

    final isMe = msg.isMe;
    final cardBg = isMe ? Colors.white.withOpacity(0.18) : Colors.white;
    final borderCol = isMe ? Colors.white38 : const Color(0xFFCBD5E1);
    final textCol = isMe ? Colors.white : const Color(0xFF0F172A);

    return InkWell(
      onTap: _openLiveCommuteMapModal,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderCol, width: 1),
          boxShadow: isMe ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Icon & Coordinates
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.white : const Color(0xFFE65100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_on,
                    size: 15,
                    color: isMe ? const Color(0xFFE65100) : Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe ? 'You Shared Live GPS' : '${msg.senderName} Shared Live GPS',
                        style: TextStyle(
                          color: textCol,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        '${lat.toStringAsFixed(4)}° N, ${lng.toStringAsFixed(4)}° E • Live Synced',
                        style: TextStyle(
                          color: isMe ? Colors.white70 : const Color(0xFF64748B),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isMe ? Colors.white : const Color(0xFFE65100)).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'LIVE RADAR',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.white : const Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Embedded Interactive Map Preview Trigger Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.black.withOpacity(0.22) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isMe ? Colors.white24 : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sessionStatus == 'in_progress'
                          ? 'En route together • Tap to Open Live Map ➔'
                          : 'Tap to see where rider & passenger are in live ➔',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isMe ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const Icon(Icons.open_in_full_rounded, size: 13, color: Color(0xFFE65100)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableMessageText(ChatMessage msg) {
    final text = msg.text;
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: AppTypography.bodyMd.copyWith(
          color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface,
        ),
      );
    }

    final spans = <InlineSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: TextStyle(color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface),
        ));
      }
      final url = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: InkWell(
          onTap: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            url,
            style: TextStyle(
              color: msg.isMe ? const Color(0xFFFFF176) : const Color(0xFF1976D2),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: TextStyle(color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface),
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildDateDivider(DateTime dt) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDateDivider(dt),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatIntroCard() {
    final displayName = widget.displayName;
    final role = widget.peerRole ?? 'Companion';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE65100).withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.verified, size: 16, color: Color(0xFF0284C7)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: Text(
                '$role • ${widget.vehicleModel}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC2410C),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verified DIU Commute Chat',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Chat directly to coordinate pickup point, timing, and helmet arrangements. Live coordinates can be shared with the GPS button below.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFFFCC80)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.waving_hand, size: 14),
                  label: const Text('Say Hi', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    _messageController.text = 'Hi ${displayName.split(" ").first}! 👋';
                    _sendMessage();
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.my_location, size: 14),
                  label: const Text('Share Location', style: TextStyle(fontSize: 12)),
                  onPressed: _shareLocation,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFFA7F3D0)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('Call', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    DirectCallService.showCallOptions(
                      context,
                      phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                      peerName: displayName,
                      peerRole: role,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showStudentProfileDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE65100).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                effectiveDisplayName.isNotEmpty ? effectiveDisplayName[0].toUpperCase() : 'S',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    effectiveDisplayName,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.verified, color: Color(0xFF16A34A), size: 18),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_resolvedDept ?? 'DIU Department'} • ${widget.peerRole ?? 'DIU Campus Peer'}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),

            // Profile info cards
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  if (effectiveStudentId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: Color(0xFF0284C7), size: 20),
                          const SizedBox(width: 12),
                          const Text('Student ID', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                          const Spacer(),
                          Text(effectiveStudentId, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 12),
                      const Text('Phone Number', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                      const Spacer(),
                      Text(
                        effectivePhone.isNotEmpty ? effectivePhone : 'Not Provided',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: effectivePhone.isNotEmpty ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  if (_resolvedEmail != null && _resolvedEmail!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, color: Color(0xFFEA580C), size: 20),
                        const SizedBox(width: 12),
                        const Text('Email', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _resolvedEmail!,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final phone = effectivePhone;
                      if (phone.isNotEmpty) {
                        DirectCallService.makeDirectPhoneCall(context, phoneNumber: phone, peerName: effectiveDisplayName);
                      } else {
                        DirectCallService.showCallOptions(context, phoneNumber: phone, peerName: effectiveDisplayName, peerRole: widget.peerRole ?? 'DIU Peer');
                      }
                    },
                    icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                    label: const Text('Call Student', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
                if (effectivePhone.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: effectivePhone));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $effectivePhone to clipboard'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF0F172A)),
                    label: const Text('Copy', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubbleIndicator extends StatefulWidget {
  final String peerName;

  const _TypingBubbleIndicator({required this.peerName});

  @override
  State<_TypingBubbleIndicator> createState() => _TypingBubbleIndicatorState();
}

class _TypingBubbleIndicatorState extends State<_TypingBubbleIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final double progress = (_animController.value - (index * 0.18)) % 1.0;
        final double bounce = (progress >= 0 && progress <= 0.5)
            ? (1.0 - (progress * 2 - 0.5).abs() * 2)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -bounce * 4.5),
          child: Container(
            width: 6.5,
            height: 6.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withOpacity(0.55 + (bounce * 0.45)),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.peerName} is typing',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE65100),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(0),
              _buildDot(1),
              _buildDot(2),
            ],
          ),
        ],
      ),
    );
  }

}
