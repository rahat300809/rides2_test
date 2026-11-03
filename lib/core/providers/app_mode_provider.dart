import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode {
  all,        // Default: Full unified campus experience
  passenger,  // Passenger usage: Find rides, request seats, student commute
  rider,      // Rider usage: Offer bike rides, accept student requests, driver tools
}

extension AppModeX on AppMode {
  bool get isAll => this == AppMode.all;
  bool get isPassenger => this == AppMode.passenger;
  bool get isRider => this == AppMode.rider;
  bool get showRiderFeatures => this == AppMode.all || this == AppMode.rider;
  bool get showPassengerFeatures => this == AppMode.all || this == AppMode.passenger;

  String get label {
    switch (this) {
      case AppMode.all:
        return 'All';
      case AppMode.passenger:
        return 'Passenger';
      case AppMode.rider:
        return 'Rider';
    }
  }

  String get description {
    switch (this) {
      case AppMode.all:
        return 'Default • Both Rider & Passenger tools active';
      case AppMode.passenger:
        return 'Passenger Mode • Finding rides & seat requests';
      case AppMode.rider:
        return 'Rider Mode • Offering bike rides & passenger pickups';
    }
  }
}

class AppModeNotifier extends StateNotifier<AppMode> {
  static const String _prefKey = 'diu_app_active_mode';

  AppModeNotifier() : super(AppMode.passenger) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'rider') {
        state = AppMode.rider;
      } else {
        state = AppMode.passenger;
      }
    } catch (_) {}
  }

  Future<void> setMode(AppMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      String val = 'all';
      if (mode == AppMode.passenger) val = 'passenger';
      if (mode == AppMode.rider) val = 'rider';
      await prefs.setString(_prefKey, val);
    } catch (_) {}
  }
}

final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) {
  return AppModeNotifier();
});
