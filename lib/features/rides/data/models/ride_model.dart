import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

enum RideStatus { published, active, completed, cancelled, occupied, suspended }

class RideModel {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhotoUrl;
  final String driverDept;
  final String? driverPhone;
  final double driverRating;
  final int driverRideCount;
  final String originName;
  final String? originSubtitle;
  final double originLat;
  final double originLng;
  final String destinationName;
  final String? destinationSubtitle;
  final double destinationLat;
  final double destinationLng;
  final String? waypointName;
  final DateTime departureTime;
  final double farePerSeat;
  final int totalSeats;
  final int availableSeats;
  final bool isFemaleOnly;
  final RideStatus status;
  final VehicleModel vehicle;
  final String? h3OriginIndex;
  final String? h3DestinationIndex;
  final String routeCorridor;
  final double distanceKm;
  final int durationMinutes;

  // Realtime GPS Trace Fields (Start & End GPS)
  final double? startLat;
  final double? startLng;
  final DateTime? startTime;
  final String? startMapsLink;
  final double? endLat;
  final double? endLng;
  final DateTime? endTime;
  final String? endMapsLink;
  final String? routeMapsLink;
  final DateTime? createdAt;
  final String? postDate;
  final String? postTime;
  final List<String> destinationChoices;

  const RideModel({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverPhotoUrl,
    required this.driverDept,
    this.driverPhone,
    this.driverRating = 5.0,
    this.driverRideCount = 0,
    required this.originName,
    this.originSubtitle,
    required this.originLat,
    required this.originLng,
    required this.destinationName,
    this.destinationSubtitle,
    required this.destinationLat,
    required this.destinationLng,
    this.waypointName,
    required this.departureTime,
    required this.farePerSeat,
    required this.totalSeats,
    required this.availableSeats,
    this.isFemaleOnly = false,
    this.status = RideStatus.published,
    required this.vehicle,
    this.h3OriginIndex,
    this.h3DestinationIndex,
    this.routeCorridor = 'Ashulia Highway Corridor',
    this.distanceKm = 14.0,
    this.durationMinutes = 30,
    this.startLat,
    this.startLng,
    this.startTime,
    this.startMapsLink,
    this.endLat,
    this.endLng,
    this.endTime,
    this.endMapsLink,
    this.routeMapsLink,
    this.createdAt,
    this.postDate,
    this.postTime,
    this.destinationChoices = const [],
  });

  String get googleMapsRouteUrl {
    if (routeMapsLink != null && routeMapsLink!.isNotEmpty) {
      return routeMapsLink!;
    }
    final oLat = startLat ?? originLat;
    final oLng = startLng ?? originLng;
    final dLat = endLat ?? destinationLat;
    final dLng = endLng ?? destinationLng;
    return GpsLocationService.getGoogleMapsRouteUrl(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
    );
  }

  String get googleMapsStartUrl {
    if (startMapsLink != null && startMapsLink!.isNotEmpty) {
      return startMapsLink!;
    }
    return GpsLocationService.getGoogleMapsLocationUrl(
      startLat ?? originLat,
      startLng ?? originLng,
    );
  }

