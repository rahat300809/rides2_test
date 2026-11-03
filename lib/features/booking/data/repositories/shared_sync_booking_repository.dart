import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/booking_repository.dart';
import 'package:diu_ride/features/booking/data/repositories/mock_booking_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';

class SharedSyncBookingRepository implements BookingRepository {
  final RidesRepository ridesRepository;
  final PreferencesService preferences;
  late final MockBookingRepository _localFallback;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  SharedSyncBookingRepository({
    required this.ridesRepository,
    required this.preferences,
  }) {
    _localFallback = MockBookingRepository(ridesRepository: ridesRepository);
  }

  String get _apiBase => AppConfig.current.apiBaseUrl;

  @override
  Future<BookingModel> requestSeat({
    required String rideId,
    required String passengerId,
    required String passengerName,
    required String passengerDept,
    required String passengerPhone,
    required String pickupPoint,
    required String dropoffPoint,
    required int seatsBooked,
    required double totalFare,
  }) async {
    // 1. Client-side pre-validation: check duplicate booking on same ride
    final myExisting = await getMyBookings(passengerId);
    final alreadyBooked = myExisting.any((b) =>
        b.rideId == rideId &&
        b.status != BookingStatus.cancelled &&
        b.status != BookingStatus.rejected);
    if (alreadyBooked) {
      throw Exception('You already have an active booking on this ride.');
    }

    // 2. Client-side pre-validation: check seat availability & self-booking
    final ride = await ridesRepository.getRideById(rideId);
    if (ride != null) {
      if (ride.driverId == passengerId) {
        throw Exception('You cannot book a seat on your own ride.');
      }
      if (ride.availableSeats < seatsBooked) {
        throw Exception('Not enough seats available on this ride.');
      }
    }

    final booking = BookingModel(
      id: 'b_${const Uuid().v4().substring(0, 8)}',
      rideId: rideId,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerDept: passengerDept,
      passengerPhone: passengerPhone,
      pickupPoint: pickupPoint,
      dropoffPoint: dropoffPoint,
      seatsBooked: seatsBooked,
      totalFare: totalFare,
      status: BookingStatus.requested,
      requestedAt: DateTime.now(),
    );

    // 3. Post to central server (server atomically manages seat deduction)
    try {
      final response = await _dio.post(
        '$_apiBase/bookings',
        data: booking.toJson(),
      );
      debugPrint('Booking sent to central backend: ${booking.id}');

      BookingModel createdBooking = booking;
      if (response.statusCode == 200 && response.data is Map) {
        createdBooking = BookingModel.fromJson(Map<String, dynamic>.from(response.data as Map));
      }

      // Cache to local preferences
      try {
        final current = await getMyBookings(passengerId);
        final updated = [createdBooking, ...current.where((b) => b.id != createdBooking.id)];
        await preferences.saveSharedBookings(jsonEncode(updated.map((b) => b.toJson()).toList()));
      } catch (_) {}

      return createdBooking;
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      if (detail != null) {
        throw Exception(detail.toString());
      }
      rethrow;
    }
  }

  @override
  Future<List<BookingModel>> getMyBookings(String passengerId) async {
    try {
      final response = await _dio.get('$_apiBase/bookings?passenger_id=$passengerId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Get bookings error (fallback to cache): $e');
    }

    // Fallback to cached preferences
    final cached = preferences.getSharedBookings();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        return decoded
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((b) => b.passengerId == passengerId)
            .toList();
      } catch (_) {}
    }

    return _localFallback.getMyBookings(passengerId);
  }

  @override
  Future<List<BookingModel>> getBookingsForRide(String rideId) async {
    try {
      final response = await _dio.get('$_apiBase/bookings?ride_id=$rideId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Get ride bookings error (fallback to cache): $e');
    }

    // Fallback to cache
    final cached = preferences.getSharedBookings();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        return decoded
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((b) => b.rideId == rideId)
            .toList();
      } catch (_) {}
    }

    return _localFallback.getBookingsForRide(rideId);
  }

  @override
  Future<bool> acceptBooking(String bookingId) async {
    try {
      await _dio.post('$_apiBase/bookings/$bookingId/accept');
    } catch (e) {
      try {
        await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'accepted'});
      } catch (_) {}
    }

    await _localFallback.acceptBooking(bookingId);

    // Update preferences cache
    try {
      final cached = preferences.getSharedBookings();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == bookingId || item['id']?.toString().contains(bookingId) == true)) {
            item['status'] = 'accepted';
          }
        }
        await preferences.saveSharedBookings(jsonEncode(decoded));
      }
    } catch (_) {}

    return true;
  }

  @override
  Future<bool> rejectBooking(String bookingId) async {
    try {
      await _dio.post('$_apiBase/bookings/$bookingId/reject');
    } catch (e) {
      try {
        await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'rejected'});
      } catch (_) {}
    }

    await _localFallback.rejectBooking(bookingId);

    // Update preferences cache
    try {
      final cached = preferences.getSharedBookings();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == bookingId || item['id']?.toString().contains(bookingId) == true)) {
            item['status'] = 'rejected';
          }
        }
        await preferences.saveSharedBookings(jsonEncode(decoded));
      }
    } catch (_) {}

    return true;
  }

  @override
  Future<bool> cancelBooking(String bookingId) async {
    int seatsToRestore = 1;
    String rideIdToRestore = '';

    // Inspect cached bookings to know ride and seat count
    try {
      final cached = preferences.getSharedBookings();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map && (item['id'] == bookingId || item['id']?.toString().contains(bookingId) == true)) {
            seatsToRestore = (item['seatsBooked'] as num?)?.toInt() ?? 1;
            rideIdToRestore = item['rideId']?.toString() ?? '';
            item['status'] = 'cancelled';
          }
        }
        await preferences.saveSharedBookings(jsonEncode(decoded));
      }
    } catch (_) {}

    bool serverRestored = false;
    try {
      final res = await _dio.post('$_apiBase/bookings/$bookingId/cancel');
      if (res.statusCode == 200) {
        serverRestored = true;
      }
    } catch (e) {
      try {
        final res = await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'cancelled'});
        if (res.statusCode == 200) {
          serverRestored = true;
        }
      } catch (_) {}
    }

    await _localFallback.cancelBooking(bookingId);

    // Only restore seats locally if central server was unreachable
    if (!serverRestored && rideIdToRestore.isNotEmpty) {
      try {
        await ridesRepository.updateRideSeats(rideIdToRestore, -seatsToRestore);
      } catch (_) {}
    }

    return true;
  }

  @override
  Future<bool> deleteBooking(String bookingId) async {
    try {
      final cached = preferences.getSharedBookings();
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        final updated = decoded.where((item) {
          if (item is Map) {
            final id = item['id']?.toString() ?? '';
            return id != bookingId && !id.contains(bookingId);
          }
          return true;
        }).toList();
        await preferences.saveSharedBookings(jsonEncode(updated));
      }
    } catch (_) {}

    try {
      await _dio.delete('$_apiBase/bookings/$bookingId');
    } catch (_) {}

    await _localFallback.deleteBooking(bookingId);
    return true;
  }
}