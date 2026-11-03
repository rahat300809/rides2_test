import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';

class DepartingRidesCarousel extends StatelessWidget {
  final List<RideModel> rides;
  final Function(RideModel ride) onRequestSeat;
  final VoidCallback onSeeAll;

  const DepartingRidesCarousel({
    super.key,
    required this.rides,
    required this.onRequestSeat,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Departing Soon',
                    style: AppTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${rides.length} Available',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: onSeeAll,
                child: Text(
                  'See all',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Carousel Scroll Track or Empty State
        if (rides.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.outlineVariant.withOpacity(0.5)),
                boxShadow: const [
                  BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.two_wheeler, size: 40, color: Color(0xFFE65100)),
                  const SizedBox(height: 8),
                  Text(
                    'No Peer Motorbikes Departing Soon',
                    style: AppTypography.bodyLgMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Be the first student to offer a motorbike ride or check Search for upcoming trips.',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 258,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: rides.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final ride = rides[index];
                return _buildRideCard(context, ride);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRideCard(BuildContext context, RideModel ride) {
    const primaryAmber = Color(0xFFE65100);
    const obsidianDark = Color(0xFF141416);

    return Container(
      width: 316,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 2,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Driver info header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFFFF3E0),
                        child: Text(
                          ride.driverName.substring(0, 1),
                          style: const TextStyle(
                            color: primaryAmber,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 9, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            ride.driverName,
                            style: AppTypography.bodyMdMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF141416),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            ride.driverDept,
                            style: const TextStyle(
                              color: primaryAmber,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 13, color: Color(0xFFFFA000)),
                          const SizedBox(width: 3),
                          Text(
                            ride.driverRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF141416),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${ride.driverRideCount} rides)',
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatBdt(ride.farePerSeat),
                    style: const TextStyle(
                      color: primaryAmber,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const Text(
                    '1 seat',
                    style: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Route Info Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ride.originName,
                        style: const TextStyle(
                          color: Color(0xFF141416),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: primaryAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ride.destinationName,
                        style: const TextStyle(
                          color: Color(0xFF141416),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Moto details + Helmet + Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.two_wheeler,
                    size: 15,
                    color: primaryAmber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ride.vehicle.modelName,
                    style: const TextStyle(
                      color: Color(0xFF3A3A3C),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '🪖 Helmet',
                      style: TextStyle(
                        color: primaryAmber,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateTimeUtils.formatTime(ride.departureTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: obsidianDark,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Request Seat CTA (Obsidian dark button matching Reference 2)
          ElevatedButton(
            onPressed: () => onRequestSeat(ride),
            style: ElevatedButton.styleFrom(
              backgroundColor: obsidianDark,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Book Moto Seat (1/1)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 15, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
