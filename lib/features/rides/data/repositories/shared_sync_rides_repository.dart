import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/utils/h3_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/mock_rides_repository.dart';

class SharedSyncRidesRepository implements RidesRepository {
  final PreferencesService preferences;
  final MockRidesRepository _localFallback = MockRidesRepository();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  SharedSyncRidesRepository({required this.preferences});

  String get _apiBase => AppConfig.current.apiBaseUrl;

  @override
  Stream<List<RideModel>> watchDepartingSoonRides() {
    return Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => getDepartingSoonRides())
        .asBroadcastStream();
  }

  @override
  Future<List<RideModel>> getDepartingSoonRides() async {
    final all = await getAllAvailableRides();
    return all
        .where((r) => r.status == RideStatus.published && r.availableSeats > 0)
        .take(5)
        .toList();
  }

  @override
  Future<List<RideModel>> getAllAvailableRides() async {
    final now = DateTime.now();
    try {
      final response = await _dio.get('$_apiBase/rides');
      if (response.statusCode == 200 && response.data is List) {
        final list = <RideModel>[];
        for (final item in response.data as List) {
          try {
            final r = RideModel.fromJson(Map<String, dynamic>.from(item as Map));
            if (r.status == RideStatus.published &&
                r.availableSeats > 0 &&
                r.departureTime.isAfter(now.subtract(const Duration(minutes: 60)))) {
              list.add(r);
            }
          } catch (e) {
            debugPrint('Error parsing ride item: $e');
          }
        }
        
        // Cache to preferences
        try {
          final encoded = jsonEncode(list.map((r) => r.toJson()).toList());
          await preferences.saveSharedRides(encoded);
        } catch (_) {}

        return list;
      }
    } catch (e) {
      debugPrint('SharedSyncRidesRepository get rides note (using cache/local): $e');
    }

    // Try reading from PreferencesService cache
    final cached = preferences.getSharedRides();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        final cachedList = <RideModel>[];
        for (final item in decoded) {
          try {
            final r = RideModel.fromJson(Map<String, dynamic>.from(item as Map));
            if (r.status == RideStatus.published &&
                r.availableSeats > 0 &&
                r.departureTime.isAfter(now.subtract(const Duration(minutes: 60)))) {
              cachedList.add(r);
            }
          } catch (_) {}
        }
        return cachedList;
      } catch (_) {}
    }

    return [];
  }

  @override
  Future<List<RideModel>> searchRides({
    String? pickupQuery,
    String? dropoffQuery,
    String? generalQuery,
    DateTime? departureTime,
    int? seatsNeeded,
    VehicleType? vehicleType,
    bool femaleOnly = false,
    bool verifiedOnly = false,
    bool sortByLowestPrice = false,
  }) async {
    final all = await getAllAvailableRides();
    List<RideModel> results = List.from(all);

    results = results.where((r) => r.status != RideStatus.cancelled).toList();

    if (generalQuery != null && generalQuery.trim().isNotEmpty) {
      final g = generalQuery.trim().toLowerCase();
      final isAb4 = g.contains('ab4') || g.contains('ab 4') || g.contains('ab-4');
      results = results.where((r) {
        final ab4Match = isAb4 && (
          r.originName.toLowerCase().contains('academic building 4') ||
          (r.originSubtitle?.toLowerCase().contains('academic building 4') ?? false) ||
          r.destinationName.toLowerCase().contains('academic building 4') ||
          (r.destinationSubtitle?.toLowerCase().contains('academic building 4') ?? false)
        );
        final destChoicesMatch = r.destinationChoices.any((c) => c.toLowerCase().contains(g));
        return r.originName.toLowerCase().contains(g) ||
          (r.originSubtitle?.toLowerCase().contains(g) ?? false) ||
          r.destinationName.toLowerCase().contains(g) ||
          (r.destinationSubtitle?.toLowerCase().contains(g) ?? false) ||
          destChoicesMatch ||
          r.driverName.toLowerCase().contains(g) ||
          r.driverDept.toLowerCase().contains(g) ||
          r.routeCorridor.toLowerCase().contains(g) ||
          r.vehicle.modelName.toLowerCase().contains(g) ||
          ab4Match;
      }).toList();
    }

    if (pickupQuery != null && pickupQuery.trim().isNotEmpty) {
      final q = pickupQuery.trim().toLowerCase();
      results = results.where((r) =>
          r.originName.toLowerCase().contains(q) ||
          (r.originSubtitle?.toLowerCase().contains(q) ?? false)).toList();
    }

    if (dropoffQuery != null && dropoffQuery.trim().isNotEmpty) {
      final q = dropoffQuery.trim().toLowerCase();
      results = results.where((r) =>
          r.destinationName.toLowerCase().contains(q) ||
          (r.destinationSubtitle?.toLowerCase().contains(q) ?? false) ||
          r.destinationChoices.any((c) => c.toLowerCase().contains(q))).toList();
    }

    if (seatsNeeded != null && seatsNeeded > 1) {
      results = results.where((r) => r.availableSeats >= seatsNeeded).toList();
    }

    if (vehicleType != null) {
      results = results.where((r) => r.vehicle.type == vehicleType).toList();
    }

    if (femaleOnly) {
      results = results.where((r) => r.isFemaleOnly).toList();
    }

    if (sortByLowestPrice) {
      results.sort((a, b) => a.farePerSeat.compareTo(b.farePerSeat));
    }

    return results;
  }

  @override
  Future<RideModel?> getRideById(String id) async {
    final all = await getAllAvailableRides();
    try {
      return all.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RideModel> createRide({
    String? driverId,
    String? driverName,
    String? driverPhone,
    String? driverDepartment,
    required String originName,
    required double originLat,
    required double originLng,
    required String destinationName,
    required double destinationLat,
    required double destinationLng,
    String? waypointName,
    required DateTime departureTime,
    required VehicleModel vehicle,
    required int availableSeats,
    required double farePerSeat,
    required bool isFemaleOnly,
    List<String>? destinationChoices,
  }) async {
    final dist = H3Utils.calculateDistanceKm(originLat, originLng, destinationLat, destinationLng);
    final duration = H3Utils.estimateDurationMinutes(dist);

    final newRide = RideModel(
      id: 'ride_${const Uuid().v4().substring(0, 8)}',
      driverId: driverId ?? 'usr_driver_${DateTime.now().millisecondsSinceEpoch}',
      driverName: driverName ?? 'DIU Student Driver',
      driverPhotoUrl: null,
      driverDept: driverDepartment ?? 'CSE',
      driverRating: 4.95,
      driverRideCount: 1,
      originName: originName,
      originLat: originLat,
      originLng: originLng,
      destinationName: destinationName,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      waypointName: waypointName,
      departureTime: departureTime,
      farePerSeat: farePerSeat,
      totalSeats: availableSeats,
      availableSeats: availableSeats,
      isFemaleOnly: isFemaleOnly,
      destinationChoices: destinationChoices ?? const [],
      createdAt: DateTime.now(),
      status: RideStatus.published,
      vehicle: vehicle,
      h3OriginIndex: H3Utils.latLngToH3(originLat, originLng),
      h3DestinationIndex: H3Utils.latLngToH3(destinationLat, destinationLng),
      routeCorridor: 'Birulia - Ashulia Corridor',
      distanceKm: dist > 0 ? dist : 14.0,
      durationMinutes: duration,
    );

    // 1. Post to backend server
    try {
      await _dio.post(
        '$_apiBase/rides',
        data: newRide.toJson(),
      );
      debugPrint('Ride published to central backend: ${newRide.id}');
    } catch (e) {
      debugPrint('Note: Central backend post error: $e');
    }

    // 2. Cache in local preferences (bounded to 30 valid active rides)
    try {
      final now = DateTime.now();
      final currentList = await getAllAvailableRides();
      final updatedList = [
        newRide,
        ...currentList.where((r) => r.id != newRide.id && r.departureTime.isAfter(now.subtract(const Duration(minutes: 60))))
      ].take(30).toList();
      final encoded = jsonEncode(updatedList.map((r) => r.toJson()).toList());
      await preferences.saveSharedRides(encoded);
    } catch (_) {}

    return newRide;
  }

  @override
  Future<bool> extendRideTime(String rideId, {int minutes = 30, DateTime? newDepartureTime}) async {
    try {
      final newTime = newDepartureTime ?? DateTime.now().add(Duration(minutes: minutes));
      final newTimeStr = '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
      final res = await _dio.post('$_apiBase/rides/$rideId/extend-time', data: {
        'minutes': minutes,
        'newTime': newTimeStr,
        'newDepartureTime': newTime.toIso8601String(),
      });
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('extendRideTime error: $e');
      return false;
    }
  }

  @override
  Future<bool> extendPassengerRequestTime(String requestId, {int minutes = 30, DateTime? newRequestedTime}) async {
    try {
      final newTime = newRequestedTime ?? DateTime.now().add(Duration(minutes: minutes));
      final newTimeStr = '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
      final res = await _dio.post('$_apiBase/passenger-requests/$requestId/extend-time', data: {
        'minutes': minutes,
        'newTime': newTimeStr,
        'newRequestedTime': newTime.toIso8601String(),
      });
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('extendPassengerRequestTime error: $e');
      return false;
    }
  }

  @override
  Future<List<RideModel>> getMyOfferedRides(String driverId) async {
    try {
      final res = await _dio.get('$_apiBase/rides', queryParameters: {'driver_id': driverId});
      if (res.statusCode == 200 && res.data is List) {
        final list = (res.data as List)
            .map((json) => RideModel.fromJson(json as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    final all = await getAllAvailableRides();
    return all.where((r) => r.driverId == driverId).toList();
  }

  @override
  Future<bool> cancelOfferedRide(String rideId) async {
    // 1. Notify central backend
    try {
      await _dio.post('$_apiBase/rides/$rideId/cancel');
    } catch (_) {
      try {
        await _dio.post('$_apiBase/rides/cancel-session', data: {
          'rideId': rideId,
          'reason': 'Cancelled by driver',
        });
      } catch (_) {
        try {
          await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'cancelled'});
        } catch (_) {}
      }
    }

    // 2. Update local fallback
    await _localFallback.cancelOfferedRide(rideId);

    // 3. Update cached preferences
    try {
      final cached = preferences.getSharedRides();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == rideId || item['id']?.toString().contains(rideId) == true)) {
            item['status'] = 'cancelled';
          }
        }
        await preferences.saveSharedRides(jsonEncode(decoded));
      }
    } catch (_) {}

    return true;
  }

  @override
  Future<bool> deleteRide(String rideId) async {
    // 1. Immediately purge from local fallback and preferences cache
    try {
      await _localFallback.deleteRide(rideId);
      final cached = preferences.getSharedRides();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        final updated = decoded.where((item) {
          if (item is Map) {
            final id = item['id']?.toString() ?? '';
            return id != rideId && !id.contains(rideId);
          }
          return true;
        }).toList();
        await preferences.saveSharedRides(jsonEncode(updated));
      }
    } catch (_) {}

    // 2. Call backend DELETE endpoints
    try {
      await _dio.delete('$_apiBase/rides/$rideId');
      debugPrint('Ride deleted from central backend: $rideId');
    } catch (e) {
      try {
        await _dio.delete('$_apiBase/rides', queryParameters: {'id': rideId});
      } catch (_) {
        try {
          await _dio.post('$_apiBase/rides/$rideId/delete');
        } catch (_) {
          try {
            await _dio.post('$_apiBase/rides/delete', data: {'id': rideId});
          } catch (_) {}
        }
      }
    }

    return true;
  }

  @override
  Future<bool> startRide(String rideId, {double? startLat, double? startLng}) async {
    try {
      await _dio.post('$_apiBase/rides/$rideId/start', data: {
        'latitude': startLat,
        'longitude': startLng,
      });
    } catch (_) {
      try {
        await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'active'});
      } catch (_) {}
    }
    await _localFallback.startRide(rideId, startLat: startLat, startLng: startLng);

    // Sync status into cached preferences
    try {
      final cached = preferences.getSharedRides();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == rideId || item['id']?.toString().contains(rideId) == true)) {
            item['status'] = 'active';
            if (startLat != null) item['startLat'] = startLat;
            if (startLng != null) item['startLng'] = startLng;
          }
        }
        await preferences.saveSharedRides(jsonEncode(decoded));
      }
    } catch (_) {}

    return true;
  }

  @override
  Future<bool> completeRide(String rideId, {double? endLat, double? endLng}) async {
    try {
      await _dio.post('$_apiBase/rides/complete-session', data: {
        'rideId': rideId,
        'latitude': endLat,
        'longitude': endLng,
      });
    } catch (_) {
      try {
        await _dio.post('$_apiBase/rides/$rideId/complete', data: {
          'latitude': endLat,
          'longitude': endLng,
        });
      } catch (_) {
        try {
          await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'completed'});
        } catch (_) {}
      }
    }

    // 1. Mark completed in cached shared rides
    try {
      final cached = preferences.getSharedRides();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == rideId || item['id']?.toString().contains(rideId) == true)) {
            item['status'] = 'completed';
            if (endLat != null) item['endLat'] = endLat;
            if (endLng != null) item['endLng'] = endLng;
          }
        }
        await preferences.saveSharedRides(jsonEncode(decoded));
      }
    } catch (_) {}

    // 2. Mark any matching booking in cached bookings as completed
    try {
      final cachedB = preferences.getSharedBookings();
      if (cachedB != null && cachedB.isNotEmpty) {
        final decodedB = jsonDecode(cachedB) as List<dynamic>;
        for (final item in decodedB) {
          if (item is Map && (item['rideId'] == rideId || item['rideId']?.toString().contains(rideId) == true)) {
            item['status'] = 'completed';
          }
        }
        await preferences.saveSharedBookings(jsonEncode(decodedB));
      }
    } catch (_) {}

    await _localFallback.completeRide(rideId, endLat: endLat, endLng: endLng);
    return true;
  }

  @override
  Future<bool> shareLiveLocation({
    required String rideId,
    required String userId,
    required String userName,
    required String role,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _dio.post('$_apiBase/location/share', data: {
        'rideId': rideId,
        'userId': userId,
        'userName': userName,
        'role': role,
        'latitude': latitude,
        'longitude': longitude,
      });
      return true;
    } catch (e) {
      debugPrint('shareLiveLocation error: $e');
      return false;
    }
  }

  @override
  Future<void> updateRideSeats(String rideId, int seatsToDeduct) async {
    try {
      final ride = await getRideById(rideId);
      if (ride != null) {
        final newSeats = (ride.availableSeats - seatsToDeduct).clamp(0, ride.totalSeats);
        await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'availableSeats': newSeats});
      }
    } catch (_) {}
  }

  static final List<PassengerRequestModel> _defaultStudentRequests = [
    PassengerRequestModel(
      id: 'preq_seed_mirpur_1',
      passengerId: 'usr_student_shakib',
      passengerName: 'Shakib Ahmed',
      passengerPhone: '01711223344',
      passengerDept: 'CSE',
      pickup: 'DIU Campus (Daffodil Smart City)',
      dropoff: 'Mirpur 10 (Roundabout / Metro Station)',
      requestedTime: 'Today, 5:30 PM',
      proposedFare: 60.0,
      notes: 'Need a ride after lab class. Extra helmet preferred.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
    PassengerRequestModel(
      id: 'preq_seed_uttara_2',
      passengerId: 'usr_student_nafisa',
      passengerName: 'Nafisa Tabassum',
      passengerPhone: '01822334455',
      passengerDept: 'SWE',
      pickup: 'DIU Campus (Gate 1, Ashulia)',
      dropoff: 'Uttara Sector 7 (Rajlakshmi)',
      requestedTime: 'Today, 6:00 PM',
      proposedFare: 70.0,
      notes: 'Going to Uttara via Birulia-Baunia road.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
    PassengerRequestModel(
      id: 'preq_seed_dhanmondi_3',
      passengerId: 'usr_student_arafat',
      passengerName: 'Arafat Rahman',
      passengerPhone: '01933445566',
      passengerDept: 'BBA',
      pickup: 'DIU Campus (Main Building AB-4)',
      dropoff: 'Dhanmondi 27 (Sobhanbagh)',
      requestedTime: 'Today, 5:45 PM',
      proposedFare: 80.0,
      notes: 'Ready near fountain circle. Can split fuel fare.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
    PassengerRequestModel(
      id: 'preq_seed_ecb_4',
      passengerId: 'usr_student_tasnia',
      passengerName: 'Tasnia Farin',
      passengerPhone: '01744556677',
      passengerDept: 'EEE',
      pickup: 'DIU Campus (Permanent Campus)',
      dropoff: 'ECB Chattar (Matikata)',
      requestedTime: 'Today, 6:15 PM',
      proposedFare: 65.0,
      notes: 'Evening ride to Mirpur DOHS / ECB corridor.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
    PassengerRequestModel(
      id: 'preq_seed_farmgate_5',
      passengerId: 'usr_student_siyam',
      passengerName: 'Siyam Hossain',
      passengerPhone: '01655667788',
      passengerDept: 'CIS',
      pickup: 'DIU Campus (Ashulia Model Town)',
      dropoff: 'Farmgate (Ananda Cinema Hall)',
      requestedTime: 'Today, 5:15 PM',
      proposedFare: 90.0,
      notes: 'Going to Farmgate / Khamarbari direction.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
    PassengerRequestModel(
      id: 'preq_seed_savar_6',
      passengerId: 'usr_student_mim',
      passengerName: 'Mim Akter',
      passengerPhone: '01566778899',
      passengerDept: 'Pharmacy',
      pickup: 'DIU Campus (Daffodil Smart City)',
      dropoff: 'Savar (City Center / Thana Stand)',
      requestedTime: 'Today, 4:45 PM',
      proposedFare: 50.0,
      notes: 'Quick commute to Savar Bazar bus stand.',
      status: 'open',
      createdAt: DateTime.now().toIso8601String(),
    ),
  ];

  @override
  Future<List<PassengerRequestModel>> getPassengerRequests({String status = 'all'}) async {
    try {
      final res = await _dio.get('$_apiBase/passenger-requests', queryParameters: {'status': status});
      if (res.statusCode == 200 && res.data is List) {
        return (res.data as List)
            .map((e) => PassengerRequestModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      return _defaultStudentRequests;
    }
    return [];
  }

  @override
  Future<PassengerRequestModel> createPassengerRequest({
    required String passengerId,
    required String passengerName,
    required String passengerPhone,
    required String pickup,
    required String dropoff,
    required String requestedTime,
    double proposedFare = 50.0,
    String notes = '',
  }) async {
    try {
      final res = await _dio.post('$_apiBase/passenger-requests', data: {
        'passengerId': passengerId,
        'passengerName': passengerName,
        'passengerPhone': passengerPhone,
        'pickup': pickup,
        'dropoff': dropoff,
        'requestedTime': requestedTime,
        'proposedFare': proposedFare,
        'notes': notes,
      });
      return PassengerRequestModel.fromJson(Map<String, dynamic>.from(res.data));
    } catch (_) {
      return PassengerRequestModel(
        id: 'preq_${DateTime.now().millisecondsSinceEpoch}',
        passengerId: passengerId,
        passengerName: passengerName,
        passengerPhone: passengerPhone,
        pickup: pickup,
        dropoff: dropoff,
        requestedTime: requestedTime,
        proposedFare: proposedFare,
        notes: notes,
        createdAt: DateTime.now().toIso8601String(),
      );
    }
  }

  @override
  Future<bool> acceptPassengerRequest({
    required String requestId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String driverBike,
    String? driverStudentId,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/passenger-requests/$requestId/accept', data: {
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'driverBike': driverBike,
        if (driverStudentId != null && driverStudentId.isNotEmpty)
          'driverStudentId': driverStudentId,
      });
      return res.statusCode == 200;
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        throw Exception(detail['detail'].toString());
      }
      if (detail is String && detail.isNotEmpty) {
        throw Exception(detail);
      }
      rethrow;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> updatePassengerRequest({
    required String requestId,
    String? pickup,
    String? dropoff,
    String? requestedTime,
    double? proposedFare,
    String? notes,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (pickup != null) data['pickup'] = pickup;
      if (dropoff != null) data['dropoff'] = dropoff;
      if (requestedTime != null) data['requestedTime'] = requestedTime;
      if (proposedFare != null) data['proposedFare'] = proposedFare;
      if (notes != null) data['notes'] = notes;

      final res = await _dio.patch('$_apiBase/passenger-requests/$requestId', data: data);
      return res.statusCode == 200;
    } catch (_) {
      try {
        final data = <String, dynamic>{};
        if (pickup != null) data['pickup'] = pickup;
        if (dropoff != null) data['dropoff'] = dropoff;
        if (requestedTime != null) data['requestedTime'] = requestedTime;
        if (proposedFare != null) data['proposedFare'] = proposedFare;
        if (notes != null) data['notes'] = notes;

        final res = await _dio.post('$_apiBase/passenger-requests/$requestId/update', data: data);
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  Future<bool> deletePassengerRequest(String requestId) async {
    try {
      final res = await _dio.delete('$_apiBase/passenger-requests/$requestId');
      return res.statusCode == 200;
    } catch (_) {
      try {
        final res = await _dio.post('$_apiBase/passenger-requests/$requestId/delete');
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCompletedRides({String? userId}) async {
    try {
      final url = userId != null
          ? '$_apiBase/completed-rides?user_id=$userId'
          : '$_apiBase/completed-rides';
      final res = await _dio.get(url);
      if (res.data is List) {
        return List<Map<String, dynamic>>.from(res.data);
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<bool> triggerAlertRing({
    required String targetUserId,
    String? targetName,
    String? senderId,
    required String senderName,
    required String rideId,
    String? ringId,
    String? message,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/alert-ring', data: {
        'targetUserId': targetUserId,
        'targetName': targetName ?? '',
        'senderId': senderId ?? '',
        'senderName': senderName,
        'rideId': rideId,
        'ringId': ringId ?? 'ring_${DateTime.now().millisecondsSinceEpoch}',
        'message': message ?? '🔔 Alert: Please check your phone!',
      });
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopAlertRing({
    required String targetUserId,
    String? senderId,
    String? ringId,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/stop-ring', data: {
        'targetUserId': targetUserId,
        'senderId': senderId ?? '',
        'ringId': ringId ?? '',
      });
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
