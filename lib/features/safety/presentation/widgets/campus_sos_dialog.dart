import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/app_constants.dart';
import 'package:diu_ride/core/theme/app_typography.dart';


class CampusSosDialog {
  CampusSosDialog._();

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onConfirmed,
    String locationName = 'DIU Smart City, Ashulia',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppColors.surfaceContainerLowest,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emergency_outlined, color: AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Campus Emergency SOS',
                  style: AppTypography.headlineSm.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to trigger Campus SOS?',
                style: AppTypography.bodyLgMedium.copyWith(color: AppColors.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'This will instantly notify:\n• DIU Smart Campus Proctor Control (${AppConstants.proctorExtension})\n• Campus Security Dispatch\n• Your registered Emergency Guardian Contacts\n\nYour live coordinates ($locationName) will be broadcast.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_in_talk, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Direct Proctor Helpline: ${AppConstants.proctorSecurityHelpline}',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.labelLg.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onConfirmed();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.onError,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text('Confirm SOS Dispatch', style: AppTypography.labelLg),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
