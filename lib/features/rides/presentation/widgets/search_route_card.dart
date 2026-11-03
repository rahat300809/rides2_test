import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/map/presentation/widgets/location_autocomplete_input.dart';

class SearchRouteCard extends StatefulWidget {
  final String pickup;
  final String dropoff;
  final int seats;
  final DateTime? departureTime;
  final Function(String val) onPickupChanged;
  final Function(String val) onDropoffChanged;
  final VoidCallback onSwap;
  final VoidCallback onGpsTap;
  final Function(int seats) onSeatsChanged;
  final VoidCallback onSelectTime;

  const SearchRouteCard({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.seats,
    this.departureTime,
    required this.onPickupChanged,
    required this.onDropoffChanged,
    required this.onSwap,
    required this.onGpsTap,
    required this.onSeatsChanged,
    required this.onSelectTime,
  });

  @override
  State<SearchRouteCard> createState() => _SearchRouteCardState();
}

class _SearchRouteCardState extends State<SearchRouteCard> with SingleTickerProviderStateMixin {
  late TextEditingController _pickupController;
  late TextEditingController _dropoffController;
  late AnimationController _swapAnimController;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(text: widget.pickup);
    _dropoffController = TextEditingController(text: widget.dropoff);
    _swapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(covariant SearchRouteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pickup != _pickupController.text) {
      _pickupController.text = widget.pickup;
    }
    if (widget.dropoff != _dropoffController.text) {
      _dropoffController.text = widget.dropoff;
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _swapAnimController.dispose();
    super.dispose();
  }

  void _triggerSwap() {
    _swapAnimController.forward(from: 0.0);
    widget.onSwap();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Inputs row with route dot indicator
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Vertical Route Indicator
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 38,
                        color: AppColors.outlineVariant.withOpacity(0.6),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Pickup & Dropoff Inputs with Google API Autocomplete & Map Picker
                  Expanded(
                    child: Column(
                      children: [
                        LocationAutocompleteInput(
                          controller: _pickupController,
                          hintText: 'Choose campus pickup point',
                          labelText: 'From (Pickup)',
                          prefixIcon: Icons.trip_origin,
                          prefixColor: AppColors.primary,
                          onChanged: widget.onPickupChanged,
                          onLocationSelected: (result) {
                            _pickupController.text = result.title;
                            widget.onPickupChanged(result.title);
                          },
                          onGpsTap: widget.onGpsTap,
                        ),
                        const SizedBox(height: 8),
                        LocationAutocompleteInput(
                          controller: _dropoffController,
                          hintText: 'e.g. Motijheel, Mirpur 10, Uttara...',
                          labelText: 'To (Destination)',
                          prefixIcon: Icons.location_on,
                          prefixColor: AppColors.secondary,
                          onChanged: widget.onDropoffChanged,
                          onLocationSelected: (result) {
                            _dropoffController.text = result.title;
                            widget.onDropoffChanged(result.title);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Time & Passenger Selector row
              Row(
                children: [
                  // Time Selector Pill
                  Expanded(
                    child: InkWell(
                      onTap: widget.onSelectTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Departure',
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      'Today, 10:30 AM',
                                      style: AppTypography.labelLg.copyWith(fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.expand_more, size: 16, color: AppColors.outline),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Fixed 1 Moto Seat Pill
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                '1 Moto Seat',
                                style: AppTypography.labelLg.copyWith(fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Fixed',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Floating Swap Location Button on the right
          Positioned(
            right: 48,
            top: 36,
            child: RotationTransition(
              turns: _swapAnimController,
              child: InkWell(
                onTap: _triggerSwap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.swap_vert,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
