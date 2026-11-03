class CampusLocation {
  final String id;
  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;
  final bool isCampus;
  final String? h3Index;

  const CampusLocation({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.isCampus = false,
    this.h3Index,
  });
}

class CampusLocations {
  CampusLocations._();

  // DIU Smart City, Ashulia Coordinates
  static const double diuCenterLat = 23.8769;
  static const double diuCenterLng = 90.3204;

  // DIU Campus Hotspots
  static const CampusLocation mainGate = CampusLocation(
    id: 'diu_gate_1',
    name: 'DIU Main Gate 1',
    subtitle: 'Daffodil Smart City, Ashulia',
    latitude: 23.8775,
    longitude: 90.3201,
    isCampus: true,
    h3Index: '88654c6001fffff',
  );

  static const CampusLocation transportTerminal = CampusLocation(
    id: 'diu_bus_bay',
    name: 'Transport Terminal (Bus Bay)',
    subtitle: 'Behind Academic Bldg 1, DSC',
    latitude: 23.8762,
    longitude: 90.3195,
    isCampus: true,
    h3Index: '88654c6001fffff',
  );

  static const CampusLocation academicBldg4 = CampusLocation(
    id: 'diu_ab_4',
    name: 'Academic Building 4 (Daffodil Tower)',
    subtitle: 'DSC Central Circle',
    latitude: 23.8781,
    longitude: 90.3215,
    isCampus: true,
    h3Index: '88654c6001fffff',
  );

  static const CampusLocation lakeBridge = CampusLocation(
    id: 'diu_lake_bridge',
    name: 'Campus Lake Bridge',
    subtitle: 'Knowledge City Lakeside Point',
    latitude: 23.8755,
    longitude: 90.3220,
    isCampus: true,
    h3Index: '88654c6001fffff',
  );

  static const CampusLocation sportsComplex = CampusLocation(
    id: 'diu_sports',
    name: 'DSC Sports Complex',
    subtitle: 'Cricket Ground North Pavilion',
    latitude: 23.8790,
    longitude: 90.3180,
    isCampus: true,
    h3Index: '88654c6001fffff',
  );

  // Popular Dhaka Commute Corridors
  static const CampusLocation uttaraMetro = CampusLocation(
    id: 'dest_uttara_metro',
    name: 'Metro Station (Uttara North)',
    subtitle: 'Diabari Exit Gate 2 • 18m away',
    latitude: 23.8710,
    longitude: 90.3800,
    isCampus: false,
    h3Index: '88654c6225fffff',
  );

  static const CampusLocation uttaraHouseBuilding = CampusLocation(
    id: 'dest_uttara_house_building',
    name: 'Uttara Sector 11 (House Building)',
    subtitle: 'Dhaka - Mymensingh Highway',
    latitude: 23.8735,
    longitude: 90.3985,
    isCampus: false,
    h3Index: '88654c622dfffff',
  );

  static const CampusLocation dhanmondiCampus = CampusLocation(
    id: 'dest_dhanmondi',
    name: 'Dhanmondi Campus (Sobhanbag)',
    subtitle: 'Mirpur Road, Dhanmondi 27 • 42m away',
    latitude: 23.7538,
    longitude: 90.3768,
    isCampus: false,
    h3Index: '88654c6533fffff',
  );

  static const CampusLocation mirpur10 = CampusLocation(
    id: 'dest_mirpur_10',
    name: 'Mirpur 10 Roundabout',
    subtitle: 'Metro Pillar 240, Mirpur • 28m away',
    latitude: 23.8069,
    longitude: 90.3687,
    isCampus: false,
    h3Index: '88654c628bfffff',
  );

  static const CampusLocation savarStand = CampusLocation(
    id: 'dest_savar',
    name: 'Savar Bazar Bus Stand',
    subtitle: 'Aricha Road Overbridge • 12m away',
    latitude: 23.8488,
    longitude: 90.2575,
    isCampus: false,
    h3Index: '88654c60b7fffff',
  );

  static const CampusLocation ecbChattar = CampusLocation(
    id: 'dest_ecb',
    name: 'ECB Chattar (Matikata Road)',
    subtitle: 'Cantonment Flyover Link',
    latitude: 23.8225,
    longitude: 90.3934,
    isCampus: false,
    h3Index: '88654c6211fffff',
  );

  static const CampusLocation mohakhali = CampusLocation(
    id: 'dest_mohakhali',
    name: 'Mohakhali Flyover',
    subtitle: 'Wireless Gate, Dhaka',
    latitude: 23.7778,
    longitude: 90.4044,
    isCampus: false,
    h3Index: '88654c6553fffff',
  );

  static const List<CampusLocation> allCampusSpots = [
    mainGate,
    transportTerminal,
    academicBldg4,
    lakeBridge,
    sportsComplex,
  ];

  static const List<CampusLocation> popularDestinations = [
    uttaraMetro,
    uttaraHouseBuilding,
    dhanmondiCampus,
    mirpur10,
    savarStand,
    ecbChattar,
    mohakhali,
  ];
}
