import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/shared_sync_booking_repository.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/shared_sync_rides_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    AppConfig.initialize(
      environment: Environment.development,
      apiBaseUrl: 'http://127.0.0.1:9999/dummy_api', // dummy offline url
    );
  });

  group('Flutter SharedSync Repositories - Repeated Ordering & Posting Verified Tests', () {
    late PreferencesService prefsService;
    late SharedSyncRidesRepository ridesRepo;
    late SharedSyncBookingRepository bookingRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      prefsService = PreferencesService(prefs);
      ridesRepo = SharedSyncRidesRepository(preferences: prefsService);
      bookingRepo = SharedSyncBookingRepository(
        ridesRepository: ridesRepo,
        preferences: prefsService,
      );
    });

    test('Rapid repeated ride posting bounds cache to maximum 30 active rides', () async {
      // Driver posts 40 rides in a row
      for (int i = 0; i < 40; i++) {
        await ridesRepo.createRide(
          driverId: 'drv_rapid',
          driverName: 'Rapid Poster',
          originName: 'Campus',
          originLat: 23.8,
          originLng: 90.3,
          destinationName: 'City',
          destinationLat: 23.7,
          destinationLng: 90.4,
          departureTime: DateTime.now().add(Duration(hours: 1 + i)),
          vehicle: const VehicleModel(
            id: 'v_rapid',
            type: VehicleType.bike,
            modelName: 'Rapid Bike',
            color: 'Blue',
            licensePlate: 'Dhaka-999',
          ),
          availableSeats: 1,
          farePerSeat: 50.0,
          isFemaleOnly: false,
        );
      }

      final cachedJson = prefsService.getSharedRides();
      expect(cachedJson, isNotNull);
      final decoded = jsonDecode(cachedJson!) as List;
      // Must be capped at 30 items
      expect(decoded.length, lessThanOrEqualTo(30));
    });

    test('Repeated booking by same user on same ride is blocked with duplicate exception', () async {
      // Setup a ride in local cache with available seats
      final ride = RideModel(
        id: 'ride_same_ride',
        driverId: 'drv_someone_else',
        driverName: 'Other Driver',
        driverDept: 'CSE',
        driverRating: 5.0,
        driverRideCount: 10,
        originName: 'Gate 1',
        originLat: 23.8,
        originLng: 90.3,
        destinationName: 'Mirpur',
        destinationLat: 23.7,
        destinationLng: 90.4,
        departureTime: DateTime.now().add(const Duration(hours: 2)),
        farePerSeat: 50.0,
        totalSeats: 2,
        availableSeats: 2,
        isFemaleOnly: false,
        createdAt: DateTime.now(),
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_test',
          type: VehicleType.bike,
          modelName: 'Bike',
          color: 'Black',
          licensePlate: 'Dhaka-1',
        ),
      );
      await prefsService.saveSharedRides(jsonEncode([ride.toJson()]));

      // Seed an active booking in cache for this user
      final existingBooking = BookingModel(
        id: 'bkg_existing',
        rideId: 'ride_same_ride',
        passengerId: 'usr_repeat_booker',
        passengerName: 'Repeat Booker',
        passengerDept: 'SWE',
        passengerPhone: '01711111111',
        pickupPoint: 'Gate 1',
        dropoffPoint: 'Mirpur',
        seatsBooked: 1,
        totalFare: 50.0,
        status: BookingStatus.requested,
        requestedAt: DateTime.now(),
      );
      await prefsService.saveSharedBookings(jsonEncode([existingBooking.toJson()]));

      // Attempting to book the same ride again throws duplicate booking exception
      expect(
        () => bookingRepo.requestSeat(
          rideId: 'ride_same_ride',
          passengerId: 'usr_repeat_booker',
          passengerName: 'Repeat Booker',
          passengerDept: 'SWE',
          passengerPhone: '01711111111',
          pickupPoint: 'Gate 1',
          dropoffPoint: 'Mirpur',
          seatsBooked: 1,
          totalFare: 50.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Driver attempting to book their own ride throws self-booking exception', () async {
      final ride = RideModel(
        id: 'ride_self_test',
        driverId: 'drv_myself',
        driverName: 'Myself Driver',
        driverDept: 'CSE',
        driverRating: 5.0,
        driverRideCount: 10,
        originName: 'Gate 1',
        originLat: 23.8,
        originLng: 90.3,
        destinationName: 'Mirpur',
        destinationLat: 23.7,
        destinationLng: 90.4,
        departureTime: DateTime.now().add(const Duration(hours: 2)),
        farePerSeat: 50.0,
        totalSeats: 2,
        availableSeats: 2,
        isFemaleOnly: false,
        createdAt: DateTime.now(),
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_test',
          type: VehicleType.bike,
          modelName: 'Bike',
          color: 'Black',
          licensePlate: 'Dhaka-1',
        ),
      );
      await prefsService.saveSharedRides(jsonEncode([ride.toJson()]));

      expect(
        () => bookingRepo.requestSeat(
          rideId: 'ride_self_test',
          passengerId: 'drv_myself', // Same as driver
          passengerName: 'Myself Driver',
          passengerDept: 'CSE',
          passengerPhone: '01711111111',
          pickupPoint: 'Gate 1',
          dropoffPoint: 'Mirpur',
          seatsBooked: 1,
          totalFare: 50.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Booking with insufficient available seats throws exception', () async {
      final ride = RideModel(
        id: 'ride_zero_seats',
        driverId: 'drv_other',
        driverName: 'Other Driver',
        driverDept: 'CSE',
        driverRating: 5.0,
        driverRideCount: 10,
        originName: 'Gate 1',
        originLat: 23.8,
        originLng: 90.3,
        destinationName: 'Mirpur',
        destinationLat: 23.7,
        destinationLng: 90.4,
        departureTime: DateTime.now().add(const Duration(hours: 2)),
        farePerSeat: 50.0,
        totalSeats: 1,
        availableSeats: 0, // No seats left!
        isFemaleOnly: false,
        createdAt: DateTime.now(),
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_test',
          type: VehicleType.bike,
          modelName: 'Bike',
          color: 'Black',
          licensePlate: 'Dhaka-1',
        ),
      );
      await prefsService.saveSharedRides(jsonEncode([ride.toJson()]));

      expect(
        () => bookingRepo.requestSeat(
          rideId: 'ride_zero_seats',
          passengerId: 'usr_new_passenger',
          passengerName: 'New Passenger',
          passengerDept: 'CSE',
          passengerPhone: '01711111111',
          pickupPoint: 'Gate 1',
          dropoffPoint: 'Mirpur',
          seatsBooked: 1,
          totalFare: 50.0,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
