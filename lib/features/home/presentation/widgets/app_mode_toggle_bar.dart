import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/providers/mode_session_provider.dart';
import 'package:diu_ride/core/utils/mode_switch_controller.dart';

class AppModeToggleBar extends ConsumerWidget {
  final ValueChanged<AppMode>? onModeChanged;

  const AppModeToggleBar({
    super.key,
    this.onModeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(appModeProvider);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSegment(
            context: context,
            ref: ref,
            mode: AppMode.all,
            title: 'All (Default)',
            icon: Icons.tune,
            isActive: currentMode == AppMode.all,
          ),
          _buildSegment(
            context: context,
            ref: ref,
            mode: AppMode.passenger,
            title: 'Passenger',
            icon: Icons.hail_rounded,
            isActive: currentMode == AppMode.passenger,
          ),
          _buildSegment(
            context: context,
            ref: ref,
            mode: AppMode.rider,
            title: 'Rider',
            icon: Icons.two_wheeler,
            isActive: currentMode == AppMode.rider,
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required BuildContext context,
    required WidgetRef ref,
    required AppMode mode,
    required String title,
    required IconData icon,
    required bool isActive,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (isActive) return;
          if (ref.read(modeSessionProvider).isBootstrapping) return;

          final ok = await ModeSwitchController.switchMode(context, ref, mode);
          if (!ok || !context.mounted) return;
          onModeChanged?.call(mode);
          _showModeToast(context, mode);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 7.5),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? const Color(0xFFE65100) : Colors.white.withOpacity(0.9),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? const Color(0xFF141416) : Colors.white.withOpacity(0.92),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeToast(BuildContext context, AppMode mode) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    String title = '';
    String subtitle = '';
    IconData icon = Icons.check_circle;

    switch (mode) {
      case AppMode.all:
        title = 'Default Mode Active';
        subtitle = 'All campus rider & passenger commute features visible';
        icon = Icons.tune;
        break;
      case AppMode.passenger:
        title = 'Passenger Mode Active';
        subtitle = 'Showing ride search, book seat & throw ride requests';
        icon = Icons.hail_rounded;
        break;
      case AppMode.rider:
        title = 'Rider Mode Active';
        subtitle = 'Showing bike offer tools, student pickup requests & rider messages';
        icon = Icons.two_wheeler;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: const Color(0xFFFFA000)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 11,
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
    );
  }
}
