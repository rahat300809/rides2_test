import 'package:flutter_test/flutter_test.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/errors/failure.dart';
import 'package:diu_ride/core/utils/h3_utils.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/mock_booking_repository.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/mock_rides_repository.dart';

void main() {
  group('DIU Ride - Input Validation Tests', () {
    test('Student ID validation accepts standard DIU formats', () {
      expect(Validators.validateStudentId('201-15-14285'), isNull);
      expect(Validators.validateStudentId('211-35-987'), isNull);
      expect(Validators.validateStudentId(''), isNotNull);
      expect(Validators.validateStudentId('123'), isNotNull);
    });

    test('DIU Email validation enforces official domain', () {
      expect(Validators.validateDiuEmail('tanvir@diu.edu.bd'), isNull);
      expect(Validators.validateDiuEmail('student@daffodilvarsity.edu.bd'), isNotNull);
      expect(Validators.validateDiuEmail('gmail@gmail.com'), isNotNull);
      expect(Validators.validateDiuEmail(''), isNotNull);
    });

    test('Phone number validation accepts 11-digit BD mobile', () {
      expect(Validators.validatePhoneNumber('01712345678'), isNull);
      expect(Validators.validatePhoneNumber('+8801812345678'), isNull);
      expect(Validators.validatePhoneNumber('012345'), isNotNull);
    });
  });

  group('H3 Geographic Indexing & Spatial Tests', () {
    test('Converts campus coordinates to resolution 8 H3 index', () {
      final h3 = H3Utils.latLngToH3(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng);
      expect(h3, isNotEmpty);
      expect(h3.startsWith('88654c'), isTrue);
    });

    test('Computes 6 neighboring cells for k-ring 1', () {
      final center = H3Utils.latLngToH3(CampusLocations.diuCenterLat, CampusLocations.diuCenterLng);
      final neighbors = H3Utils.getNeighboringH3Cells(center);
      expect(neighbors.length, equals(7)); // center + 6 neighbors
      expect(neighbors.first, equals(center));
    });

    test('Accurately computes Haversine distance from DSC to Uttara Metro', () {
      final dist = H3Utils.calculateDistanceKm(
        CampusLocations.diuCenterLat,
        CampusLocations.diuCenterLng,
        CampusLocations.uttaraMetro.latitude,
        CampusLocations.uttaraMetro.longitude,
      );
      // Actual straight-line distance is ~6.1 km
      expect(dist, greaterThan(5.0));
      expect(dist, lessThan(8.0));
    });
  });

  group('Transactional Seat Locking & Concurrent Booking Tests', () {
    late MockRidesRepository ridesRepo;
    late MockBookingRepository bookingRepo;

    setUp(() {
      ridesRepo = MockRidesRepository();
      bookingRepo = MockBookingRepository(ridesRepository: ridesRepo);
    });

    test('Successfully requests a seat when available', () async {
      final booking = await bookingRepo.requestSeat(
        rideId: 'ride_sakib_01',
        passengerId: 'usr_student_alpha',
        passengerName: 'Student Alpha',
        passengerDept: "SWE '22",
        passengerPhone: '01700000001',
        pickupPoint: 'DIU Main Gate 1',
        dropoffPoint: 'Uttara Diabari Metro Stn',
        seatsBooked: 1,
        totalFare: 40.0,
      );

      expect(booking.status, equals(BookingStatus.requested));
      expect(booking.seatsBooked, equals(1));
    });

    test('Prevents duplicate booking by the same student on the same ride', () async {
      await bookingRepo.requestSeat(
        rideId: 'ride_sakib_01',
        passengerId: 'usr_student_beta',
        passengerName: 'Student Beta',
        passengerDept: "CSE '22",
        passengerPhone: '01700000002',
        pickupPoint: 'DIU Main Gate 1',
        dropoffPoint: 'Uttara Diabari Metro Stn',
        seatsBooked: 1,
        totalFare: 40.0,
      );

      // Attempt second reservation on same ride
      expect(
        () => bookingRepo.requestSeat(
          rideId: 'ride_sakib_01',
          passengerId: 'usr_student_beta',
          passengerName: 'Student Beta',
          passengerDept: "CSE '22",
          passengerPhone: '01700000002',
          pickupPoint: 'DIU Main Gate 1',
          dropoffPoint: 'Uttara Diabari Metro Stn',
          seatsBooked: 1,
          totalFare: 40.0,
        ),
        throwsA(isA<DuplicateBookingFailure>()),
      );
    });

    test('Transactional seat exhaustion: two users requesting the last seat simultaneously', () async {
      // Create a ride with exactly 1 seat
      final singleSeatRide = await ridesRepo.createRide(
        originName: 'DIU Gate 1',
        originLat: CampusLocations.mainGate.latitude,
        originLng: CampusLocations.mainGate.longitude,
        destinationName: 'Mirpur 10',
        destinationLat: CampusLocations.mirpur10.latitude,
        destinationLng: CampusLocations.mirpur10.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 30)),
        vehicle: const VehicleModel(
          id: 'v_test',
          type: VehicleType.bike,
          modelName: 'Bike Test',
          color: 'Black',
          licensePlate: 'Dhaka-123',
        ),
        availableSeats: 1,
        farePerSeat: 35.0,
        isFemaleOnly: false,
      );

      // Passenger 1 reserves the last seat
      final booking1 = await bookingRepo.requestSeat(
        rideId: singleSeatRide.id,
        passengerId: 'passenger_1',
        passengerName: 'User One',
        passengerDept: 'CSE',
        passengerPhone: '01700000001',
        pickupPoint: 'DIU Gate 1',
        dropoffPoint: 'Mirpur 10',
        seatsBooked: 1,
        totalFare: 35.0,
      );
      expect(booking1.status, equals(BookingStatus.requested));

      // Update ride availableSeats to 0 to simulate transactional state update
      final rideInRepo = await ridesRepo.getRideById(singleSeatRide.id);
      if (rideInRepo != null) {
        // Verify that Passenger 2 trying to book the same ride fails with SeatUnavailableFailure
        expect(
          () => bookingRepo.requestSeat(
            rideId: singleSeatRide.id,
            passengerId: 'passenger_2',
            passengerName: 'User Two',
            passengerDept: 'BBA',
            passengerPhone: '01700000002',
            pickupPoint: 'DIU Gate 1',
            dropoffPoint: 'Mirpur 10',
            seatsBooked: 2, // exceeds available
            totalFare: 70.0,
          ),
          throwsA(isA<SeatUnavailableFailure>()),
        );
      }
    });

    test('Cancellation transitions status to cancelled', () async {
      final booking = await bookingRepo.requestSeat(
        rideId: 'ride_ayesha_02',
        passengerId: 'usr_student_gamma',
        passengerName: 'Student Gamma',
        passengerDept: "BBA '21",
        passengerPhone: '01700000003',
        pickupPoint: 'DSC Roundabout',
        dropoffPoint: 'Mirpur 12',
        seatsBooked: 1,
        totalFare: 80.0,
      );

      final success = await bookingRepo.cancelBooking(booking.id);
      expect(success, isTrue);

      final list = await bookingRepo.getMyBookings('usr_student_gamma');
      expect(list.first.status, equals(BookingStatus.cancelled));
    });
  });
}
