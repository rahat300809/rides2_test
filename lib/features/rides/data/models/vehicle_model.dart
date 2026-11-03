enum VehicleType { bike, car, microbus }

class VehicleModel {
  final String id;
  final VehicleType type;
  final String modelName;
  final String color;
  final String licensePlate;
  final bool hasAc;
  final bool hasPassengerHelmet;
  final bool isSmokeFree;
  final bool hasPhoneCharger;
  final bool hasLuggageSpace;

  const VehicleModel({
    required this.id,
    required this.type,
    required this.modelName,
    required this.color,
    required this.licensePlate,
    this.hasAc = false,
    this.hasPassengerHelmet = false,
    this.isSmokeFree = true,
    this.hasPhoneCharger = true,
    this.hasLuggageSpace = false,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String? ?? 'veh_${DateTime.now().millisecondsSinceEpoch}',
      type: VehicleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => VehicleType.bike,
      ),
      modelName: json['modelName'] as String? ?? json['model'] as String? ?? 'Motorbike',
      color: json['color'] as String? ?? 'Black',
      licensePlate: json['licensePlate'] as String? ?? 'Dhaka Metro',
      hasAc: json['hasAc'] as bool? ?? false,
      hasPassengerHelmet: json['hasPassengerHelmet'] as bool? ?? true,
      isSmokeFree: json['isSmokeFree'] as bool? ?? true,
      hasPhoneCharger: json['hasPhoneCharger'] as bool? ?? true,
      hasLuggageSpace: json['hasLuggageSpace'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'modelName': modelName,
      'color': color,
      'licensePlate': licensePlate,
      'hasAc': hasAc,
      'hasPassengerHelmet': hasPassengerHelmet,
      'isSmokeFree': isSmokeFree,
      'hasPhoneCharger': hasPhoneCharger,
      'hasLuggageSpace': hasLuggageSpace,
    };
  }
}
