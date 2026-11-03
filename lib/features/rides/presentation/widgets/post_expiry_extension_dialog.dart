import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class PostExpiryExtensionDialog extends ConsumerStatefulWidget {
  final String postId;
  final String postType; // 'ride' or 'passenger_request'
  final String title;
  final String? scheduledTimeStr;
  final int initialMinutesRemaining;

  const PostExpiryExtensionDialog({
    super.key,
    required this.postId,
    required this.postType,
    required this.title,
    this.scheduledTimeStr,
    this.initialMinutesRemaining = 30,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    required String postType,
    required String title,
    String? scheduledTimeStr,
    int initialMinutesRemaining = 30,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PostExpiryExtensionDialog(
        postId: postId,
        postType: postType,
        title: title,
        scheduledTimeStr: scheduledTimeStr,
        initialMinutesRemaining: initialMinutesRemaining,
      ),
    );
  }

  @override
  ConsumerState<PostExpiryExtensionDialog> createState() =>
      _PostExpiryExtensionDialogState();
}

class _PostExpiryExtensionDialogState
    extends ConsumerState<PostExpiryExtensionDialog> {
  late int _secondsRemaining;
  Timer? _countdownTimer;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.initialMinutesRemaining * 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('30 minutes passed. Post automatically expired and removed.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown() {
    final mins = _secondsRemaining ~/ 60;
    final secs = _secondsRemaining % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _extendTime(int additionalMinutes) async {
    setState(() => _isSubmitting = true);
    final repo = ref.read(ridesRepositoryProvider);
    final newTime = DateTime.now().add(Duration(minutes: additionalMinutes));
    final newTimeFormatted = DateTimeUtils.formatTime(newTime);

    try {
      if (widget.postType == 'ride') {
        await repo.extendRideTime(
          widget.postId,
          minutes: additionalMinutes,
          newDepartureTime: newTime,
        );
      } else {
        await repo.extendPassengerRequestTime(
          widget.postId,
          minutes: additionalMinutes,
          newRequestedTime: newTime,
        );
      }

      ref.invalidate(allAvailableRidesProvider);
      ref.invalidate(departingSoonRidesProvider);
      ref.invalidate(passengerRequestsProvider);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Extended by $additionalMinutes mins! New scheduled time: $newTimeFormatted',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to extend time: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _cancelAndRemovePost() async {
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(ridesRepositoryProvider);
      if (widget.postType == 'ride') {
        await repo.deleteRide(widget.postId);
      } else {
        await repo.deletePassengerRequest(widget.postId);
      }

      ref.invalidate(allAvailableRidesProvider);
      ref.invalidate(departingSoonRidesProvider);
      ref.invalidate(passengerRequestsProvider);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post closed and removed.'),
            backgroundColor: Color(0xFF6B7280),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error closing post: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRide = widget.postType == 'ride';
    final roleLabel = isRide ? 'Rider (Bike Offer)' : 'Passenger (Ride Request)';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Icon(
              Icons.schedule,
              color: Color(0xFFDC2626),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scheduled Time Reached',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE65100),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.route, size: 16, color: Color(0xFFB45309)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.scheduledTimeStr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Original Scheduled Time: ${widget.scheduledTimeStr}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Countdown box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto-deletion Countdown:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        Text(
                          _formatCountdown(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDC2626),
                            fontFeatures: [],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'If you are delayed, extend your post below. If not extended within 30 minutes, your post will be automatically deleted from the app and web.',
              style: TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.4),
            ),
            const SizedBox(height: 14),

            const Text(
              'Select Extension:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),

            // Quick Extension Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : () => _extendTime(15),
                    child: const Text(
                      '+15 mins',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : () => _extendTime(30),
                    child: const Text(
                      '+30 mins',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : () => _extendTime(60),
                    child: const Text(
                      '+1 hour',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Cancel / Finished button
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9CA3AF),
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text(
                  'Trip done / Cancel post now',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _isSubmitting ? null : _cancelAndRemovePost,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
