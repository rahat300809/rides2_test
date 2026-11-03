import 'package:diu_ride/features/booking/data/models/booking_model.dart';

abstract class BookingRepository {
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
  });

  Future<List<BookingModel>> getMyBookings(String passengerId);

  Future<List<BookingModel>> getBookingsForRide(String rideId);

  Future<bool> cancelBooking(String bookingId);

  Future<bool> deleteBooking(String bookingId);

  Future<bool> acceptBooking(String bookingId);

  Future<bool> rejectBooking(String bookingId);
}
