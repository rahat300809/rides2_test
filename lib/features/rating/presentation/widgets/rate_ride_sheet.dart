import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

class RateRideSheet extends StatefulWidget {
  final String rideId;
  final String driverName;
  final Function(int rating, String feedback, List<String> tags) onSubmit;

  const RateRideSheet({
    super.key,
    required this.rideId,
    required this.driverName,
    required this.onSubmit,
  });

  static Future<void> show({
    required BuildContext context,
    required String rideId,
    required String driverName,
    required Function(int rating, String feedback, List<String> tags) onSubmit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateRideSheet(
        rideId: rideId,
        driverName: driverName,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<RateRideSheet> createState() => _RateRideSheetState();
}

class _RateRideSheetState extends State<RateRideSheet> {
  int _rating = 5;
  final _commentController = TextEditingController();
  final Set<String> _selectedTags = {'Punctual', 'Safe Driving'};

  final List<String> _availableTags = [
    'Punctual',
    'Safe Driving',
    'Friendly Peer',
    'Clean Vehicle',
    'Good Route',
    'Helped with Luggage',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Rate Your Commute',
            style: AppTypography.headlineMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'How was your ride with ${widget.driverName}?',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // 5-Star Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return IconButton(
                iconSize: 36,
                icon: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  color: AppColors.ratingStar,
                ),
                onPressed: () {
                  setState(() {
                    _rating = starIndex;
                  });
                },
              );
            }),
          ),
          const SizedBox(height: 16),

          // Tags
          Text('Compliments', style: AppTypography.labelMd),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableTags.map((tag) {
              final isSelected = _selectedTags.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: isSelected,
                selectedColor: AppColors.primaryFixed,
                checkmarkColor: AppColors.onPrimaryFixed,
                labelStyle: AppTypography.labelSm.copyWith(
                  color: isSelected ? AppColors.onPrimaryFixed : AppColors.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: AppColors.surfaceContainerLow,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Optional comment
          TextField(
            controller: _commentController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Share optional peer review...',
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onSubmit(
                _rating,
                _commentController.text.trim(),
                _selectedTags.toList(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Submit Peer Review'),
          ),
        ],
      ),
    );
  }
}
