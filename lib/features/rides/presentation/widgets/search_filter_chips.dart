import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class SearchFilterChips extends StatelessWidget {
  final RideSearchFilterState filterState;
  final RideSearchNotifier notifier;

  const SearchFilterChips({
    super.key,
    required this.filterState,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          // Verified Only
          _buildChip(
            label: 'Verified Only',
            icon: Icons.tune,
            isSelected: filterState.verifiedOnly,
            onTap: notifier.toggleVerifiedOnly,
          ),
          const SizedBox(width: 8),

          // Price: Lowest
          _buildChip(
            label: 'Price: Lowest',
            icon: Icons.payments,
            iconColor: AppColors.secondary,
            isSelected: filterState.sortByLowestPrice,
            onTap: notifier.toggleLowestPrice,
          ),
          const SizedBox(width: 8),

          // Bikes Only
          _buildChip(
            label: 'Motorbikes Only',
            icon: Icons.two_wheeler,
            iconColor: const Color(0xFF2E7D32),
            isSelected: true,
            onTap: () {},
          ),
          const SizedBox(width: 8),

          // Leaving <20m
          _buildChip(
            label: 'Leaving <20m',
            icon: Icons.bolt,
            isSelected: filterState.leavingSoon,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    Color? iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : (iconColor ?? AppColors.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelMd.copyWith(
                color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
