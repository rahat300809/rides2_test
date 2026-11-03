import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/shared_sync_rides_repository.dart';

final ridesRepositoryProvider = Provider<RidesRepository>((ref) {
  final prefs = ref.watch(preferencesProvider);
  return SharedSyncRidesRepository(preferences: prefs);
});

final departingSoonRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  final all = await repo.getDepartingSoonRides();
  final currentUser = ref.watch(authNotifierProvider).user;
  if (currentUser == null) return all;
  return all.where((r) =>
    r.driverId != currentUser.id &&
    r.driverId != currentUser.studentId &&
    (currentUser.phone.isEmpty || r.driverPhone != currentUser.phone)
  ).toList();
});

final departingSoonRidesStreamProvider = StreamProvider<List<RideModel>>((ref) {
  final repo = ref.watch(ridesRepositoryProvider);
  final currentUser = ref.watch(authNotifierProvider).user;
  return repo.watchDepartingSoonRides().map((list) {
    if (currentUser == null) return list;
    return list.where((r) =>
      r.driverId != currentUser.id &&
      r.driverId != currentUser.studentId &&
      (currentUser.phone.isEmpty || r.driverPhone != currentUser.phone)
    ).toList();
  });
});

class RideSearchFilterState {
  final String pickupQuery;
  final String dropoffQuery;
  final String generalSearchQuery;
  final bool isAllRidesMode;
  final DateTime? departureTime;
  final int seatsNeeded;
  final VehicleType? vehicleType;
  final bool verifiedOnly;
  final bool femaleOnly;
  final bool sortByLowestPrice;
  final bool leavingSoon;

  const RideSearchFilterState({
    this.pickupQuery = '',
    this.dropoffQuery = '',
    this.generalSearchQuery = '',
    this.isAllRidesMode = true,
    this.departureTime,
    this.seatsNeeded = 1,
    this.vehicleType,
    this.verifiedOnly = false,
    this.femaleOnly = false,
    this.sortByLowestPrice = false,
    this.leavingSoon = false,
  });

  RideSearchFilterState copyWith({
    String? pickupQuery,
    String? dropoffQuery,
    String? generalSearchQuery,
    bool? isAllRidesMode,
    DateTime? departureTime,
    int? seatsNeeded,
    VehicleType? vehicleType,
    bool? verifiedOnly,
    bool? femaleOnly,
    bool? sortByLowestPrice,
    bool? leavingSoon,
    bool clearVehicleType = false,
  }) {
    return RideSearchFilterState(
      pickupQuery: pickupQuery ?? this.pickupQuery,
      dropoffQuery: dropoffQuery ?? this.dropoffQuery,
      generalSearchQuery: generalSearchQuery ?? this.generalSearchQuery,
      isAllRidesMode: isAllRidesMode ?? this.isAllRidesMode,
      departureTime: departureTime ?? this.departureTime,
      seatsNeeded: seatsNeeded ?? this.seatsNeeded,
      vehicleType: clearVehicleType ? null : (vehicleType ?? this.vehicleType),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      femaleOnly: femaleOnly ?? this.femaleOnly,
      sortByLowestPrice: sortByLowestPrice ?? this.sortByLowestPrice,
      leavingSoon: leavingSoon ?? this.leavingSoon,
    );
  }
}

class RideSearchNotifier extends StateNotifier<RideSearchFilterState> {
  RideSearchNotifier() : super(const RideSearchFilterState());

  void setGeneralSearch(String query) => state = state.copyWith(generalSearchQuery: query);
  void setPickup(String pickup) => state = state.copyWith(pickupQuery: pickup);
  void setDropoff(String dropoff) => state = state.copyWith(dropoffQuery: dropoff);
  void setAllRidesMode(bool isAll) => state = state.copyWith(isAllRidesMode: isAll);

  void swapLocations() {
    final oldPickup = state.pickupQuery;
    state = state.copyWith(
      pickupQuery: state.dropoffQuery,
      dropoffQuery: oldPickup,
    );
  }

  void setSeatsNeeded(int seats) => state = state.copyWith(seatsNeeded: seats);

