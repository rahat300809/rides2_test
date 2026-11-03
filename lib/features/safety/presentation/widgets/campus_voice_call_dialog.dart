import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';

class CampusVoiceCallDialog extends StatefulWidget {
  final String peerName;
  final String peerPhone;
  final String peerRole;
  final String? peerDept;

  const CampusVoiceCallDialog({
    super.key,
    required this.peerName,
    required this.peerPhone,
    this.peerRole = 'Ride Companion',
    this.peerDept = 'DIU Student',
  });

  static Future<void> show(
    BuildContext context, {
    required String peerName,
    required String peerPhone,
    String peerRole = 'Ride Companion',
    String? peerDept,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CampusVoiceCallDialog(
        peerName: peerName,
        peerPhone: peerPhone,
        peerRole: peerRole,
        peerDept: peerDept,
      ),
    );
  }

  @override
  State<CampusVoiceCallDialog> createState() => _CampusVoiceCallDialogState();
}

class _CampusVoiceCallDialogState extends State<CampusVoiceCallDialog>
    with SingleTickerProviderStateMixin {
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  int _callSeconds = 0;
  Timer? _connectTimer;
  Timer? _callTimer;
  Timer? _hapticRingTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Periodic haptic ring pulse during connection phase
    _hapticRingTimer = Timer.periodic(const Duration(milliseconds: 1400), (t) {
      if (!_isConnected && mounted) {
        HapticFeedback.vibrate();
      } else {
        t.cancel();
      }
    });

    // Simulate connecting to peer over campus voice network
    _connectTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        _hapticRingTimer?.cancel();
        setState(() => _isConnected = true);
        _startCallTimer();
      }
    });
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _hapticRingTimer?.cancel();
    _connectTimer?.cancel();
    _callTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _endCall() {
    _callTimer?.cancel();
    _connectTimer?.cancel();
    final duration = _callSeconds > 0 ? _formatDuration(_callSeconds) : '00:00';
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const Icon(Icons.call_end, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            Text(
              'Call ended ($duration) • ${widget.peerName}',
              style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _copyPhone() {
    Clipboard.setData(ClipboardData(text: widget.peerPhone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Phone number ${widget.peerPhone} copied to clipboard!'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _dialPhone() async {
    await DirectCallService.makeDirectPhoneCall(
      context,
      phoneNumber: widget.peerPhone,
      peerName: widget.peerName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1E19),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),

          // Top Security Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.call, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Direct Campus Peer Voice Call',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Animated Peer Avatar
          ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.05).animate(_pulseController),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    _isConnected ? const Color(0xFF00A86B) : const Color(0xFF004D40),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(_isConnected ? 0.5 : 0.2),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 44,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Peer Name & Role
          Text(
            widget.peerName,
            style: AppTypography.headlineSm.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.peerRole,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (widget.peerDept != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.peerDept!,
                    style: const TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Call Status / Duration
          Text(
            _isConnected
                ? 'Connected • ${_formatDuration(_callSeconds)}'
                : 'Connecting peer via DIU Voice Net...',
            style: TextStyle(
              color: _isConnected ? const Color(0xFF69F0AE) : Colors.white60,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),

          // Direct Phone Quick Trigger
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: _dialPhone,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_in_talk, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Direct Call: ${widget.peerPhone}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _copyPhone,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Bottom Action Bar: Mute, End Call, Speaker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    onPressed: () => setState(() => _isMuted = !_isMuted),
                    icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    iconSize: 26,
                    style: IconButton.styleFrom(
                      backgroundColor: _isMuted ? Colors.white24 : Colors.white12,
                      foregroundColor: _isMuted ? Colors.redAccent : Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isMuted ? 'Muted' : 'Mute',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),

              // Hang Up Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    onPressed: _endCall,
                    icon: const Icon(Icons.call_end),
                    iconSize: 34,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(20),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'End Call',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              // Speakerphone Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                    icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down),
                    iconSize: 26,
                    style: IconButton.styleFrom(
                      backgroundColor: _isSpeakerOn ? AppColors.primary.withOpacity(0.3) : Colors.white12,
                      foregroundColor: _isSpeakerOn ? AppColors.primary : Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
