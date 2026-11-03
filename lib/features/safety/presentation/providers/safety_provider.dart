import 'package:flutter_riverpod/flutter_riverpod.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String relation;
  final String phone;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relation,
    required this.phone,
  });
}

class SafetyState {
  final bool isSosTriggered;
  final List<EmergencyContact> contacts;
  final String? lastSosIncidentId;

  const SafetyState({
    this.isSosTriggered = false,
    this.contacts = const [
      EmergencyContact(
        id: 'c1',
        name: 'Father (Guardian)',
        relation: 'Parent',
        phone: '01711223344',
      ),
      EmergencyContact(
        id: 'c2',
        name: 'DSC Proctor Office',
        relation: 'DIU Security',
        phone: '+8801711000000',
      ),
    ],
    this.lastSosIncidentId,
  });

  SafetyState copyWith({
    bool? isSosTriggered,
    List<EmergencyContact>? contacts,
    String? lastSosIncidentId,
  }) {
    return SafetyState(
      isSosTriggered: isSosTriggered ?? this.isSosTriggered,
      contacts: contacts ?? this.contacts,
      lastSosIncidentId: lastSosIncidentId ?? this.lastSosIncidentId,
    );
  }
}

class SafetyNotifier extends StateNotifier<SafetyState> {
  SafetyNotifier() : super(const SafetyState());

  void triggerSos({
    required String location,
    String? rideId,
  }) {
    final incidentId = 'SOS-${DateTime.now().millisecondsSinceEpoch}';
    state = state.copyWith(
      isSosTriggered: true,
      lastSosIncidentId: incidentId,
    );
  }

  void addContact(EmergencyContact contact) {
    state = state.copyWith(contacts: [...state.contacts, contact]);
  }

  void removeContact(String id) {
    state = state.copyWith(
      contacts: state.contacts.where((c) => c.id != id).toList(),
    );
  }

  void resetSos() {
    state = state.copyWith(isSosTriggered: false);
  }
}

final safetyNotifierProvider = StateNotifierProvider<SafetyNotifier, SafetyState>((ref) {
  return SafetyNotifier();
});
