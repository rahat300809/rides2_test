import 'package:flutter/material.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';
import 'package:diu_ride/features/ai_assistant/presentation/widgets/diu_ai_chat_sheet.dart';

class DestinationMatchingBikesView extends StatelessWidget {
  final String query;
  final List<RideModel> matchingRides;
  final Function(RideModel ride) onRequestSeat;
  final VoidCallback onClearQuery;
  final Function(String address)? onSetAsDefault;

  const DestinationMatchingBikesView({
    super.key,
    required this.query,
    required this.matchingRides,
    required this.onRequestSeat,
    required this.onClearQuery,
    this.onSetAsDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFE65100).withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE65100).withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with query match
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE65100).withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.two_wheeler, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Motorbikes to "$query"',
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1C1C1E),
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              matchingRides.isNotEmpty
                                  ? '${matchingRides.length} student rider${matchingRides.length > 1 ? 's' : ''} heading this way • Tap to expand'
                                  : 'No rides found for "$query"',
                              style: AppTypography.labelSm.copyWith(
                                color: const Color(0xFF8E8E93),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onClearQuery,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 14, color: Color(0xFF8E8E93)),
                        SizedBox(width: 4),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Results List or Empty State
            if (matchingRides.isEmpty)
              _buildEmptyState(context)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: matchingRides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final ride = matchingRides[index];
                  return _ExpandableMatchingBikeCard(
                    ride: ride,
                    onRequestSeat: onRequestSeat,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          const Icon(Icons.two_wheeler_outlined, size: 44, color: Color(0xFF8E8E93)),
          const SizedBox(height: 10),
          Text(
            'No Active Motorbike Rides to "$query"',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'No student is currently offering a ride heading towards this area. You can save it as your default commute address or request a ride.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onSetAsDefault != null)
                ElevatedButton.icon(
                  onPressed: () => onSetAsDefault!(query),
                  icon: const Icon(Icons.notification_add, size: 16),
                  label: Text('Save "$query" for Alerts'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF141416),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: () => DiuAiChatSheet.show(context),
                icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFE65100)),
                label: const Text('Ask DIU AI Assistant'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF3E0),
                  foregroundColor: const Color(0xFFE65100),
                  side: const BorderSide(color: Color(0xFFFFCC80), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpandableMatchingBikeCard extends StatefulWidget {
  final RideModel ride;
  final Function(RideModel ride) onRequestSeat;

  const _ExpandableMatchingBikeCard({
    required this.ride,
    required this.onRequestSeat,
  });

  @override
  State<_ExpandableMatchingBikeCard> createState() => _ExpandableMatchingBikeCardState();
}

class _ExpandableMatchingBikeCardState extends State<_ExpandableMatchingBikeCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isExpanded ? const Color(0xFFE65100).withOpacity(0.4) : Colors.black.withOpacity(0.06),
          width: _isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isExpanded ? const Color(0xFFE65100).withOpacity(0.06) : Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Rider Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFFFF3E0),
                        child: Text(
                          ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'B',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                ride.driverName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'DIU Verified',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${ride.driverDept} • ⭐ ${ride.driverRating.toStringAsFixed(1)} (${ride.driverRideCount} rides)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E8E93),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Fare & Expand Icon
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            CurrencyFormatter.formatBdt(ride.farePerSeat),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
                            ),
                          ),
                          const Text(
                            '1 seat',
                            style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF8E8E93),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Route Summary Preview
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.04)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.radio_button_checked, size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ride.originName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateTimeUtils.formatTime(ride.departureTime),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFFFF3B30)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ride.destinationName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!_isExpanded)
                          Text(
                            'Tap to expand ▾',
                            style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // EXPANDED DETAILS SECTION
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE65100).withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Waypoint corridor
                      if (ride.waypointName != null && ride.waypointName!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.alt_route, size: 15, color: Color(0xFFE65100)),
                            const SizedBox(width: 6),
                            Text(
                              'Via Waypoint: ${ride.waypointName}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Motorcycle & Helmet details
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Text(
                                  ride.vehicle.modelName,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFE65100)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (ride.vehicle.licensePlate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ride.vehicle.licensePlate,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                              ),
                            ),
                          const Spacer(),
                          const Row(
                            children: [
                              Icon(Icons.verified, size: 13, color: Color(0xFF2E7D32)),
                              SizedBox(width: 3),
                              Text('DIU Verified Bike', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                            ],
                          ),
                        ],
                      ),

                      if (ride.driverPhone != null && ride.driverPhone!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF6B7280)),
                            const SizedBox(width: 6),
                            Text(
                              'Phone: ${ride.driverPhone!}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF4B5563), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Expanded Action Bar: Message Biker, Call Driver, Route Details, Book Seat
                Row(
                  children: [
                    // Chat with Biker
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1B5E20),
                          side: const BorderSide(color: Color(0xFF1B5E20)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 15),
                        label: const Text('Chat Biker', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                rideId: ride.id,
                                peerName: ride.driverName,
                                vehicleModel: ride.vehicle.modelName,
                                peerPhone: ride.driverPhone ?? '',
                                peerRole: 'Driver',
                                peerId: ride.driverId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Call Driver
                    if (ride.driverPhone != null && ride.driverPhone!.isNotEmpty) ...[
                      InkWell(
                        onTap: () {
                          CampusVoiceCallDialog.show(
                            context,
                            peerName: ride.driverName,
                            peerPhone: ride.driverPhone!,
                            peerRole: 'Biker / Rider',
                            peerDept: ride.driverDept,
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.call, color: Color(0xFF2E7D32), size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Full Route Details
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RideDetailsTrackingScreen(rideId: ride.id),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.map_outlined, color: Color(0xFF1F2937), size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Book Seat
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Book Seat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => widget.onRequestSeat(ride),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Collapsed Compact Bar
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 12, color: Color(0xFFE65100)),
                              const SizedBox(width: 4),
                              Text(
                                ride.vehicle.modelName,
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '🪖 Helmet Ready',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFE65100)),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () => widget.onRequestSeat(ride),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF141416),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Book Seat (1/1)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
