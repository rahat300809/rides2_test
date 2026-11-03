import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

class CampusCategoryGrid extends StatelessWidget {
  final VehicleType? selectedType;
  final bool femaleOnlySelected;
  final Function(VehicleType? type, bool isFemaleOnly) onSelectCategory;

  const CampusCategoryGrid({
    super.key,
    required this.selectedType,
    required this.femaleOnlySelected,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Campus Moto Share',
                    style: AppTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE65100).withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.two_wheeler, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Bikes Only',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Apple iOS 3D Grid of Moto Categories
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.48,
            children: [
              // 1. Find a Bike Ride
              _buildCategoryCard(
                title: 'Find a Bike Ride',
                subtitle: 'Active campus commutes',
                badgeText: 'Live Rides',
                badgeBg: const Color(0xFFE8F5E9),
                badgeColor: const Color(0xFF2E7D32),
                icon: Icons.two_wheeler,
                iconColor: const Color(0xFF00C853),
                iconBg: const Color(0xFFE8F5E9),
                isSelected: true,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 2. Offer Your Ride
              _buildCategoryCard(
                title: 'Offer a Ride',
                subtitle: 'Share your motorbike seat',
                badgeText: 'Bikers',
                badgeBg: const Color(0xFFFFF3E0),
                badgeColor: const Color(0xFFE65100),
                icon: Icons.add_circle_outline,
                iconColor: const Color(0xFFE65100),
                iconBg: const Color(0xFFFFF3E0),
                isSelected: false,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 3. Campus Messages
              _buildCategoryCard(
                title: 'Campus Messages',
                subtitle: 'Direct peer chats & calls',
                badgeText: 'Chatbox',
                badgeBg: const Color(0xFFE0F2FE),
                badgeColor: const Color(0xFF0284C7),
                icon: Icons.chat_bubble_outline,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFE0F2FE),
                isSelected: false,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 4. Scheduled Commutes
              _buildCategoryCard(
                title: 'Scheduled Commutes',
                subtitle: 'Morning & evening classes',
                badgeText: 'Planned',
                badgeBg: const Color(0xFFF3E8FF),
                badgeColor: const Color(0xFF7E22CE),
                icon: Icons.schedule,
                iconColor: const Color(0xFF7E22CE),
                iconBg: const Color(0xFFF3E8FF),
                isSelected: false,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeBg,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65100) : Colors.black.withOpacity(0.06),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFE65100).withOpacity(0.18)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isSelected ? 14 : 10,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected ? Colors.white : iconColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: AppTypography.labelSm.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
