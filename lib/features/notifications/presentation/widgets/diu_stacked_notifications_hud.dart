import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/notifications/data/models/notification_model.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';

/// Interactive Stacked In-App Notification HUD
/// Displays unseen notifications in a realistic stacked card deck.
/// Users can dismiss cards individually, tap to take action, or view all.
class DiuStackedNotificationsHud extends ConsumerStatefulWidget {
  final Function(NotificationModel notice)? onNoticeTap;

  const DiuStackedNotificationsHud({
    super.key,
    this.onNoticeTap,
  });

  @override
  ConsumerState<DiuStackedNotificationsHud> createState() =>
      _DiuStackedNotificationsHudState();
}

class _DiuStackedNotificationsHudState
    extends ConsumerState<DiuStackedNotificationsHud>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unreadList = notifications.where((n) => !n.isRead).toList();

    if (unreadList.isEmpty) {
      return const SizedBox.shrink();
    }

    final topNotice = unreadList.first;
    final remainingCount = unreadList.length;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Layer 3 (Bottom Stack Card)
            if (remainingCount >= 3)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFED7AA),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),

            // Layer 2 (Middle Stack Card)
            if (remainingCount >= 2)
              Positioned(
                top: 4,
                left: 8,
                right: 8,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Card (Active interactive notification card)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE65100).withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Row: Badge Counter + Title + Dismiss
                  Row(
                    children: [
                      // Type Icon
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIconForType(topNotice.type),
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Title & Badge
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                topNotice.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (remainingCount > 1) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '+${remainingCount - 1} in stack',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Dismiss Single
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Dismiss',
                        onPressed: () {
                          ref
                              .read(notificationsProvider.notifier)
                              .markAsRead(topNotice.id);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Notification Body
                  InkWell(
                    onTap: () {
                      if (widget.onNoticeTap != null) {
                        widget.onNoticeTap!(topNotice);
                      } else {
                        ref
                            .read(notificationsProvider.notifier)
                            .markAsRead(topNotice.id);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 30),
                      child: Text(
                        topNotice.body,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  // Actions row: View All & Clear All
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            );
                          },
                          child: const Row(
                            children: [
                              Text(
                                'View Notification Stack',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 9,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        if (remainingCount > 1)
                          InkWell(
                            onTap: () {
                              ref
                                  .read(notificationsProvider.notifier)
                                  .markAllAsRead();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Clear All',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
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

  IconData _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.safetyAlert:
        return Icons.campaign;
      case NotificationType.rideRequest:
        return Icons.person_add;
      case NotificationType.rideAccepted:
        return Icons.check_circle;
      case NotificationType.rideRejected:
        return Icons.cancel;
      case NotificationType.rideCancelled:
        return Icons.event_busy;
      case NotificationType.driverArriving:
        return Icons.two_wheeler;
      case NotificationType.rideStarted:
        return Icons.directions_bike;
      case NotificationType.rideCompleted:
        return Icons.flag;
      case NotificationType.chatMessage:
        return Icons.chat_bubble_outline;
      case NotificationType.ridePublished:
        return Icons.add_road;
    }
  }
}
