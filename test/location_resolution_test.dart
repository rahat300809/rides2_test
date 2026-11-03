import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/core/services/location_search_service.dart';

void main() {
  group('DIU Ride - GPS & Location Resolution Tests', () {
    test('Identifies ISP IP geolocation anomaly (Keraniganj / Old Dhaka)', () {
      expect(GpsLocationService.isIspIpAnomaly(23.7100, 90.4100), isTrue);
      expect(GpsLocationService.isIspIpAnomaly(23.7104, 90.4074), isTrue);
      expect(GpsLocationService.isIspIpAnomaly(23.7150, 90.4120), isTrue);

      // DIU Campus and valid commute corridors must NOT be flagged as ISP anomalies
      expect(GpsLocationService.isIspIpAnomaly(23.8765, 90.3204), isFalse); // DIU Campus
      expect(GpsLocationService.isIspIpAnomaly(23.8710, 90.3800), isFalse); // Uttara North
      expect(GpsLocationService.isIspIpAnomaly(23.8069, 90.3687), isFalse); // Mirpur 10
    });

    test('Safely intercepts legacy raw GPS coordinate strings matching ISP anomaly', () {
      final coords = LocationSearchService.lookupCoordinates('Current GPS Location (23.7100, 90.4100)');
      expect(coords.latitude, closeTo(23.8765, 0.001));
      expect(coords.longitude, closeTo(90.3204, 0.001));
    });

    test('Resolves known campus and city corridor landmarks accurately', () {
      final uttara = LocationSearchService.lookupCoordinates('Uttara North');
      expect(uttara.latitude, closeTo(23.8710, 0.01));
      expect(uttara.longitude, closeTo(90.3800, 0.01));

      final mirpur = LocationSearchService.lookupCoordinates('Mirpur 10');
      expect(mirpur.latitude, closeTo(23.8069, 0.01));
      expect(mirpur.longitude, closeTo(90.3687, 0.01));

      final diu = LocationSearchService.lookupCoordinates('DIU Smart City, Ashulia');
      expect(diu.latitude, closeTo(23.8765, 0.005));
      expect(diu.longitude, closeTo(90.3204, 0.005));
    });

    test('Reverse geocoding corrects ISP anomaly to DIU Smart City', () async {
      final ispName = await LocationSearchService.reverseGeocode(const LatLng(23.7100, 90.4100));
      expect(ispName, equals('DIU Smart City, Ashulia'));

      final campusName = await LocationSearchService.reverseGeocode(const LatLng(23.8765, 90.3204));
      expect(campusName.contains('DIU') || campusName.contains('Campus') || campusName.contains('Ashulia'), isTrue);
    });
  });
}

