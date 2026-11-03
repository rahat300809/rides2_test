import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/providers/mode_session_provider.dart';
import 'package:diu_ride/core/utils/mode_switch_controller.dart';

/// Normalized Tactile Mode Toggle Switch (Student ↔ Biker).
/// Crisp, solid pill container with sliding active indicator,
/// matching the native DIU theme without blurry glass effects.
class LiquidGlass3DToggle extends ConsumerWidget {
  final double width;
  final double height;
  final bool showLabels;

  const LiquidGlass3DToggle({
    super.key,
    this.width = 124,
    this.height = 32,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(appModeProvider);
    final isBootstrapping = ref.watch(modeSessionProvider).isBootstrapping;
    final isRider = currentMode == AppMode.rider;

    return GestureDetector(
      onTap: isBootstrapping
          ? null
          : () async {
              final targetMode = isRider ? AppMode.passenger : AppMode.rider;
              await ModeSwitchController.switchMode(context, ref, targetMode);
            },
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(height),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Sliding Solid Active Thumb
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: isRider ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: (width / 2) - 3,
                height: height - 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: isRider
                      ? const LinearGradient(
                          colors: [Color(0xFFD84315), Color(0xFFFFA000)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: !isRider ? Colors.white : null,
                  boxShadow: [
                    BoxShadow(
                      color: isRider
                          ? const Color(0xFFE65100).withOpacity(0.35)
                          : const Color(0xFF0F172A).withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Foreground Labels (Student & Biker)
            Row(
              children: [
                // Passenger / Student Half
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_rounded,
                          size: 13,
                          color: !isRider ? const Color(0xFFE65100) : const Color(0xFF64748B),
                        ),
                        if (showLabels) ...[
                          const SizedBox(width: 3.5),
                          Text(
                            'Student',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: !isRider ? FontWeight.w800 : FontWeight.w600,
                              color: !isRider ? const Color(0xFFE65100) : const Color(0xFF64748B),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Rider / Biker Half
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.two_wheeler_rounded,
                          size: 14,
                          color: isRider ? Colors.white : const Color(0xFF64748B),
                        ),
                        if (showLabels) ...[
                          const SizedBox(width: 3.5),
                          Text(
                            'Biker',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isRider ? FontWeight.w800 : FontWeight.w600,
                              color: isRider ? Colors.white : const Color(0xFF64748B),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
