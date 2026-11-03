import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

/// Runtime isolation session for Student ↔ Biker.
/// [generation] remounts the nav shell so the inactive mode's UI tree is disposed.
/// Account history / earnings are never cleared here — only live UI caches.
class ModeSessionState {
  final int generation;
  final bool isBootstrapping;
  final AppMode? pendingMode;
  final String statusMessage;
  final double progress;

  const ModeSessionState({
    this.generation = 0,
    this.isBootstrapping = false,
    this.pendingMode,
    this.statusMessage = '',
    this.progress = 0,
  });

  ModeSessionState copyWith({
    int? generation,
    bool? isBootstrapping,
    AppMode? pendingMode,
    bool clearPendingMode = false,
    String? statusMessage,
    double? progress,
  }) {
    return ModeSessionState(
      generation: generation ?? this.generation,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      pendingMode: clearPendingMode ? null : (pendingMode ?? this.pendingMode),
      statusMessage: statusMessage ?? this.statusMessage,
      progress: progress ?? this.progress,
    );
  }
}

class ModeSessionNotifier extends StateNotifier<ModeSessionState> {
  ModeSessionNotifier() : super(const ModeSessionState());

  Timer? _watchdog;

  void beginBootstrap(AppMode target) {
    _watchdog?.cancel();
    state = state.copyWith(
      isBootstrapping: true,
      pendingMode: target,
      statusMessage: target.isRider
          ? 'Closing Student app runtime…'
          : 'Closing Biker app runtime…',
      progress: 0.05,
    );
    // Never leave the overlay stuck (e.g. if UI work freezes mid-step).
    _watchdog = Timer(const Duration(seconds: 18), () {
      if (mounted && state.isBootstrapping) {
        finishBootstrap();
      }
    });
  }

  void updateProgress(double progress, String message) {
    if (!state.isBootstrapping) return;
    state = state.copyWith(
      progress: progress.clamp(0.0, 1.0),
      statusMessage: message,
    );
  }

  /// Remounts mode shell after previous mode caches are cleared.
  void remountShell() {
    state = state.copyWith(generation: state.generation + 1);
  }

  void finishBootstrap() {
    _watchdog?.cancel();
    _watchdog = null;
    state = state.copyWith(
      isBootstrapping: false,
      clearPendingMode: true,
      statusMessage: '',
      progress: 1,
    );
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }
}

final modeSessionProvider =
    StateNotifierProvider<ModeSessionNotifier, ModeSessionState>((ref) {
  return ModeSessionNotifier();
});
