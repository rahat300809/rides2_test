import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/booking_repository.dart';
import 'package:diu_ride/features/booking/data/repositories/shared_sync_booking_repository.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
// isCurrentUserRide lives in rides_provider.dart (already imported)

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  final ridesRepo = ref.watch(ridesRepositoryProvider);
  final prefs = ref.watch(preferencesProvider);
  return SharedSyncBookingRepository(ridesRepository: ridesRepo, preferences: prefs);
});

class BookingState {
  final bool isLoading;
  final BookingModel? lastBooking;
  final String? errorMessage;
  final bool isSuccess;

  const BookingState({
    this.isLoading = false,
    this.lastBooking,
    this.errorMessage,
    this.isSuccess = false,
  });

  BookingState copyWith({
    bool? isLoading,
    BookingModel? lastBooking,
    String? errorMessage,
    bool? isSuccess,
  }) {
    return BookingState(
      isLoading: isLoading ?? this.isLoading,
      lastBooking: lastBooking ?? this.lastBooking,
      errorMessage: errorMessage,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class BookingNotifier extends StateNotifier<BookingState> {
  final BookingRepository _repository;
  final Ref _ref;

  BookingNotifier(this._repository, this._ref) : super(const BookingState());

  Future<bool> bookSeat({
    required String rideId,
    required String pickupPoint,
    required String dropoffPoint,
    required int seatsBooked,
    required double totalFare,
    // Optional ride context for notification messaging
    RideModel? ride,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, isSuccess: false);
    final user = _ref.read(authNotifierProvider).user;
    if (user == null) {
      state = state.copyWith(isLoading: false, errorMessage: 'User not signed in');
      return false;
    }

    // Same account cannot book its own biker offer after switching to Student mode
    if (ride != null && isCurrentUserRide(ride, user)) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'You cannot book your own ride. Mode switch does not let the same account accept itself.',
      );
      return false;
    }

    try {
      final booking = await _repository.requestSeat(
        rideId: rideId,
        passengerId: user.id,
        passengerName: user.name,
        passengerDept: '${user.department} ${user.batch}',
        passengerPhone: user.phone,
        pickupPoint: pickupPoint,
        dropoffPoint: dropoffPoint,
        seatsBooked: seatsBooked,
        totalFare: totalFare,
      );

      state = state.copyWith(
        isLoading: false,
        lastBooking: booking,
        isSuccess: true,
      );

      // -----------------------------------------------------------------------
      // FIRE NOTIFICATIONS — connect the pipeline
      // -----------------------------------------------------------------------
      final notifier = _ref.read(notificationsProvider.notifier);
      final driverName = ride?.driverName ?? 'Driver';

      // 1. Passenger notification: request sent
      notifier.onBookingRequestSent(
        bookingId: booking.id,
        rideId: rideId,
        driverName: driverName,
        fare: totalFare,
      );

      // 2. Driver notification: incoming request alarm (requiresAction = true)
      notifier.onRideRequested(
        bookingId: booking.id,
        rideId: rideId,
        passengerName: user.name,
        pickup: pickupPoint,
        dropoff: dropoffPoint,
        seats: seatsBooked,
        fare: totalFare,
      );
      // -----------------------------------------------------------------------

      // Invalidate relevant providers to refresh UI
      _ref.invalidate(myBookingsProvider);
      _ref.invalidate(departingSoonRidesProvider);
      _ref.invalidate(allSystemRidesProvider);
      _ref.invalidate(allAvailableRidesProvider);
      _ref.invalidate(searchRidesResultsProvider);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> cancelBooking(String bookingId) async {
    await _repository.cancelBooking(bookingId);
    _ref.invalidate(myBookingsProvider);
    _ref.invalidate(departingSoonRidesProvider);
    _ref.invalidate(allSystemRidesProvider);
    _ref.invalidate(allAvailableRidesProvider);
    _ref.invalidate(searchRidesResultsProvider);
  }

  /// Driver accepts a booking request — fires acceptance notification
  Future<bool> acceptBooking({
    required String bookingId,
    required String rideId,
    required String driverName,
    required String pickupPoint,
  }) async {
    try {
      final success = await _repository.acceptBooking(bookingId);
      if (success) {
        _ref.read(notificationsProvider.notifier).onBookingAccepted(
              bookingId: bookingId,
              rideId: rideId,
              driverName: driverName,
              pickup: pickupPoint,
            );
        _ref.invalidate(rideBookingsProvider);
        _ref.invalidate(myBookingsProvider);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Driver rejects a booking request — fires rejection notification
  Future<bool> rejectBooking({
    required String bookingId,
    required String rideId,
    required String driverName,
  }) async {
    try {
      final success = await _repository.rejectBooking(bookingId);
      if (success) {
        _ref.read(notificationsProvider.notifier).onBookingRejected(
              bookingId: bookingId,
              rideId: rideId,
              driverName: driverName,
            );
        _ref.invalidate(rideBookingsProvider);
        _ref.invalidate(myBookingsProvider);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  void reset() {
    state = const BookingState();
  }
}

final bookingNotifierProvider =
    StateNotifierProvider<BookingNotifier, BookingState>((ref) {
  final repo = ref.watch(bookingRepositoryProvider);
  return BookingNotifier(repo, ref);
});

final myBookingsProvider = FutureProvider<List<BookingModel>>((ref) async {
  final repo = ref.watch(bookingRepositoryProvider);
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];
  return repo.getMyBookings(user.id);
});

final rideBookingsProvider =
    FutureProvider.family<List<BookingModel>, String>((ref, rideId) async {
  final repo = ref.watch(bookingRepositoryProvider);
  return repo.getBookingsForRide(rideId);
});
