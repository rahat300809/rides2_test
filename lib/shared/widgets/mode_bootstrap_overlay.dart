import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/core/providers/mode_session_provider.dart';

/// Full-screen setup UI while Student ↔ Biker runtime is rebuilt.
class ModeBootstrapOverlay extends ConsumerWidget {
  const ModeBootstrapOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(modeSessionProvider);
    if (!session.isBootstrapping) return const SizedBox.shrink();

    final AppMode target = session.pendingMode ?? ref.watch(appModeProvider);
    final isRider = target == AppMode.rider;
    final accent = isRider ? const Color(0xFFE65100) : const Color(0xFF059669);
    final title = isRider ? 'Setting up Biker App' : 'Setting up Student App';
    final subtitle = isRider
        ? 'Student tools are being disabled. Your trip history and earnings stay on your account.'
        : 'Biker tools are being disabled. Your trip history and payments stay on your account.';

    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B1220).withOpacity(0.94),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isRider
                          ? const [Color(0xFFD84315), Color(0xFFFFA000)]
                          : const [Color(0xFF059669), Color(0xFF34D399)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    isRider ? Icons.two_wheeler_rounded : Icons.school_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: session.progress.clamp(0.05, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  session.statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(session.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(flex: 3),
                Text(
                  'This takes about 10–15 seconds',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
