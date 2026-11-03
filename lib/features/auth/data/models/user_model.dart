enum UserRole { student, admin, guest }

class UserModel {
  final String id;
  final String studentId;
  final String name;
  final String email;
  final String phone;
  final String? profilePhotoUrl;
  final String department;
  final String batch;
  final bool isDiuVerified;
  final UserRole role;
  final double rating;
  final int totalRidesAsPassenger;
  final int totalRidesAsDriver;
  final bool isDriverRegistered;
  final String? vehicleInfo;
  final String? defaultAddress;
  final bool isGuest;

  bool get isVisitor => isGuest || id == 'guest_visitor' || studentId == 'VISITOR-GUEST';
  bool get isBiker => !isVisitor && (isDriverRegistered || (vehicleInfo != null && vehicleInfo!.isNotEmpty));
  String? get vehicleModel => vehicleInfo;

  const UserModel({
    required this.id,
    required this.studentId,
    required this.name,
    required this.email,
    required this.phone,
    this.profilePhotoUrl,
    required this.department,
    required this.batch,
    this.isDiuVerified = true,
    this.role = UserRole.student,
    this.rating = 5.0,
    this.totalRidesAsPassenger = 0,
    this.totalRidesAsDriver = 0,
    this.isDriverRegistered = false,
    this.vehicleInfo,
    this.defaultAddress,
    this.isGuest = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final uid = json['id'] as String? ?? 'usr_${DateTime.now().millisecondsSinceEpoch}';
    final sid = json['studentId'] as String? ?? '211-15-00000';
    final guestFlag = json['isGuest'] as bool? ?? (uid == 'guest_visitor' || sid == 'VISITOR-GUEST');
    return UserModel(
      id: uid,
      studentId: sid,
      name: json['name'] as String? ?? (guestFlag ? 'Guest Explorer' : 'DIU Student'),
      email: json['email'] as String? ?? 'student@diu.edu.bd',
      phone: json['phone'] as String? ?? '01712345678',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      department: json['department'] as String? ?? (guestFlag ? 'Campus Visitor' : 'CSE'),
      batch: json['batch'] as String? ?? (guestFlag ? 'Trial Mode' : 'Batch 54'),
      isDiuVerified: json['isDiuVerified'] as bool? ?? (!guestFlag),
      role: json['role'] == 'admin' ? UserRole.admin : (guestFlag ? UserRole.guest : UserRole.student),
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalRidesAsPassenger: json['totalRidesAsPassenger'] as int? ?? 0,
      totalRidesAsDriver: json['totalRidesAsDriver'] as int? ?? 0,
      isDriverRegistered: json['isDriverRegistered'] as bool? ?? false,
      vehicleInfo: json['vehicleInfo'] as String?,
      defaultAddress: json['defaultAddress'] as String? ?? json['default_address'] as String?,
      isGuest: guestFlag,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'name': name,
      'email': email,
      'phone': phone,
      'profilePhotoUrl': profilePhotoUrl,
      'department': department,
      'batch': batch,
      'isDiuVerified': isDiuVerified,
      'role': role == UserRole.admin ? 'admin' : (isGuest ? 'guest' : 'student'),
      'rating': rating,
      'totalRidesAsPassenger': totalRidesAsPassenger,
      'totalRidesAsDriver': totalRidesAsDriver,
      'isDriverRegistered': isDriverRegistered,
      'vehicleInfo': vehicleInfo,
      'defaultAddress': defaultAddress,
      'isGuest': isGuest,
    };
  }

  UserModel copyWith({
    String? name,
    String? phone,
    String? profilePhotoUrl,
    String? department,
    String? batch,
    bool? isDriverRegistered,
    String? vehicleInfo,
    double? rating,
    int? totalRidesAsPassenger,
    int? totalRidesAsDriver,
    String? defaultAddress,
    bool? isGuest,
  }) {
    return UserModel(
      id: id,
      studentId: studentId,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      department: department ?? this.department,
      batch: batch ?? this.batch,
      isDiuVerified: isDiuVerified,
      role: role,
      rating: rating ?? this.rating,
      totalRidesAsPassenger: totalRidesAsPassenger ?? this.totalRidesAsPassenger,
      totalRidesAsDriver: totalRidesAsDriver ?? this.totalRidesAsDriver,
      isDriverRegistered: isDriverRegistered ?? this.isDriverRegistered,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
      defaultAddress: defaultAddress ?? this.defaultAddress,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
