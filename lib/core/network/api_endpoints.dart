class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String loginWithStudentId = '/auth/login-student-id';
  static const String verifyEmail = '/auth/verify-email';
  static const String sendPhoneOtp = '/auth/send-otp';
  static const String verifyPhoneOtp = '/auth/verify-otp';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';

  // Rides
  static const String rides = '/rides';
  static const String searchRides = '/rides/search';
  static const String nearbyRides = '/rides/nearby';
  static const String createRide = '/rides';
  static String rideDetails(String id) => '/rides/$id';
  static String cancelRide(String id) => '/rides/$id/cancel';
  static String startRide(String id) => '/rides/$id/start';
  static String completeRide(String id) => '/rides/$id/complete';

  // Bookings
  static const String createBooking = '/bookings';
  static const String myBookings = '/bookings/my-bookings';
  static String bookingDetails(String id) => '/bookings/$id';
  static String cancelBooking(String id) => '/bookings/$id/cancel';
  static String acceptBooking(String id) => '/bookings/$id/accept';
  static String rejectBooking(String id) => '/bookings/$id/reject';

  // Realtime & Location
  static const String updateDriverLocation = '/location/driver';

  // Safety & SOS
  static const String triggerSos = '/safety/sos';
  static const String emergencyContacts = '/safety/emergency-contacts';

  // Ratings
  static const String submitRating = '/ratings';

  // Chat
  static String chatMessages(String rideId) => '/chat/$rideId/messages';
  static String sendMessage(String rideId) => '/chat/$rideId/messages';

  // Notifications
  static const String notifications = '/notifications';
  static String markNotificationRead(String id) => '/notifications/$id/read';
}
