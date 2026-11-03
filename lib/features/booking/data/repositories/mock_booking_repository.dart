import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/errors/failure.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/booking_repository.dart';

class MockBookingRepository implements BookingRepository {
  final RidesRepository ridesRepository;
  final List<BookingModel> _bookings = [];

  // Transaction mutex lock to prevent concurrent double booking of the last seat
  bool _isLockAcquired = false;

  MockBookingRepository({required this.ridesRepository}) {
    _seedBookings();
  }

  void _seedBookings() {
    // Keep empty by default so no fake confirmed commute ride is stuck on home screen.
    // Real bookings are created dynamically by students via ride requests.
  }

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
    // Acquire transactional seat lock
    while (_isLockAcquired) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isLockAcquired = true;

    try {
      await Future.delayed(const Duration(milliseconds: 400));

      // 1. Check duplicate booking
      final alreadyBooked = _bookings.any(
        (b) => b.rideId == rideId && b.passengerId == passengerId && b.status != BookingStatus.cancelled && b.status != BookingStatus.rejected,
      );
      if (alreadyBooked) {
        throw const DuplicateBookingFailure('You already have an active reservation for this ride.');
      }

      // 2. Fetch authoritative ride state
      final ride = await ridesRepository.getRideById(rideId);
      if (ride == null) {
        throw const ServerFailure('Ride not found');
      }

      // 3. Authoritative seat availability check
      if (ride.availableSeats < seatsBooked) {
        throw const SeatUnavailableFailure(
          'Seat unavailable! Another DIU peer just reserved the last seat.',
        );
      }

      // 4. Atomically deduct seat
      await ridesRepository.updateRideSeats(rideId, seatsBooked);

      // 5. Create booking record
      final booking = BookingModel(
        id: 'book_${const Uuid().v4().substring(0, 8)}',
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

      _bookings.insert(0, booking);
      return booking;
    } finally {
      // Release lock
      _isLockAcquired = false;
    }
  }

  @override
  Future<List<BookingModel>> getMyBookings(String passengerId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _bookings.where((b) => b.passengerId == passengerId).toList();
  }

  @override
  Future<List<BookingModel>> getBookingsForRide(String rideId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _bookings.where((b) => b.rideId == rideId).toList();
  }

  @override
  Future<bool> cancelBooking(String bookingId) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx] = _bookings[idx].copyWith(status: BookingStatus.cancelled);
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteBooking(String bookingId) async {
    _bookings.removeWhere((b) => b.id == bookingId);
    return true;
  }

  @override
  Future<bool> acceptBooking(String bookingId) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx] = _bookings[idx].copyWith(status: BookingStatus.accepted);
      return true;
    }
    return false;
  }

  @override
  Future<bool> rejectBooking(String bookingId) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx] = _bookings[idx].copyWith(status: BookingStatus.rejected);
      return true;
    }
    return false;
  }
}
