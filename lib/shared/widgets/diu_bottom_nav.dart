import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';

class DiuBottomNav extends ConsumerWidget {
  final int currentIndex;
  final Function(int index) onTap;
  final int unreadChats;

  const DiuBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadChats = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appMode = ref.watch(appModeProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bottomNavBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x20E65100),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              // 0. Home
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                ),
              ),

              // 1. All Shared Rides (Adapts based on mode)
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  icon: appMode.isPassenger
                      ? Icons.explore_outlined
                      : Icons.two_wheeler_outlined,
                  activeIcon: appMode.isPassenger
                      ? Icons.explore
                      : Icons.two_wheeler,
                  label: appMode.isPassenger
                      ? 'Find Rides'
                      : (appMode.isRider ? 'Ride Status' : 'All Rides'),
                ),
              ),

              // 2. Center Action (Adapts: Request Ride for Passenger, Offer Ride for Rider/All)
              Expanded(
                child: _buildCenterAction(appMode),
              ),

              // 3. Community SMS & Messages
              Expanded(
                child: _buildNavItemWithBadge(
                  index: 3,
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: 'Messages',
                  badgeCount: unreadChats,
                  badgeColor: AppColors.secondary,
                ),
              ),

              // 4. Campus News Feed
              Expanded(
                child: _buildNavItem(
                  index: 4,
                  icon: Icons.feed_outlined,
                  activeIcon: Icons.feed_rounded,
                  label: 'News Feed',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterAction(AppMode appMode) {
    final isSelected = currentIndex == 2;
    final isPassenger = appMode.isPassenger;

    return GestureDetector(
      onTap: () => onTap(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -12),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isPassenger
                      ? [
                          const Color(0xFF10B981), // Emerald Teal
                          const Color(0xFF059669),
                        ]
                      : [
                          const Color(0xFFD84315), // Royal Indigo
                          const Color(0xFFFFA000), // Electric Purple
                        ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isPassenger ? const Color(0xFF10B981) : const Color(0xFFE65100)).withOpacity(0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isPassenger ? Icons.hail_rounded : (appMode.isRider ? Icons.two_wheeler : Icons.add),
                color: Colors.white,
                size: isPassenger ? 27 : 29,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -8),
            child: Text(
              isPassenger ? 'Request Ride' : 'Offer Ride',
              style: AppTypography.labelSm.copyWith(
                color: isSelected ? AppColors.bottomNavSelected : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.bottomNavSelected : AppColors.bottomNavUnselected;

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTypography.labelSm.copyWith(
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int badgeCount,
    Color badgeColor = AppColors.secondary,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.bottomNavSelected : AppColors.bottomNavUnselected;

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: badgeCount > 0
                      ? (isSelected ? badgeColor : badgeColor.withOpacity(0.8))
                      : color,
                  size: 24,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -3,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                          minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.surface, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
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
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTypography.labelSm.copyWith(
                  color: badgeCount > 0 && !isSelected
                      ? badgeColor
                      : color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
