import 'package:flutter/material.dart';
import 'package:diu_ride/features/auth/data/models/user_model.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

/// Prevents the same logged-in account from accepting its own
/// Student request or booking its own Biker offer after mode switch.
class SameAccountGuard {
  SameAccountGuard._();

  static bool isOwnPassengerRequest(dynamic request, UserModel? user) {
    if (user == null) return false;
    return isCurrentUserPassengerRequest(request, user);
  }

  static bool isOwnOfferedRide(RideModel ride, UserModel? user) {
    if (user == null) return false;
    return isCurrentUserRide(ride, user);
  }

  static void showBlockedSnackBar(
    BuildContext context, {
    required bool asOwnRequest,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFB45309),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          asOwnRequest
              ? 'This is your own student request. Switching to Biker mode cannot accept it — wait for another biker.'
              : 'This is your own biker offer. Switching to Student mode cannot book it — wait for another student.',
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Returns true if action was blocked (caller should return early).
  static bool blockOwnPassengerAccept(
    BuildContext context,
    UserModel? user,
    dynamic request,
  ) {
    if (!isOwnPassengerRequest(request, user)) return false;
    showBlockedSnackBar(context, asOwnRequest: true);
    return true;
  }

  /// Returns true if action was blocked (caller should return early).
  static bool blockOwnRideBook(
    BuildContext context,
    UserModel? user,
    RideModel ride,
  ) {
    if (!isOwnOfferedRide(ride, user)) return false;
    showBlockedSnackBar(context, asOwnRequest: false);
    return true;
  }
}
