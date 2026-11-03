import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

/// Guard to prevent switching app modes (Biker ↔ Passenger) if there are active
/// uncompleted/unexpired rides or ride requests.
class AppModeSwitchGuard {
  AppModeSwitchGuard._();

  static Future<bool> canSwitchMode(
    BuildContext context,
    WidgetRef ref,
    AppMode targetMode,
  ) async {
    final currentMode = ref.read(appModeProvider);
    if (currentMode == targetMode) return true;

    final user = ref.read(authNotifierProvider).user;
    final now = DateTime.now();

    // 1. Switching to Passenger mode:
    // Rider must NOT have an active offered ride!
    if (targetMode == AppMode.passenger) {
      final myRides = ref.read(myPostedRidesProvider).valueOrNull ?? [];
      final activeRides = myRides.where((r) {
        final isPublished = r.status == RideStatus.published || r.status == RideStatus.active;
        // 15-minute grace period past departure time
        final isNotExpired = r.departureTime.isAfter(now.subtract(const Duration(minutes: 15)));
        return isPublished && isNotExpired;
      }).toList();

      if (activeRides.isNotEmpty) {
        if (!context.mounted) return false;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active Ride Posted',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: const Text(
              'আপনার একটি শেয়ার্ড রাইড পোস্ট চালু রয়েছে (Biker Mode)।\n\nপ্যাসেঞ্জার মোডে যেতে হলে অনুগ্রহ করে রাইডটি কমপ্লিট করুন অথবা "My Status" থেকে রাইড পোস্টটি ডিলিট/ক্যান্সেল করুন।',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF334155)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'ঠিক আছে',
                  style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        return false;
      }
    }

    // 2. Switching to Rider mode:
    // Passenger must NOT have an active pending ride request!
    if (targetMode == AppMode.rider && user != null) {
      final allRequests = ref.read(allPassengerRequestsProvider).valueOrNull ?? [];
      final myActiveRequests = allRequests.where((req) {
        final isMine = isCurrentUserPassengerRequest(req, user);
        final isMap = req is Map<String, dynamic>;
        final status = (isMap ? req['status'] : req.status)?.toString().toLowerCase() ?? '';
        final isOpen = status == 'open' || status == 'matched' || status == 'pending';

        DateTime? reqTime;
        try {
          final tStr = isMap ? req['requestedTime'] : req.requestedTime;
          if (tStr != null) reqTime = DateTime.tryParse(tStr.toString());
        } catch (_) {}
        if (reqTime == null) {
          try {
            final cStr = isMap ? req['createdAt'] : req.createdAt;
            if (cStr != null) reqTime = DateTime.tryParse(cStr.toString());
          } catch (_) {}
        }

        final isNotExpired = reqTime == null || reqTime.isAfter(now.subtract(const Duration(minutes: 15)));
        return isMine && isOpen && isNotExpired;
      }).toList();

      if (myActiveRequests.isNotEmpty) {
        if (!context.mounted) return false;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.hail_rounded, color: Color(0xFF10B981), size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Active Request Pending',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: const Text(
              'আপনার একটি রাইড রিকোয়েস্ট পেন্ডিং রয়েছে (Passenger Mode)।\n\nরাইডার মোডে সুইচ করার আগে রিকোয়েস্টটি ডিলিট অথবা ক্যান্সেল করতে হবে।',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF334155)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'ঠিক আছে',
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        return false;
      }
    }

    return true;
  }
}

