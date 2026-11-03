import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 4-card elegant Bento shortcut grid for campus commuting.
class CampusShortcutsGrid extends StatelessWidget {
  final VoidCallback onOpenCampusRides;
  final VoidCallback onOpenStudentGigs;
  final VoidCallback onOpenLiveMap;
  final VoidCallback onOpenCampusBuzz;

  const CampusShortcutsGrid({
    super.key,
    required this.onOpenCampusRides,
    required this.onOpenStudentGigs,
    required this.onOpenLiveMap,
    required this.onOpenCampusBuzz,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Campus Commute Shortcuts',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  title: 'Campus Rides',
                  subtitle: 'Outgoing bikes',
                  icon: Icons.two_wheeler_rounded,
                  iconColor: const Color(0xFFE65100),
                  accentColor: const Color(0xFFFFF8E1),
                  borderColor: const Color(0xFFFFEDD5),
                  onTap: onOpenCampusRides,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildShortcutCard(
                  title: 'Student Gigs',
                  subtitle: 'Open ride requests',
                  icon: Icons.assignment_rounded,
                  iconColor: const Color(0xFF0284C7),
                  accentColor: const Color(0xFFF0F9FF),
                  borderColor: const Color(0xFFE0F2FE),
                  onTap: onOpenStudentGigs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  title: 'Live Radar',
                  subtitle: 'Interactive map',
                  icon: Icons.map_rounded,
                  iconColor: const Color(0xFFE65100),
                  accentColor: const Color(0xFFFFF8E1),
                  borderColor: const Color(0xFFFFF3E0),
                  onTap: onOpenLiveMap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildShortcutCard(
                  title: 'Campus Buzz',
                  subtitle: 'Student notices',
                  icon: Icons.campaign_rounded,
                  iconColor: const Color(0xFF059669),
                  accentColor: const Color(0xFFF0FDF4),
                  borderColor: const Color(0xFFDCFCE7),
                  onTap: onOpenCampusBuzz,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color accentColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
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

