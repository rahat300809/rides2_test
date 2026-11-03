import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

/// NotificationSoundService
/// Provides high-priority loud alert buzzer for ringing,
/// and chime notifications for incoming messages across Android & Web.
class NotificationSoundService {
  NotificationSoundService._();

  static AudioPlayer? _ringPlayer;
  static AudioPlayer? _chimePlayer;
  static Timer? _vibrationTimer;
  static bool _isRinging = false;

  static bool get isRinging => _isRinging;

  /// Play a loud ringing buzzer sound when someone rings you
  static Future<void> playRingAlert({int durationSeconds = 25}) async {
    try {
      stopRinging();
      _isRinging = true;

      // 1. Initialize audio player and play looping alert sound
      try {
        _ringPlayer = AudioPlayer();
        await _ringPlayer?.setVolume(1.0);
        await _ringPlayer?.setReleaseMode(ReleaseMode.loop);
        await _ringPlayer?.play(AssetSource('sounds/ring_alert.wav'));
      } catch (e) {
        debugPrint('[NotificationSoundService] Ring player asset error, using audio pulse: $e');
      }

      // 2. Hardware vibration + periodic system sound buzzer pulses
      _vibrationTimer?.cancel();
      _vibratePulse();
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}

      _vibrationTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        if (!_isRinging) {
          _vibrationTimer?.cancel();
          return;
        }
        _vibratePulse();
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      });

      // Auto stop after duration
      Future.delayed(Duration(seconds: durationSeconds), () {
        if (_isRinging) {
          stopRinging();
        }
      });
    } catch (e) {
      debugPrint('[NotificationSoundService] playRingAlert error: $e');
      _vibratePulse();
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  /// Stop ringing immediately (when dismissed or answered)
  static void stopRinging() {
    _isRinging = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try {
      _ringPlayer?.stop();
      _ringPlayer?.dispose();
    } catch (_) {}
    _ringPlayer = null;
  }

  /// Play a crisp notification chime when a new message arrives
  static Future<void> playMessageChime() async {
    try {
      _chimePlayer?.dispose();
      _chimePlayer = AudioPlayer();
      await _chimePlayer?.setVolume(0.9);
      await _chimePlayer?.setReleaseMode(ReleaseMode.release);
      await _chimePlayer?.play(AssetSource('sounds/message_chime.wav'));

      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    } catch (e) {
      debugPrint('[NotificationSoundService] playMessageChime fallback: $e');
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  static void _vibratePulse() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
