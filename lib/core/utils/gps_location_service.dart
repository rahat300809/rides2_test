import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/services/location_search_service.dart';

class GpsLocationService {
  GpsLocationService._();

  // Default fallback (DIU Permanent Campus, Ashulia)
  static const double defaultCampusLat = 23.8765;
  static const double defaultCampusLng = 90.3204;
  static const String defaultCampusName = 'DIU Smart City, Ashulia';

  /// Detects whether coordinates match the well-known ISP gateway IP routing hub in South Dhaka / Keraniganj
  /// (e.g. 23.7100, 90.4100 where desktop browsers and broadband in Bangladesh geolocate)
  static bool isIspIpAnomaly(double lat, double lng) {
    return (lat - 23.7100).abs() < 0.025 && (lng - 90.4100).abs() < 0.025;
  }

  /// Create a synthetic Position representing DIU Permanent Campus, Ashulia
  static Position createCampusPosition() {
    return Position(
      latitude: defaultCampusLat,
      longitude: defaultCampusLng,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 10.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  /// Fetch current mobile latitude & longitude with smart ISP / web anomaly detection
  static Future<Position?> getCurrentLocation({bool filterIspAnomaly = true}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[GPS] Location services are disabled. Prompting or using fallback.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[GPS] Location permissions denied.');
          return filterIspAnomaly ? createCampusPosition() : null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Location permissions permanently denied.');
        return filterIspAnomaly ? createCampusPosition() : null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      // On Web or desktop without hardware GPS, HTML5 geolocation returns ISP IP address in Old Dhaka (23.7100, 90.4100)
      if (filterIspAnomaly && (isIspIpAnomaly(pos.latitude, pos.longitude) || (kIsWeb && pos.accuracy > 1500))) {
        debugPrint('[GPS] Detected ISP IP geolocation anomaly (${pos.latitude}, ${pos.longitude}). Correcting to DIU Campus.');
        return createCampusPosition();
      }

      return pos;
    } catch (e) {
      debugPrint('[GPS] Error fetching location: $e');
      return filterIspAnomaly ? createCampusPosition() : null;
    }
  }

  /// Resolve current location into a clean, human-readable address/campus name
  /// Never returns raw cryptic coordinates like 'Current GPS Location (23.7100, 90.4100)'
  static Future<String> getReadableCurrentLocationName() async {
    try {
      final pos = await getCurrentLocation(filterIspAnomaly: true);
      if (pos == null) return defaultCampusName;
      if (isIspIpAnomaly(pos.latitude, pos.longitude)) return defaultCampusName;

      // Check if user is on or near DIU Campus (< 2.0 km)
      final dLatCampus = (pos.latitude - defaultCampusLat).abs();
      final dLngCampus = (pos.longitude - defaultCampusLng).abs();
      if (dLatCampus < 0.018 && dLngCampus < 0.018) {
        return defaultCampusName;
      }

      // Reverse geocode to real readable place name (e.g. 'Mirpur 10', 'Uttara Sector 11')
      final address = await LocationSearchService.reverseGeocode(LatLng(pos.latitude, pos.longitude));
      if (address.isNotEmpty && !address.startsWith('Pin (')) {
        return address;
      }
      return defaultCampusName;
    } catch (_) {
      return defaultCampusName;
    }
  }

  /// Get accurate coordinates LatLng for maps and routing (guaranteed safe from ISP anomaly)
  static Future<LatLng> getAccurateCurrentCoordinates() async {
    try {
      final pos = await getCurrentLocation(filterIspAnomaly: true);
      if (pos != null) {
        if (isIspIpAnomaly(pos.latitude, pos.longitude)) {
          return const LatLng(defaultCampusLat, defaultCampusLng);
        }
        return LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    return const LatLng(defaultCampusLat, defaultCampusLng);
  }

  /// Generate a Google Maps link for a single coordinate
  static String getGoogleMapsLocationUrl(double lat, double lng) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  /// Generate a Google Maps turn-by-turn route directions link
  static String getGoogleMapsRouteUrl({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) {
    return 'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=driving';
  }

  /// Open any Google Maps URL in native Maps app or browser
  static Future<bool> openGoogleMaps(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return launched;
    } catch (e) {
      debugPrint('[GPS] Could not open Google Maps link: $e');
      return false;
    }
  }
}
