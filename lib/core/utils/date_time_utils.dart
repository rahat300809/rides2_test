import 'package:intl/intl.dart';

class DateTimeUtils {
  DateTimeUtils._();

  static String formatTime(DateTime time) {
    // Ensure display in BD local time (UTC+6)
    final bdTime = time.isUtc ? time.add(const Duration(hours: 6)) : time.toLocal();
    return DateFormat('hh:mm a').format(bdTime);
  }

  /// Formats departure time in Bangladesh Standard Time (BST, GMT+6).
  /// Shows "Today, 12:06 PM" or "Tomorrow, 08:30 AM" or "d MMM, hh:mm a"
  static String formatDepartureDateTime(DateTime dt) {
    // Convert to Bangladesh local time (UTC+6)
    final bdTime = dt.isUtc ? dt.add(const Duration(hours: 6)) : dt.toLocal();
    final nowBd = DateTime.now().toUtc().add(const Duration(hours: 6));

    final timeStr = DateFormat('hh:mm a').format(bdTime);

    final isToday = bdTime.year == nowBd.year &&
        bdTime.month == nowBd.month &&
        bdTime.day == nowBd.day;

    final tomorrow = nowBd.add(const Duration(days: 1));
    final isTomorrow = bdTime.year == tomorrow.year &&
        bdTime.month == tomorrow.month &&
        bdTime.day == tomorrow.day;

    if (isToday) {
      return 'Today, $timeStr';
    } else if (isTomorrow) {
      return 'Tomorrow, $timeStr';
    } else {
      return '${DateFormat('d MMM').format(bdTime)}, $timeStr';
    }
  }

  static String formatDate(DateTime date) {
    return DateFormat('EEE, d MMM').format(date);
  }

  static String formatFullDateTime(DateTime dt) {
    return DateFormat('d MMM yyyy, hh:mm a').format(dt);
  }

  static String formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final difference = dt.difference(now);

    if (difference.inMinutes <= 0) {
      return 'Departed';
    } else if (difference.inMinutes < 60) {
      return 'Leaving in ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'Leaving in ${difference.inHours}h';
    } else {
      return formatDate(dt);
    }
  }

  static String formatPostingTime(DateTime? dt) {
    if (dt == null) return 'Posted recently';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.isNegative || diff.inSeconds < 45) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24 && dt.day == now.day) {
      return 'Today, ${formatTime(dt)}';
    } else if (diff.inHours < 48 && dt.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday, ${formatTime(dt)}';
    } else {
      return DateFormat('d MMM, hh:mm a').format(dt);
    }
  }
}
