enum BookingStatus { requested, accepted, rejected, cancelled, completed }

class BookingModel {
  final String id;
  final String rideId;
  final String passengerId;
  final String passengerName;
  final String? passengerPhotoUrl;
  final String passengerDept;
  final String passengerPhone;
  final String pickupPoint;
  final String dropoffPoint;
  final int seatsBooked;
  final double totalFare;
  final BookingStatus status;
  final DateTime requestedAt;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleModel;
  final DateTime? departureTime;
  final String? originName;
  final String? destinationName;
  final String? rideStatus;

  const BookingModel({
    required this.id,
    required this.rideId,
    required this.passengerId,
    required this.passengerName,
    this.passengerPhotoUrl,
    required this.passengerDept,
    required this.passengerPhone,
    required this.pickupPoint,
    required this.dropoffPoint,
    required this.seatsBooked,
    required this.totalFare,
    this.status = BookingStatus.requested,
    required this.requestedAt,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.vehicleModel,
    this.departureTime,
    this.originName,
    this.destinationName,
    this.rideStatus,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    DateTime? depTime;
    if (json['departureTime'] != null) {
      depTime = DateTime.tryParse(json['departureTime'].toString());
    }

    return BookingModel(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      passengerId: json['passengerId'] as String,
      passengerName: json['passengerName'] as String,
      passengerPhotoUrl: json['passengerPhotoUrl'] as String?,
      passengerDept: json['passengerDept'] as String? ?? 'DIU Student',
      passengerPhone: json['passengerPhone'] as String? ?? '',
      pickupPoint: json['pickupPoint'] as String,
      dropoffPoint: json['dropoffPoint'] as String,
      seatsBooked: json['seatsBooked'] as int,
      totalFare: (json['totalFare'] as num).toDouble(),
      status: BookingStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => BookingStatus.requested,
      ),
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      driverId: json['driverId'] as String?,
      driverName: json['driverName'] as String?,
      driverPhone: json['driverPhone'] as String?,
      vehicleModel: json['vehicleModel'] as String?,
      departureTime: depTime,
      originName: json['originName'] as String?,
      destinationName: json['destinationName'] as String?,
      rideStatus: json['rideStatus'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rideId': rideId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhotoUrl': passengerPhotoUrl,
      'passengerDept': passengerDept,
      'passengerPhone': passengerPhone,
      'pickupPoint': pickupPoint,
      'dropoffPoint': dropoffPoint,
      'seatsBooked': seatsBooked,
      'totalFare': totalFare,
      'status': status.name,
      'requestedAt': requestedAt.toIso8601String(),
      if (driverId != null) 'driverId': driverId,
      if (driverName != null) 'driverName': driverName,
      if (driverPhone != null) 'driverPhone': driverPhone,
      if (vehicleModel != null) 'vehicleModel': vehicleModel,
      if (departureTime != null) 'departureTime': departureTime!.toIso8601String(),
      if (originName != null) 'originName': originName,
      if (destinationName != null) 'destinationName': destinationName,
      if (rideStatus != null) 'rideStatus': rideStatus,
    };
  }

  BookingModel copyWith({
    BookingStatus? status,
    String? driverId,
    String? driverName,
    String? driverPhone,
    String? vehicleModel,
    DateTime? departureTime,
    String? originName,
    String? destinationName,
    String? rideStatus,
  }) {
    return BookingModel(
      id: id,
      rideId: rideId,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerDept: passengerDept,
      passengerPhone: passengerPhone,
      pickupPoint: pickupPoint,
      dropoffPoint: dropoffPoint,
      seatsBooked: seatsBooked,
      totalFare: totalFare,
      status: status ?? this.status,
      requestedAt: requestedAt,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      departureTime: departureTime ?? this.departureTime,
      originName: originName ?? this.originName,
      destinationName: destinationName ?? this.destinationName,
      rideStatus: rideStatus ?? this.rideStatus,
    );
  }
}
