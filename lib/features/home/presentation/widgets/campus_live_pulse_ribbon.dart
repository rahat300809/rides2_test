import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

/// Elegant horizontal live campus stats ribbon displaying active riders,
/// open student requests, and varsity verification badges.
class CampusLivePulseRibbon extends ConsumerWidget {
  const CampusLivePulseRibbon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];
    final allRequests = ref.watch(allPassengerRequestsProvider).value ?? [];

    final activeRidesCount = allRides.where((r) => r.availableSeats > 0).length;
    final activeRequestsCount = allRequests.where((req) => req.status == 'open').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildPill(
            icon: Icons.two_wheeler_rounded,
            iconColor: const Color(0xFFE65100),
            bgColor: const Color(0xFFFFF3E0),
            title: '$activeRidesCount Bikes',
            subtitle: 'On Corridor',
          ),
          _buildDivider(),
          _buildPill(
            icon: Icons.hail_rounded,
            iconColor: const Color(0xFF0284C7),
            bgColor: const Color(0xFFF0F9FF),
            title: '$activeRequestsCount Requests',
            subtitle: 'Waiting Gigs',
          ),
          _buildDivider(),
          _buildPill(
            icon: Icons.verified_user_rounded,
            iconColor: const Color(0xFF16A34A),
            bgColor: const Color(0xFFF0FDF4),
            title: '100% DIU',
            subtitle: 'Student Only',
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 24,
      width: 1,
      color: const Color(0xFFE2E8F0),
    );
  }
}

