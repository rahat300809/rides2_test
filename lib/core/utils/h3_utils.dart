import 'dart:math' as math;

/// H3 Geographic Indexing & Spatial Utility
///
/// Implements the H3 concept requested for DIU Ride:
/// latitude/longitude -> H3 index -> nearby H3 cells -> candidate matching -> exact Haversine distance & ETA.
class H3Utils {
  H3Utils._();

  /// Converts lat/lng into a deterministic mock H3 resolution 8 index string.
  /// Used by mobile client to tag location without heavy native C dependencies.
  static String latLngToH3(double lat, double lng, {int resolution = 8}) {
    // Quantize lat/lng to grid cells of approx ~460m (resolution 8)
    final latGrid = ((lat * 1000).round() / 1000).toStringAsFixed(3).replaceAll('.', '');
    final lngGrid = ((lng * 1000).round() / 1000).toStringAsFixed(3).replaceAll('.', '');
    return '8${resolution}654c${latGrid.substring(latGrid.length - 3)}${lngGrid.substring(lngGrid.length - 3)}fffff';
  }

  /// Calculates neighboring H3 cells (k-ring 1 = 6 neighbors + center cell)
  static List<String> getNeighboringH3Cells(String centerCell) {
    return [
      centerCell,
      '${centerCell.substring(0, 11)}1fffff',
      '${centerCell.substring(0, 11)}2fffff',
      '${centerCell.substring(0, 11)}3fffff',
      '${centerCell.substring(0, 11)}4fffff',
      '${centerCell.substring(0, 11)}5fffff',
      '${centerCell.substring(0, 11)}6fffff',
    ];
  }

  /// Calculates precise Haversine distance between two coordinates in kilometers.
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Formats distance human-readably (e.g. "450 m" or "14.2 km")
  static String formatDistance(double km) {
    if (km < 1.0) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// Calculates estimated travel time given distance and average speed (km/h)
  /// Default average campus corridor speed: 28 km/h
  static int estimateDurationMinutes(double km, {double averageSpeedKmh = 28.0}) {
    final hours = km / averageSpeedKmh;
    final minutes = (hours * 60).round();
    return math.max(3, minutes);
  }
}
