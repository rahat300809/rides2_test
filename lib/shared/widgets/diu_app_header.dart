import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/feed/presentation/screens/campus_feed_screen.dart';
import 'package:diu_ride/shared/widgets/liquid_glass_3d_toggle.dart';

class DiuAppHeader extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationsTap;

  const DiuAppHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.onProfileTap,
    this.onNotificationsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final hasPendingRequests =
        ref.watch(pendingRideRequestsProvider).isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.97),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 10,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Logo + Title
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else ...[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => SvgPicture.asset(
                            'assets/svg/diu_ride_logo.svg',
                            height: 34,
                            width: 34,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'DIU Ride',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        title,
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Right: Notification bell + Messages + Profile avatar
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Notification Bell with animated badge
                  GestureDetector(
                    onTap: onNotificationsTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hasPendingRequests
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.surfaceContainerLow,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasPendingRequests
                                ? Icons.notifications_active
                                : (unreadCount > 0
                                    ? Icons.notifications
                                    : Icons.notifications_none_outlined),
                            size: 20,
                            color: hasPendingRequests
                                ? AppColors.primary
                                : (unreadCount > 0
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant),
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              constraints: const BoxConstraints(
                                  minWidth: 16, minHeight: 16),
                              decoration: BoxDecoration(
                                color: hasPendingRequests
                                    ? AppColors.primary
                                    : AppColors.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.surface, width: 1.5),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Campus Messages Button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CampusMessagesScreen(
                            onExploreRides: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 19,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Campus Feed Button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CampusFeedScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 19,
                        color: Color(0xFF006699),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3D Liquid Glass Mode Toggle (Passenger ↔ Rider)
                  const LiquidGlass3DToggle(width: 120, height: 32),
                  const SizedBox(width: 8),

                  // Avatar with live indicator
                  GestureDetector(
                    onTap: onProfileTap,
                    child: Stack(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.surface, width: 2),
                            color: AppColors.primaryContainer,
                          ),
                          child: const Center(
                            child:
                                Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
