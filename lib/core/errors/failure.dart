class Failure {
  final String message;
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network connection failed. Please check your internet.']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server encountered an issue. Please try again later.', super.statusCode]);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed. Please verify your DIU credentials.']);
}

class SeatUnavailableFailure extends Failure {
  const SeatUnavailableFailure([super.message = 'Sorry, the last seat for this ride was just booked by another student.']);
}

class DuplicateBookingFailure extends Failure {
  const DuplicateBookingFailure([super.message = 'You have already requested or reserved a seat in this ride.']);
}