  void toggleVehicleType(VehicleType type) {
    if (state.vehicleType == type) {
      state = state.copyWith(clearVehicleType: true);
    } else {
      state = state.copyWith(vehicleType: type);
    }
  }

  void toggleFemaleOnly() => state = state.copyWith(femaleOnly: !state.femaleOnly);
  void toggleVerifiedOnly() => state = state.copyWith(verifiedOnly: !state.verifiedOnly);
  void toggleLowestPrice() => state = state.copyWith(sortByLowestPrice: !state.sortByLowestPrice);

  void clearFilters() {
    state = const RideSearchFilterState(
      pickupQuery: '',
      dropoffQuery: '',
      generalSearchQuery: '',
      isAllRidesMode: true,
    );
  }
}

final rideSearchFilterProvider = StateNotifierProvider<RideSearchNotifier, RideSearchFilterState>((ref) {
  return RideSearchNotifier();
});

String _normIdToken(String raw) {
  return raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
}

Set<String> _userIdentityTokens(dynamic currentUser) {
  final tokens = <String>{};
  if (currentUser == null) return tokens;
  final uId = (currentUser.id ?? '').toString().trim();
  final uStdId = (currentUser.studentId ?? '').toString().trim();
  final uPhone = (currentUser.phone ?? '').toString().replaceAll(RegExp(r'\D'), '');
  final uEmail = (currentUser.email ?? '').toString().trim().toLowerCase();
  for (final v in [uId, uStdId, uEmail]) {
    if (v.isEmpty) continue;
    tokens.add(v.toLowerCase());
    final clean = _normIdToken(v);
    if (clean.isNotEmpty) {
      tokens.add(clean);
      if (clean.startsWith('usr')) tokens.add(clean.substring(3));
    }
  }
  if (uPhone.length >= 8) {
    tokens.add(uPhone);
    tokens.add(uPhone.length > 10 ? uPhone.substring(uPhone.length - 10) : uPhone);
  }
  return tokens;
}

bool _tokensOverlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return false;
  return a.intersection(b).isNotEmpty;
}

/// Helper to detect if a ride was posted by the current user
bool isCurrentUserRide(RideModel r, dynamic currentUser) {
  if (currentUser == null) return false;
  final userTokens = _userIdentityTokens(currentUser);
  final driverTokens = <String>{
    r.driverId.trim().toLowerCase(),
    _normIdToken(r.driverId),
  };
  final dClean = _normIdToken(r.driverId);
  if (dClean.startsWith('usr') && dClean.length > 3) {
    driverTokens.add(dClean.substring(3));
  }
  final dPhone = (r.driverPhone ?? '').replaceAll(RegExp(r'\D'), '');
  if (dPhone.length >= 8) {
    driverTokens.add(dPhone);
    driverTokens.add(dPhone.length > 10 ? dPhone.substring(dPhone.length - 10) : dPhone);
  }
  if (_tokensOverlap(userTokens, driverTokens)) return true;

  final uName = (currentUser.name ?? '').toString().trim().toLowerCase();
  final dName = r.driverName.trim().toLowerCase();
  if (uName.isNotEmpty && dName.isNotEmpty && uName == dName && !uName.contains('student') && dPhone.isEmpty) {
    return true;
  }
  return false;
}

/// Helper to detect if a passenger request was posted by the current user
bool isCurrentUserPassengerRequest(dynamic e, dynamic currentUser) {
  if (currentUser == null) return false;
  final userTokens = _userIdentityTokens(currentUser);

  String pId = '';
  String pPhone = '';
  String pName = '';
  if (e is Map) {
    pId = (e['passengerId'] ?? e['passenger_id'] ?? '').toString().trim();
    pPhone = (e['passengerPhone'] ?? e['passenger_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    pName = (e['passengerName'] ?? e['passenger_name'] ?? '').toString().trim().toLowerCase();
  } else {
    try {
      pId = (e.passengerId ?? '').toString().trim();
      pPhone = (e.passengerPhone ?? '').toString().replaceAll(RegExp(r'\D'), '');
      pName = (e.passengerName ?? '').toString().trim().toLowerCase();
    } catch (_) {}
  }

  final passengerTokens = <String>{
    pId.toLowerCase(),
    _normIdToken(pId),
  };
  final pClean = _normIdToken(pId);
  if (pClean.startsWith('usr') && pClean.length > 3) {
    passengerTokens.add(pClean.substring(3));
  }
  if (pPhone.length >= 8) {
    passengerTokens.add(pPhone);
    passengerTokens.add(pPhone.length > 10 ? pPhone.substring(pPhone.length - 10) : pPhone);
  }
  if (_tokensOverlap(userTokens, passengerTokens)) return true;

  final uName = (currentUser.name ?? '').toString().trim().toLowerCase();
  if (uName.isNotEmpty && pName.isNotEmpty && uName == pName && !uName.contains('student') && pPhone.isEmpty) {
    return true;
  }
  return false;
}

final allSystemRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.getAllAvailableRides();
});

final allAvailableRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final all = await ref.watch(allSystemRidesProvider.future);
  final currentUser = ref.watch(authNotifierProvider).user;
  final now = DateTime.now();

  return all.where((r) {
    // Must be published and open
    if (r.status != RideStatus.published) return false;
    // Must have available seats remaining
    if (r.availableSeats <= 0) return false;
    // Must not be expired past departure time
    // Allow a 60-minute grace window past departure time so Leaving Now and active rides stay visible
    if (!r.departureTime.isAfter(now.subtract(const Duration(minutes: 60)))) return false;
    // Rider shouldn't see their own posted rides in the available rides feed
    if (currentUser != null && isCurrentUserRide(r, currentUser)) return false;
    return true;
  }).toList();
});

final myPostedRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  final currentUser = ref.watch(authNotifierProvider).user;
  if (currentUser == null) return [];
  final allSystem = await ref.watch(allSystemRidesProvider.future);
  final fromSystem = allSystem.where((r) => isCurrentUserRide(r, currentUser)).toList();
  try {
    final fromApi = await repo.getMyOfferedRides(currentUser.id);
    final map = <String, RideModel>{};
    for (final r in fromSystem) {
      map[r.id] = r;
    }
    for (final r in fromApi) {
      map[r.id] = r;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.departureTime.compareTo(a.departureTime));
    return list;
  } catch (_) {
    return fromSystem;
  }
});

final searchRidesResultsProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  final filter = ref.watch(rideSearchFilterProvider);
  final currentUser = ref.watch(authNotifierProvider).user;

  final results = await repo.searchRides(
    pickupQuery: filter.isAllRidesMode ? null : (filter.pickupQuery.isEmpty ? null : filter.pickupQuery),
    dropoffQuery: filter.isAllRidesMode ? null : (filter.dropoffQuery.isEmpty ? null : filter.dropoffQuery),
    generalQuery: filter.generalSearchQuery.isEmpty ? null : filter.generalSearchQuery,
    departureTime: filter.departureTime,
    seatsNeeded: filter.seatsNeeded,
    vehicleType: filter.vehicleType,
    femaleOnly: filter.femaleOnly,
    verifiedOnly: filter.verifiedOnly,
    sortByLowestPrice: filter.sortByLowestPrice,
  );

  if (currentUser == null) return results;
  return results.where((r) => !isCurrentUserRide(r, currentUser)).toList();
});

final allPassengerRequestsProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.getPassengerRequests(status: 'all');
});

final myPassengerRequestsProvider = FutureProvider<List<dynamic>>((ref) async {
  final all = await ref.watch(allPassengerRequestsProvider.future);
  final currentUser = ref.watch(authNotifierProvider).user;
  if (currentUser == null) return [];
  return all.where((e) => isCurrentUserPassengerRequest(e, currentUser)).toList();
});

final passengerRequestsProvider = FutureProvider<List<dynamic>>((ref) async {
  final all = await ref.watch(allPassengerRequestsProvider.future);
  final currentUser = ref.watch(authNotifierProvider).user;
  if (currentUser == null) return all;
  // Requester shouldn't see their own requests in the public request feed!
  return all.where((e) => !isCurrentUserPassengerRequest(e, currentUser)).toList();
});

final completedRidesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.getCompletedRides();
});