  String get googleMapsEndUrl {
    if (endMapsLink != null && endMapsLink!.isNotEmpty) {
      return endMapsLink!;
    }
    return GpsLocationService.getGoogleMapsLocationUrl(
      endLat ?? destinationLat,
      endLng ?? destinationLng,
    );
  }

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id: json['id'] as String,
      driverId: json['driverId'] as String,
      driverName: json['driverName'] as String,
      driverPhotoUrl: json['driverPhotoUrl'] as String?,
      driverDept: json['driverDept'] as String? ?? 'DIU Student',
      driverPhone: json['driverPhone'] as String?,
      driverRating: (json['driverRating'] as num?)?.toDouble() ?? 5.0,
      driverRideCount: json['driverRideCount'] as int? ?? 0,
      originName: json['originName'] as String,
      originSubtitle: json['originSubtitle'] as String?,
      originLat: (json['originLat'] as num).toDouble(),
      originLng: (json['originLng'] as num).toDouble(),
      destinationName: json['destinationName'] as String,
      destinationSubtitle: json['destinationSubtitle'] as String?,
      destinationLat: (json['destinationLat'] as num).toDouble(),
      destinationLng: (json['destinationLng'] as num).toDouble(),
      waypointName: json['waypointName'] as String?,
      departureTime: DateTime.tryParse(json['departureTime']?.toString() ?? '') ?? DateTime.now(),
      farePerSeat: (json['farePerSeat'] as num).toDouble(),
      totalSeats: json['totalSeats'] as int,
      availableSeats: json['availableSeats'] as int,
      isFemaleOnly: json['isFemaleOnly'] as bool? ?? false,
      status: RideStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RideStatus.published,
      ),
      vehicle: VehicleModel.fromJson(json['vehicle'] as Map<String, dynamic>),
      h3OriginIndex: json['h3OriginIndex'] as String?,
      h3DestinationIndex: json['h3DestinationIndex'] as String?,
      routeCorridor: json['routeCorridor'] as String? ?? 'Ashulia Highway Corridor',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 14.0,
      durationMinutes: json['durationMinutes'] as int? ?? 30,
      startLat: (json['startLat'] as num?)?.toDouble(),
      startLng: (json['startLng'] as num?)?.toDouble(),
      startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime'] as String) : null,
      startMapsLink: json['startMapsLink'] as String?,
      endLat: (json['endLat'] as num?)?.toDouble(),
      endLng: (json['endLng'] as num?)?.toDouble(),
      endTime: json['endTime'] != null ? DateTime.tryParse(json['endTime'] as String) : null,
      endMapsLink: json['endMapsLink'] as String?,
      routeMapsLink: json['routeMapsLink'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      postDate: json['postDate'] as String? ?? json['post_date'] as String?,
      postTime: json['postTime'] as String? ?? json['post_time'] as String?,
      destinationChoices: (json['destinationChoices'] is List)
          ? (json['destinationChoices'] as List).map((e) => e.toString()).toList()
          : ((json['destinationChoices'] is String && (json['destinationChoices'] as String).isNotEmpty)
              ? (json['destinationChoices'] as String).split(',').map((e) => e.trim()).toList()
              : const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhotoUrl': driverPhotoUrl,
      'driverDept': driverDept,
      'driverPhone': driverPhone,
      'driverRating': driverRating,
      'driverRideCount': driverRideCount,
      'originName': originName,
      'originSubtitle': originSubtitle,
      'originLat': originLat,
      'originLng': originLng,
      'destinationName': destinationName,
      'destinationSubtitle': destinationSubtitle,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'waypointName': waypointName,
      'departureTime': departureTime.toIso8601String(),
      'farePerSeat': farePerSeat,
      'totalSeats': totalSeats,
      'availableSeats': availableSeats,
      'isFemaleOnly': isFemaleOnly,
      'status': status.name,
      'vehicle': vehicle.toJson(),
      'h3OriginIndex': h3OriginIndex,
      'h3DestinationIndex': h3DestinationIndex,
      'routeCorridor': routeCorridor,
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
      'startLat': startLat,
      'startLng': startLng,
      'startTime': startTime?.toIso8601String(),
      'startMapsLink': startMapsLink,
      'endLat': endLat,
      'endLng': endLng,
      'endTime': endTime?.toIso8601String(),
      'endMapsLink': endMapsLink,
      'routeMapsLink': routeMapsLink,
      'createdAt': createdAt?.toIso8601String(),
      'postDate': postDate,
      'postTime': postTime,
      'destinationChoices': destinationChoices,
    };
  }

  RideModel copyWith({
    int? availableSeats,
    RideStatus? status,
    String? driverPhone,
    double? startLat,
    double? startLng,
    DateTime? startTime,
    String? startMapsLink,
    double? endLat,
    double? endLng,
    DateTime? endTime,
    String? endMapsLink,
    String? routeMapsLink,
    DateTime? departureTime,
    DateTime? createdAt,
    String? postDate,
    String? postTime,
    List<String>? destinationChoices,
  }) {
    return RideModel(
      id: id,
      driverId: driverId,
      driverName: driverName,
      driverPhotoUrl: driverPhotoUrl,
      driverDept: driverDept,
      driverPhone: driverPhone ?? this.driverPhone,
      driverRating: driverRating,
      driverRideCount: driverRideCount,
      originName: originName,
      originSubtitle: originSubtitle,
      originLat: originLat,
      originLng: originLng,
      destinationName: destinationName,
      destinationSubtitle: destinationSubtitle,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      waypointName: waypointName,
      departureTime: departureTime ?? this.departureTime,
      farePerSeat: farePerSeat,
      totalSeats: totalSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      isFemaleOnly: isFemaleOnly,
      status: status ?? this.status,
      vehicle: vehicle,
      h3OriginIndex: h3OriginIndex,
      h3DestinationIndex: h3DestinationIndex,
      routeCorridor: routeCorridor,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      startTime: startTime ?? this.startTime,
      startMapsLink: startMapsLink ?? this.startMapsLink,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      endTime: endTime ?? this.endTime,
      endMapsLink: endMapsLink ?? this.endMapsLink,
      routeMapsLink: routeMapsLink ?? this.routeMapsLink,
      createdAt: createdAt ?? this.createdAt,
      postDate: postDate ?? this.postDate,
      postTime: postTime ?? this.postTime,
      destinationChoices: destinationChoices ?? this.destinationChoices,
    );
  }
}
