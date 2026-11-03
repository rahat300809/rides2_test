import 'package:diu_ride/shared/widgets/visitor_mode_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/same_account_guard.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';

/// Clean, Uber-styled Bottom Sheet for Confirming Seat Bookings.
class BookingConfirmationSheet extends ConsumerStatefulWidget {
  final RideModel ride;
  final VoidCallback onBookingSuccess;

  const BookingConfirmationSheet({
    super.key,
    required this.ride,
    required this.onBookingSuccess,
  });

  static Future<void> show({
    required BuildContext context,
    required RideModel ride,
    required VoidCallback onBookingSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => BookingConfirmationSheet(
        ride: ride,
        onBookingSuccess: onBookingSuccess,
      ),
    );
  }

  @override
  ConsumerState<BookingConfirmationSheet> createState() =>
      _BookingConfirmationSheetState();
}

class _BookingConfirmationSheetState
    extends ConsumerState<BookingConfirmationSheet> {
  int _seats = 1;
  String? _selectedDropoffPoint;

  @override
  void initState() {
    super.initState();
    _selectedDropoffPoint = widget.ride.destinationName;
  }

  void _confirmBooking() async {
    if (checkAndEnforceVisitorMode(context, ref, actionName: 'book a ride seat')) return;

    final authUser = ref.read(authNotifierProvider).user;
    if (SameAccountGuard.blockOwnRideBook(context, authUser, widget.ride)) return;

    // Freshness check: disallow booking if departure time has passed (15m grace)
    final now = DateTime.now();
    if (widget.ride.departureTime.isBefore(now.subtract(const Duration(minutes: 15)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: const Text('⚠️ This ride has already departed or expired.'),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    final total = widget.ride.farePerSeat * _seats;
    final dropoff = _selectedDropoffPoint ?? widget.ride.destinationName;
    final success = await ref.read(bookingNotifierProvider.notifier).bookSeat(
          rideId: widget.ride.id,
          pickupPoint: widget.ride.originName,
          dropoffPoint: dropoff,
          seatsBooked: _seats,
          totalFare: total,
          ride: widget.ride,
        );

    if (mounted) {
      Navigator.of(context).pop();
      if (success) {
        widget.onBookingSuccess();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              rideId: widget.ride.id,
              driverName: widget.ride.driverName,
              peerName: widget.ride.driverName,
              vehicleModel: widget.ride.vehicle.modelName,
              peerPhone: widget.ride.driverPhone,
              peerRole: 'Driver',
              peerId: widget.ride.driverId,
            ),
          ),
        );
      } else {
        final err =
            ref.read(bookingNotifierProvider).errorMessage ?? 'Booking failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(err),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final totalFare = widget.ride.farePerSeat * _seats;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Title & Driver bar
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFFF7ED),
                child: Text(
                  widget.ride.driverName.isNotEmpty
                      ? widget.ride.driverName[0].toUpperCase()
                      : 'D',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEA580C),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.ride.driverName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 14, color: Color(0xFF0284C7)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.ride.driverRating.toStringAsFixed(1)} • ${widget.ride.driverDept}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 6),
                        Text('•', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.ride.vehicle.modelName,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatBdt(widget.ride.farePerSeat),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Text('/ seat', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. Uber-style Route Card (Green dot -> Stem -> Dark Square)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 3),
                        Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                        Container(width: 2, height: 26, color: const Color(0xFFCBD5E1)),
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0F172A))),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.ride.originName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedDropoffPoint ?? widget.ride.destinationName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (widget.ride.destinationChoices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose Your Specific Drop-off Stop:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: {
                        widget.ride.destinationName,
                        ...widget.ride.destinationChoices,
                      }.map((choice) {
                        final isSelected = (_selectedDropoffPoint ?? widget.ride.destinationName) == choice;
                        return ChoiceChip(
                          label: Text(choice),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedDropoffPoint = choice);
                          },
                          selectedColor: const Color(0xFF0F172A),
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Trip Metadata Strip (ETA + Distance + Seats remaining)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(Icons.access_time, '${widget.ride.durationMinutes} min', 'Est. Time'),
                Container(width: 1, height: 22, color: const Color(0xFFCBD5E1)),
                _buildInfoChip(Icons.straighten, '${widget.ride.distanceKm.toStringAsFixed(1)} km', 'Distance'),
                Container(width: 1, height: 22, color: const Color(0xFFCBD5E1)),
                _buildInfoChip(Icons.two_wheeler, '${widget.ride.availableSeats} open', 'Seats Left'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 5. Seat Selector Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Number of Seats', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  Text('Moto accommodates up to 2 riders', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    _stepButton(
                      Icons.remove,
                      _seats > 1 ? () => setState(() => _seats--) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_seats',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                    ),
                    _stepButton(
                      Icons.add,
                      _seats < widget.ride.availableSeats ? () => setState(() => _seats++) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 6. Total Cost Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Fare', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                Text(
                  CurrencyFormatter.formatBdt(totalFare),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 7. Full-width Uber Black Confirm Button
          ElevatedButton(
            onPressed: bookingState.isLoading ? null : _confirmBooking,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: bookingState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Text(
                        'Book Ride & Message Rider • ${CurrencyFormatter.formatBdt(totalFare)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            '💬 Booking opens direct chat with ${widget.ride.driverName} to agree on meetup point & fare before starting trip.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF475569)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF0F172A))),
        Text(label, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap != null ? Colors.white : const Color(0xFFE2E8F0),
          shape: BoxShape.circle,
          boxShadow: onTap != null
              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
