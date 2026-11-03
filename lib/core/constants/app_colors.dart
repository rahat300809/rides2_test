import 'package:flutter/material.dart';

/// Exact Stitch & Mockup Color Tokens for DIU Ride (Matching User Reference)
class AppColors {
  AppColors._();

  // Primary: Warm Amber / Sunset Orange (matching reference mockup headers & accents)
  static const Color primary = Color(0xFFE65100);
  static const Color primaryContainer = Color(0xFFEF6C00);
  static const Color primaryLight = Color(0xFFFFA726);
  static const Color primaryFixed = Color(0xFFFFE082);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);

  // Radiant Sunset Header Gradient
  static const Color headerGradientStart = Color(0xFFE65100); // Rich warm sunset
  static const Color headerGradientMid = Color(0xFFF57C00);   // Radiant amber
  static const Color headerGradientEnd = Color(0xFFFFB74D);   // Soft golden glow

  // Obsidian Deep Dark (matching bottom nav, schedule pill, and primary action buttons)
  static const Color obsidianDark = Color(0xFF141416);
  static const Color obsidianCard = Color(0xFF1C1C1E);
  static const Color onObsidian = Color(0xFFFFFFFF);

  // Secondary: Golden Amber
  static const Color secondary = Color(0xFFFFA000);
  static const Color secondaryContainer = Color(0xFFFFF3E0);
  static const Color onSecondary = Color(0xFF141416);

  // Tertiary: Jade / Eco Commute
  static const Color tertiary = Color(0xFF2E7D32);
  static const Color tertiaryContainer = Color(0xFFE8F5E9);
  static const Color onTertiary = Color(0xFFFFFFFF);

  // Surfaces & Backgrounds (Porcelain & Soft warm white)
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF4F5F7);
  static const Color surfaceContainer = Color(0xFFEEEEF2);
  static const Color surfaceContainerHigh = Color(0xFFE5E7EB);
  static const Color surfaceVariant = Color(0xFFF0F1F5);

  // Text & Content on Surfaces
  static const Color onBackground = Color(0xFF141416);
  static const Color onSurface = Color(0xFF141416);
  static const Color onSurfaceVariant = Color(0xFF6B7280);
  static const Color inverseSurface = Color(0xFF141416);
  static const Color inverseOnSurface = Color(0xFFFFFFFF);

  // Outlines & Dividers
  static const Color outline = Color(0xFFE5E7EB);
  static const Color outlineVariant = Color(0xFFF0F0F2);

  // Bottom Navigation (Deep obsidian black matching reference 1)
  static const Color bottomNavBackground = Color(0xFF121214);
  static const Color bottomNavSelected = Color(0xFFFFA000);
  static const Color bottomNavUnselected = Color(0xFF8E8E93);

  // Error & Safety SOS
  static const Color error = Color(0xFFE53935);
  static const Color errorContainer = Color(0xFFFFEBEE);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFFB71C1C);

  // Material 3 container & fixed tokens
  static const Color onSecondaryContainer = Color(0xFFE65100);
  static const Color onTertiaryContainer = Color(0xFF1B5E20);
  static const Color onPrimaryFixed = Color(0xFFE65100);
  static const Color onPrimaryFixedVariant = Color(0xFFBF360C);
  static const Color secondaryFixed = Color(0xFFFFE082);
  static const Color onSecondaryFixed = Color(0xFFE65100);
  static const Color tertiaryFixed = Color(0xFFC8E6C9);
  static const Color onTertiaryFixedVariant = Color(0xFF1B5E20);

  // Rating & Alerts
  static const Color ratingStar = Color(0xFFFFA000);
  static const Color cardShadow = Color(0x0F000000);
  static const Color amberGlowShadow = Color(0x28E65100);
}
