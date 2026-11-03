import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/auth/presentation/screens/login_screen.dart';

bool isVisitorMode(WidgetRef ref) {
  final user = ref.read(authNotifierProvider).user;
  return user != null && user.isVisitor;
}

bool checkAndEnforceVisitorMode(BuildContext context, WidgetRef ref, {String actionName = 'perform this action'}) {
  if (isVisitorMode(ref)) {
    showVisitorModeDialog(context, actionName: actionName);
    return true; // blocked
  }
  return false; // allowed
}

void showVisitorModeDialog(BuildContext context, {String actionName = 'perform this action'}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Icon(
              Icons.visibility_rounded,
              color: Color(0xFFD97706),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visitor Mode',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Explore-Only Access',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              'You are in visitor mode! You cannot $actionName while exploring as a guest.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'To post rides, request seats, broadcast commute requests, message students, or participate in campus feed, please sign in with your verified DIU Student ID or create an account.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
          ),
          child: const Text('Keep Exploring', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Consumer(
          builder: (context, ref, _) {
            return ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Sign In / Register', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            );
          },
        ),
      ],
    ),
  );
}

