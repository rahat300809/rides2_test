import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/providers/mode_session_provider.dart';
import 'package:diu_ride/core/utils/app_mode_switch_guard.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

/// Hard Student ↔ Biker switch:
/// tears down the other mode's live UI/runtime, remounts a fresh shell,
/// and keeps account history / paid / earned data on the server untouched.
class ModeSwitchController {
  ModeSwitchController._();

  static const Duration totalSetupDuration = Duration(seconds: 12);

  static Future<bool> switchMode(
    BuildContext context,
    WidgetRef ref,
    AppMode targetMode, {
    VoidCallback? onShellRemount,
  }) async {
    final current = ref.read(appModeProvider);
    if (current == targetMode) return true;
    if (ref.read(modeSessionProvider).isBootstrapping) return false;

    final canSwitch =
        await AppModeSwitchGuard.canSwitchMode(context, ref, targetMode);
    if (!canSwitch || !context.mounted) return false;

    HapticFeedback.mediumImpact();
    final session = ref.read(modeSessionProvider.notifier);
    session.beginBootstrap(targetMode);

    final steps = targetMode.isRider
        ? const [
            (0.10, 'Closing Student tools & listeners…'),
            (0.28, 'Clearing Student live commute cache…'),
            (0.48, 'Preparing Biker ride-offer workspace…'),
            (0.68, 'Loading Biker map, offers & student requests…'),
            (0.86, 'Opening Biker app shell…'),
            (1.0, 'Biker mode ready'),
          ]
        : const [
            (0.10, 'Closing Biker tools & listeners…'),
            (0.28, 'Clearing Biker live offer cache…'),
            (0.48, 'Preparing Student commute workspace…'),
            (0.68, 'Loading Student rides, bookings & requests…'),
            (0.86, 'Opening Student app shell…'),
            (1.0, 'Student mode ready'),
          ];

    final stepMs = totalSetupDuration.inMilliseconds ~/ steps.length;

    try {
      // 1) Flip mode + remount shell FIRST so old mode widgets dispose
      //    before any cache invalidation (avoids UI freeze at ~28%).
      await ref.read(appModeProvider.notifier).setMode(targetMode);
      session.remountShell();
      onShellRemount?.call();

      // Let the frame finish disposing the previous IndexedStack.
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Soft-close overlays without nuking the root route mid-switch.
      if (context.mounted) {
        try {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } catch (_) {}
      }

      // Progress UI must keep ticking even if cache work is heavy.
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        session.updateProgress(step.$1, step.$2);

        if (i == 1) {
          // Run after this progress frame so the bar never freezes on 28%.
          Future<void>.microtask(() => _invalidateLiveModeCaches(ref));
        }

        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    } catch (e, st) {
      debugPrint('[ModeSwitch] bootstrap error: $e\n$st');
      session.updateProgress(1.0, targetMode.isRider
          ? 'Biker mode ready'
          : 'Student mode ready');
    } finally {
      session.finishBootstrap();
    }

    return true;
  }

  /// Live UI caches only. Auth + completed trip/earnings history stay intact.
  static void _invalidateLiveModeCaches(WidgetRef ref) {
    void safeInvalidate(ProviderOrFamily provider) {
      try {
        ref.invalidate(provider);
      } catch (e) {
        debugPrint('[ModeSwitch] invalidate skipped: $e');
      }
    }

    safeInvalidate(allAvailableRidesProvider);
    safeInvalidate(allSystemRidesProvider);
    safeInvalidate(departingSoonRidesProvider);
    safeInvalidate(myPostedRidesProvider);
    safeInvalidate(searchRidesResultsProvider);
    safeInvalidate(allPassengerRequestsProvider);
    safeInvalidate(myPassengerRequestsProvider);
    safeInvalidate(passengerRequestsProvider);
    safeInvalidate(myBookingsProvider);
    try {
      ref.read(rideSearchFilterProvider.notifier).clearFilters();
    } catch (_) {}
  }
}
