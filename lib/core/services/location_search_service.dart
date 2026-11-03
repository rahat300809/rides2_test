import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:diu_ride/core/config/app_config.dart';

class LocationSearchResult {
  final String title;
  final String subtitle;
  final double lat;
  final double lng;
  final String category; // 'campus' | 'metro' | 'hub' | 'city'
  final String? placeId;

  const LocationSearchResult({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.category = 'city',
    this.placeId,
  });

  LatLng get latLng => LatLng(lat, lng);
}

class RouteSuggestion {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final int durationMinutes;
  final String summary;
  final String source; // 'google_routes' | 'osrm' | 'direct'

  const RouteSuggestion({
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMinutes,
    required this.summary,
    required this.source,
  });
}

class LocationSearchService {
  static const String googleApiKey = 'AIzaSyD-hl4Vshm6lqgUopu4rHbwmUbbPNA7kfA';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent': 'DIU-Ride-App/1.0',
        'Accept': 'application/json',
      },
    ),
  );

  /// Safe API Base URL pointing to local/remote server proxy
  static String get _apiBaseUrl {
    try {
      final base = AppConfig.current.apiBaseUrl;
      if (base.isNotEmpty) return base;
    } catch (_) {}
    return AppConfig.fallbackApiUrl;
  }

  /// Cache for placeId to LatLng details
  static final Map<String, LatLng> _placeLocationCache = {};

  /// Comprehensive DIU Campus, Metro Stations & Key Dhaka Commute Hubs
  /// Enables instantaneous (0ms) offline typing matches for "moti", "mir", "dhan", "utt", etc.
  static const List<LocationSearchResult> campusLandmarks = [
    // --- DIU Campus Core ---
    LocationSearchResult(
      title: 'DIU Main Gate 1',
      subtitle: 'Daffodil Smart City, Ashulia (Central Bike Stand)',
      lat: 23.8775,
      lng: 90.3201,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'DIU Gate 2 (Engineering Complex)',
      subtitle: 'DSC East Wing, Daffodil Smart City',
      lat: 23.8790,
      lng: 90.3215,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Academic Building 4 (AB-4 Daffodil Tower)',
      subtitle: 'CSE, Software Engineering & Tech Depts, DSC',
      lat: 23.8781,
      lng: 90.3215,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Campus Lake Bridge & Cafeteria',
      subtitle: 'Food Court & Lakeside connector, DSC',
      lat: 23.8755,
      lng: 90.3220,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Transport Terminal & Bus Bay',
      subtitle: 'Behind Academic Bldg 1, DSC Ashulia',
      lat: 23.8762,
      lng: 90.3195,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Birulia Bridge Crossing',
      subtitle: 'Birulia - Ashulia Highway Link',
      lat: 23.8685,
      lng: 90.3340,
      category: 'hub',
    ),

    // --- Motijheel Corridor ---
    LocationSearchResult(
      title: 'Motijheel Commercial Area',
      subtitle: 'Shapla Chattar & Bangladesh Bank, Dhaka',
      lat: 23.7330,
      lng: 90.4172,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Motijheel Metro Rail Station',
      subtitle: 'MRT Line-6 Terminal, Dilkusha, Dhaka',
      lat: 23.7305,
      lng: 90.4180,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Motijheel Model School & College',
      subtitle: 'Outer Circular Road, Motijheel, Dhaka',
      lat: 23.7335,
      lng: 90.4240,
      category: 'city',
    ),

    // --- Uttara & Diabari Corridor ---
    LocationSearchResult(
      title: 'Uttara North Metro Station',
      subtitle: 'Diabari Exit 2, Metro Rail Line 6',
      lat: 23.8710,
      lng: 90.3800,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Uttara Center Metro Station',
      subtitle: 'Sector 15 & Diabari Lake Connector',
      lat: 23.8640,
      lng: 90.3850,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Uttara House Building (Sector 7/9)',
      subtitle: 'Dhaka - Mymensingh Highway Overbridge',
      lat: 23.8735,
      lng: 90.3985,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Uttara Sector 10 / Kamarpara',
      subtitle: 'Kamarpara Bridge & Ashulia Link',
      lat: 23.8820,
      lng: 90.3850,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Uttara Sector 11 Bus Stand',
      subtitle: 'Gareeb-e-Newaz Avenue, Uttara, Dhaka',
      lat: 23.8750,
      lng: 90.3880,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Jasimuddin Road Bus Stand',
      subtitle: 'Airport Road, Uttara Sector 3, Dhaka',
      lat: 23.8610,
      lng: 90.3995,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Hazrat Shahjalal International Airport',
      subtitle: 'Terminal 1 & 2, Airport Road, Dhaka',
      lat: 23.8510,
      lng: 90.4000,
      category: 'hub',
    ),

    // --- Mirpur Corridor ---
    LocationSearchResult(
      title: 'Mirpur 10 Roundabout (Metro Hub)',
      subtitle: 'Metro Pillar 240, Mirpur Central, Dhaka',
      lat: 23.8069,
      lng: 90.3687,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Mirpur 11 Metro Station',
      subtitle: 'Mirpur 11 Bus Stand & Metro Gate, Dhaka',
      lat: 23.8180,
      lng: 90.3660,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Mirpur 1 / Sony Square',
      subtitle: 'Zoo Road & Gabtoli Connector, Mirpur, Dhaka',
      lat: 23.8005,
      lng: 90.3530,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Mirpur 2 (Mirpur Stadium / Commerce College)',
      subtitle: 'National Cricket Stadium, Mirpur, Dhaka',
      lat: 23.8075,
      lng: 90.3615,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Mirpur 12 Bus Terminal',
      subtitle: 'Pallabi Metro & Eastern Housing corridor, Mirpur',
      lat: 23.8290,
      lng: 90.3645,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Mirpur 14 / Police Staff College',
      subtitle: 'Kochukhet & Cantonment Road link, Mirpur',
      lat: 23.7980,
      lng: 90.3820,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Mirpur 6 / 7 (Section 6, Milk Vita)',
      subtitle: 'Mirpur 6 & 7 Market, Dhaka',
      lat: 23.8110,
      lng: 90.3605,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Mirpur DOHS Gate',
      subtitle: 'Mirpur DOHS Avenue 1, Dhaka',
      lat: 23.8340,
      lng: 90.3710,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Pallabi Metro Station (Mirpur 12)',
      subtitle: 'Metro Rail Line-6, Mirpur, Dhaka',
      lat: 23.8240,
      lng: 90.3640,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Shewrapara Metro Station (Mirpur)',
      subtitle: 'Mirpur Road, Shewrapara, Dhaka',
      lat: 23.7885,
      lng: 90.3730,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Kazipara Metro Station (Mirpur)',
      subtitle: 'Mirpur Road, Kazipara, Dhaka',
      lat: 23.7975,
      lng: 90.3715,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'ECB Chattar (Matikata Road)',
      subtitle: 'Mirpur DOHS & Cantonment Flyover',
      lat: 23.8225,
      lng: 90.3934,
      category: 'hub',
    ),

    // --- Dhanmondi & West Dhaka ---
    LocationSearchResult(
      title: 'Dhanmondi Campus (Sobhanbag)',
      subtitle: 'Mirpur Road, Dhanmondi 27, Dhaka',
      lat: 23.7538,
      lng: 90.3768,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Dhanmondi 32 / Shukrabad',
      subtitle: 'Metro Pillar & Bangabandhu Museum',
      lat: 23.7510,
      lng: 90.3775,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Shyamoli Square / Bus Stand',
      subtitle: 'Mirpur Road & Ring Road crossing',
      lat: 23.7715,
      lng: 90.3640,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Kalyanpur Bus Stand',
      subtitle: 'Mirpur Road Interdistrict Bus Counter',
      lat: 23.7820,
      lng: 90.3610,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Gabtoli Interdistrict Bus Terminal',
      subtitle: 'Mazar Road, Aricha Highway crossing',
      lat: 23.7840,
      lng: 90.3420,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Mohammadpur Town Hall / Bus Stand',
      subtitle: 'Asad Gate & Ring Road connector',
      lat: 23.7620,
      lng: 90.3610,
      category: 'city',
    ),

    // --- Central & East Dhaka ---
    LocationSearchResult(
      title: 'Farmgate Overbridge & Metro Station',
      subtitle: 'Ananda Cinema & Indira Road Hub',
      lat: 23.7570,
      lng: 90.3888,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Mohakhali Wireless Gate',
      subtitle: 'Mohakhali Interdistrict Bus Terminal',
      lat: 23.7780,
      lng: 90.4000,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Kuril Flyover / Biswa Road',
      subtitle: 'Airport Road & 300 Feet Highway link',
      lat: 23.8180,
      lng: 90.4180,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Gulshan 1 Circle',
      subtitle: 'Gulshan Badda Link Road & DCC Market',
      lat: 23.7800,
      lng: 90.4160,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Gulshan 2 Circle',
      subtitle: 'Kamal Ataturk Avenue & Madani Avenue',
      lat: 23.7940,
      lng: 90.4140,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Banani Road 11 / Kamal Ataturk',
      subtitle: 'Banani Rail Station & Bridge',
      lat: 23.7930,
      lng: 90.4040,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Shahbagh Square / BSMMU',
      subtitle: 'Dhaka University & TSC area',
      lat: 23.7380,
      lng: 90.3955,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Kakrail Mosque / Shantinagar',
      subtitle: 'VIP Road & Circuit House crossing',
      lat: 23.7390,
      lng: 90.4080,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Rampura Bridge / Hatirjheel',
      subtitle: 'DIT Road & Hatirjheel Water Taxi',
      lat: 23.7630,
      lng: 90.4260,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Sayedabad Bus Terminal',
      subtitle: 'Jatrabari Flyover entry, South Dhaka',
      lat: 23.7140,
      lng: 90.4320,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Sadarghat Launch Terminal',
      subtitle: 'Buriganga Riverfront, Old Dhaka',
      lat: 23.7040,
      lng: 90.4120,
      category: 'hub',
    ),

    // --- Savar & Highway Corridor ---
    LocationSearchResult(
      title: 'Savar Bazar Bus Stand',
      subtitle: 'Dhaka-Aricha Highway Overbridge',
      lat: 23.8488,
      lng: 90.2575,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Baipayl Intersection',
      subtitle: 'EPZ & Chandra Highway crossing, Savar',
      lat: 23.9350,
      lng: 90.2780,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Nabinagar Smrity Soudho',
      subtitle: 'National Martyrs Memorial & Highway Link',
      lat: 23.9110,
      lng: 90.2540,
      category: 'hub',
    ),
  ];

  /// Bangladeshi Phonetic & Typo Normalization Dictionary
  static const Map<String, String> commonTypoCorrections = {
    'motijil': 'motijheel',
    'motijl': 'motijheel',
    'motijhil': 'motijheel',
    'motejheel': 'motijheel',
    'motejil': 'motijheel',
    'motijel': 'motijheel',
    'dhanmondy': 'dhanmondi',
    'danmondi': 'dhanmondi',
    'dhanmandi': 'dhanmondi',
    'danmandi': 'dhanmondi',
    'mirpor': 'mirpur',
    'mirpr': 'mirpur',
    'mirpurr': 'mirpur',
    'mirpur10': 'mirpur 10',
    'mirpur1': 'mirpur 1',
    'mirpur2': 'mirpur 2',
    'mirpur11': 'mirpur 11',
    'mirpur12': 'mirpur 12',
    'mirpur14': 'mirpur 14',
    'uttora': 'uttara',
    'utara': 'uttara',
    'uttra': 'uttara',
    'diabari': 'uttara north metro',
    'diyabari': 'uttara north metro',
    'asulia': 'ashulia',
    'ashulea': 'ashulia',
    'ashula': 'ashulia',
    'farmget': 'farmgate',
    'farmgait': 'farmgate',
    'gulsan': 'gulshan',
    'bonani': 'banani',
    'mohakali': 'mohakhali',
    'khagon': 'khagan',
    'khagan bazar': 'khagan',
    'birulea': 'birulia',
    'gabtali': 'gabtoli',
    'kolyanpur': 'kalyanpur',
    'kallanpur': 'kalyanpur',
    'sabar': 'savar',
    'daffodil': 'daffodil smart city',
    'dafodil': 'daffodil smart city',
    'diu': 'diu main gate',
    'dsc': 'daffodil smart city',
    'ab4': 'academic building 4',
    'hatirjil': 'hatirjheel',
  };

  /// Instant local synchronous lookup for 0ms typing suggestions
  static List<LocationSearchResult> getLocalMatches(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return campusLandmarks.take(8).toList();
    }

    final queryWords = clean.split(RegExp(r'\s+'));
    final correctedWords = queryWords.map((w) => commonTypoCorrections[w] ?? w).toList();
    final normalizedQuery = correctedWords.join(' ');

    final exactMatches = <LocationSearchResult>[];
    final prefixMatches = <LocationSearchResult>[];
    final containsMatches = <LocationSearchResult>[];
    final fuzzyMatches = <LocationSearchResult>[];

    for (final lm in campusLandmarks) {
      final t = lm.title.toLowerCase();
      final s = lm.subtitle.toLowerCase();
      if (t == clean || clean == t) {
        exactMatches.add(lm);
      } else if (t.startsWith(clean) || t.startsWith(normalizedQuery)) {
        prefixMatches.add(lm);
      } else if (t.contains(clean) || clean.contains(t) || t.contains(normalizedQuery)) {
        containsMatches.add(lm);
      } else if (s.contains(clean) || s.contains(normalizedQuery)) {
        fuzzyMatches.add(lm);
      } else if (_isFuzzyMatch(t, clean) || _isFuzzyMatch(t, normalizedQuery)) {
        fuzzyMatches.add(lm);
      }
    }

    final combined = [...exactMatches, ...prefixMatches, ...containsMatches, ...fuzzyMatches];
    final seen = <String>{};
    return combined.where((item) => seen.add(item.title)).toList();
  }

  /// Bengali phonetic transliteration normalizer for resilient typo matching
  static String _normalizePhonetics(String s) {
    return s
        .toLowerCase()
        .replaceAll('sh', 's')
        .replaceAll('jh', 'j')
        .replaceAll('dh', 'd')
        .replaceAll('th', 't')
        .replaceAll('bh', 'b')
        .replaceAll('kh', 'k')
        .replaceAll('gh', 'g')
        .replaceAll('ph', 'p')
        .replaceAll('z', 'j')
        .replaceAll('ee', 'i')
        .replaceAll('ea', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('y', 'i')
        .replaceAll('v', 'b')
        .replaceAll('w', 'b')
        .replaceAll('o', 'a')
        .replaceAll(RegExp(r'([a-z])\1+'), r'$1')
        .trim();
  }

  /// Computes Levenshtein edit distance between two strings
  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// Checks if target string fuzzy matches query (typo tolerant + phonetic)
  static bool _isFuzzyMatch(String target, String query) {
    final cleanT = target.toLowerCase();
    final cleanQ = query.toLowerCase().trim();
    if (cleanT.contains(cleanQ)) return true;

    // Direct phonetic normalizer match
    final normT = _normalizePhonetics(cleanT);
    final normQ = _normalizePhonetics(cleanQ);
    if (normT.contains(normQ) || normQ.contains(normT)) return true;

    final tWords = cleanT.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2);
    final qWords = cleanQ.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2);

    for (final q in qWords) {
      final nq = _normalizePhonetics(q);
      for (final t in tWords) {
        final nt = _normalizePhonetics(t);
        if (t.startsWith(q) || q.startsWith(t)) return true;
        if (nt.startsWith(nq) || nq.startsWith(nt)) return true;

        final maxDist = q.length >= 7 ? 3 : (q.length > 4 ? 2 : 1);
        if (_levenshtein(t, q) <= maxDist) return true;
        if (_levenshtein(nt, nq) <= maxDist) return true;
      }
    }
    return false;
  }

  /// Live Search with typing suggestions & Typo-Tolerant Matching:
  /// 0. Instant Landmark & Hub Match with Substring + Fuzzy + Typo Normalization
  /// 1. Backend Server Proxy (`/ride/api/places/autocomplete`) -> 100% CORS-free on Web & Native!
  /// 2. Direct Google Places (New) Autocomplete API with Bangladesh filter (`includedRegionCodes: ["bd"]`)
  /// 3. Photon / OpenStreetMap high-speed geocoding fallback
  static Future<List<LocationSearchResult>> search(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return campusLandmarks.take(8).toList();
    }

    final localMatches = getLocalMatches(clean);
    final results = List<LocationSearchResult>.from(localMatches);

    // Compute normalized typo query
    final queryWords = clean.split(RegExp(r'\s+'));
    final correctedWords = queryWords.map((w) => commonTypoCorrections[w] ?? w).toList();
    final normalizedQuery = correctedWords.join(' ');

    // 1. Backend Server Proxy (Works seamlessly on Web and Native)
    try {
      final queryToSend = normalizedQuery.isNotEmpty ? normalizedQuery : clean;
      final proxyUrl = '$_apiBaseUrl/places/autocomplete?q=${Uri.encodeComponent(queryToSend)}';
      final res = await _dio.get(
        proxyUrl,
        options: Options(
          sendTimeout: const Duration(milliseconds: 1600),
          receiveTimeout: const Duration(milliseconds: 1800),
        ),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'] is Map ? res.data['data'] : res.data;
        final suggestions = data['suggestions'] as List?;
        if (suggestions != null && suggestions.isNotEmpty) {
          for (final sug in suggestions.take(6)) {
            final pred = sug['placePrediction'];
            if (pred != null) {
              final placeId = (pred['placeId'] ?? pred['place'])?.toString().replaceAll('places/', '');
              final structured = pred['structuredFormat'];
              final mainText = structured?['mainText']?['text']?.toString() ??
                  pred['text']?['text']?.toString() ??
                  query;
              final secondaryText = structured?['secondaryText']?['text']?.toString() ??
                  'Dhaka, Bangladesh';

              LatLng coords = _placeLocationCache[placeId ?? ''] ??
                  _approximateCoords(mainText, secondaryText);

              if (!results.any((r) => r.title.toLowerCase() == mainText.toLowerCase())) {
                results.add(
                  LocationSearchResult(
                    title: mainText,
                    subtitle: secondaryText,
                    lat: coords.latitude,
                    lng: coords.longitude,
                    category: 'city',
                    placeId: placeId,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Direct Google Places (New) Autocomplete API (For native mobile when server proxy is unavailable)
    if (results.length < 3 && !kIsWeb) {
      try {
        final googleRes = await _dio.post(
          'https://places.googleapis.com/v1/places:autocomplete',
          options: Options(
            headers: {
              'X-Goog-Api-Key': googleApiKey,
              'Content-Type': 'application/json',
            },
          ),
          data: {
            'input': query,
            'includedRegionCodes': ['bd'],
          },
        );

        if (googleRes.statusCode == 200 && googleRes.data is Map) {
          final suggestions = googleRes.data['suggestions'] as List?;
          if (suggestions != null && suggestions.isNotEmpty) {
            for (final sug in suggestions.take(6)) {
              final pred = sug['placePrediction'];
              if (pred != null) {
                final placeId = (pred['placeId'] ?? pred['place'])?.toString().replaceAll('places/', '');
                final structured = pred['structuredFormat'];
                final mainText = structured?['mainText']?['text']?.toString() ??
                    pred['text']?['text']?.toString() ??
                    query;
                final secondaryText = structured?['secondaryText']?['text']?.toString() ??
                    'Dhaka, Bangladesh';

                LatLng coords = _placeLocationCache[placeId ?? ''] ??
                    _approximateCoords(mainText, secondaryText);

                results.add(
                  LocationSearchResult(
                    title: mainText,
                    subtitle: secondaryText,
                    lat: coords.latitude,
                    lng: coords.longitude,
                    category: 'city',
                    placeId: placeId,
                  ),
                );
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Fallback: Photon / OpenStreetMap Autocomplete
    if (results.length < 3) {
      try {
        final fallbackUrl =
            'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=6&bbox=88.0,20.5,92.7,26.6';
        final res = await _dio.get(fallbackUrl);
        if (res.statusCode == 200 && res.data is Map && res.data['features'] is List) {
          final features = res.data['features'] as List;
          for (final f in features) {
            final props = f['properties'] as Map?;
            final coords = f['geometry']?['coordinates'] as List?;
            if (props != null && coords != null && coords.length >= 2) {
              final name = props['name']?.toString() ?? query;
              final city = props['city']?.toString() ?? props['county']?.toString() ?? 'Dhaka';
              final district = props['district']?.toString() ?? 'Bangladesh';
              final lng = (coords[0] as num).toDouble();
              final lat = (coords[1] as num).toDouble();

              results.add(
                LocationSearchResult(
                  title: name,
                  subtitle: '$city, $district',
                  lat: lat,
                  lng: lng,
                  category: 'city',
                ),
              );
            }
          }
        }
      } catch (_) {}
    }

    return _deduplicate(results);
  }

  /// Fetches exact coordinates for a Google Place ID
  static Future<LatLng?> getPlaceCoordinates(String placeId) async {
    final cleanId = placeId.replaceAll('places/', '');
    if (_placeLocationCache.containsKey(cleanId)) {
      return _placeLocationCache[cleanId];
    }

    // 1. Try Backend Proxy
    try {
      final proxyUrl = '$_apiBaseUrl/places/details?place_id=$cleanId';
      final res = await _dio.get(proxyUrl);
      if (res.statusCode == 200 && res.data is Map) {
        final lat = (res.data['lat'] as num?)?.toDouble();
        final lng = (res.data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final point = LatLng(lat, lng);
          _placeLocationCache[cleanId] = point;
          return point;
        }
      }
    } catch (_) {}

    // 2. Direct Google Places API fallback (for native)
    if (!kIsWeb) {
      try {
        final res = await _dio.get(
          'https://places.googleapis.com/v1/places/$cleanId?fields=id,displayName,location,formattedAddress',
          options: Options(
            headers: {'X-Goog-Api-Key': googleApiKey},
          ),
        );

        if (res.statusCode == 200 && res.data is Map) {
          final loc = res.data['location'];
          if (loc != null) {
            final lat = (loc['latitude'] as num).toDouble();
            final lng = (loc['longitude'] as num).toDouble();
            final point = LatLng(lat, lng);
            _placeLocationCache[cleanId] = point;
            return point;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Calculates real road path suggestion like Google Maps:
  /// 1. Backend Server Proxy (`/ride/api/places/routes`) -> Proxies Google Routes / OSRM, 100% CORS-free!
  /// 2. Direct Google Routes API (computeRoutes) for Native.
  /// 3. Direct OSRM Driving Engine.
  /// 4. Direct smooth polyline fallback.
  static Future<RouteSuggestion> getRoute(LatLng origin, LatLng destination) async {
    // 1. Try Backend Server Proxy (/ride/api/places/routes)
    try {
      final proxyUrl =
          '$_apiBaseUrl/places/routes?origin_lat=${origin.latitude}&origin_lng=${origin.longitude}&dest_lat=${destination.latitude}&dest_lng=${destination.longitude}';
      final res = await _dio.get(proxyUrl);
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'] is Map ? res.data['data'] : res.data;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first;
          final encoded = route['polyline']?['encodedPolyline'] as String?;
          final distanceMeters = (route['distanceMeters'] as num?)?.toDouble() ?? 0.0;
          final durationStr = route['duration'] as String? ?? '1800s';
          final durationSec = int.tryParse(durationStr.replaceAll('s', '')) ?? 1800;

          if (encoded != null && encoded.isNotEmpty) {
            final points = decodePolyline(encoded);
            if (points.isNotEmpty) {
              return RouteSuggestion(
                polylinePoints: points,
                distanceKm: (distanceMeters / 1000.0),
                durationMinutes: (durationSec / 60.0).round(),
                summary: route['description'] ?? 'Fastest route via Google Maps',
                source: 'google_routes',
              );
            }
          }

          // If OSRM was proxied:
          final coords = route['geometry']?['coordinates'] as List?;
          if (coords != null && coords.isNotEmpty) {
            final points = coords.map((c) {
              final lng = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();

            final distM = (route['distance'] as num?)?.toDouble() ?? distanceMeters;
            final durSec = (route['duration'] as num?)?.toDouble() ?? durationSec.toDouble();

            return RouteSuggestion(
              polylinePoints: points,
              distanceKm: (distM / 1000.0),
              durationMinutes: (durSec / 60.0).round(),
              summary: 'Road Route via Dhaka Arterial Corridors',
              source: 'osrm',
            );
          }
        }
      }
    } catch (_) {}

    // 2. Direct Google Routes API (computeRoutes) for Native
    if (!kIsWeb) {
      try {
        final res = await _dio.post(
          'https://routes.googleapis.com/directions/v2:computeRoutes',
          options: Options(
            headers: {
              'X-Goog-Api-Key': googleApiKey,
              'Content-Type': 'application/json',
              'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.description',
            },
          ),
          data: {
            'origin': {
              'location': {
                'latLng': {
                  'latitude': origin.latitude,
                  'longitude': origin.longitude,
                }
              }
            },
            'destination': {
              'location': {
                'latLng': {
                  'latitude': destination.latitude,
                  'longitude': destination.longitude,
                }
              }
            },
            'travelMode': 'DRIVE',
          },
        );

        if (res.statusCode == 200 && res.data is Map) {
          final routes = res.data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final route = routes.first;
            final encoded = route['polyline']?['encodedPolyline'] as String?;
            final distanceMeters = (route['distanceMeters'] as num?)?.toDouble() ?? 0.0;
            final durationStr = route['duration'] as String? ?? '1800s';
            final durationSec = int.tryParse(durationStr.replaceAll('s', '')) ?? 1800;

            if (encoded != null && encoded.isNotEmpty) {
              final points = decodePolyline(encoded);
              if (points.isNotEmpty) {
                return RouteSuggestion(
                  polylinePoints: points,
                  distanceKm: (distanceMeters / 1000.0),
                  durationMinutes: (durationSec / 60.0).round(),
                  summary: route['description'] ?? 'Fastest route via Google Maps',
                  source: 'google_routes',
                );
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. High-Accuracy OSRM Routing Fallback
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map) {
        final routes = res.data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes.first;
          final geometry = r['geometry'];
          final distanceM = (r['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSec = (r['duration'] as num?)?.toDouble() ?? 1200.0;
          final coords = geometry?['coordinates'] as List?;

          if (coords != null && coords.isNotEmpty) {
            final points = coords.map((c) {
              final lng = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();

            return RouteSuggestion(
              polylinePoints: points,
              distanceKm: (distanceM / 1000.0),
              durationMinutes: (durationSec / 60.0).round(),
              summary: 'Road Route via Dhaka Arterial Corridors',
              source: 'osrm',
            );
          }
        }
      }
    } catch (_) {}

    // 4. Fallback: Interpolated smooth points
    final distanceKm = _haversineDistanceKm(origin, destination);
    final durationMins = (distanceKm / 35.0 * 60).round().clamp(10, 180);
    final interpolated = _generateSmoothRoute(origin, destination);

    return RouteSuggestion(
      polylinePoints: interpolated,
      distanceKm: distanceKm,
      durationMinutes: durationMins,
      summary: 'Direct Commute Path',
      source: 'direct',
    );
  }

  /// Reverse geocodes a coordinate to a human-readable location name
  static Future<String> reverseGeocode(LatLng point) async {
    // 0. Detect ISP IP Geolocation Anomaly (Old Dhaka / Keraniganj 23.71, 90.41)
    // On desktop browsers in Bangladesh without GPS hardware, HTML5 geolocation points to Sadarghat/Keraniganj ISP exchange.
    if ((point.latitude - 23.7100).abs() < 0.025 && (point.longitude - 90.4100).abs() < 0.025) {
      return 'DIU Smart City, Ashulia';
    }

    // 1. Check if on or near DIU Campus (within ~2 km of DIU Permanent Campus)
    final dLatCampus = (23.8765 - point.latitude).abs();
    final dLngCampus = (90.3204 - point.longitude).abs();
    if (dLatCampus < 0.020 && dLngCampus < 0.020) {
      for (final lm in campusLandmarks) {
        final dLat = (lm.lat - point.latitude).abs();
        final dLng = (lm.lng - point.longitude).abs();
        if (dLat < 0.0035 && dLng < 0.0035) {
          return lm.title;
        }
      }
      return 'DIU Smart City, Ashulia';
    }

    // 2. Check if near any other landmark in database (within 400 meters)
    for (final lm in campusLandmarks) {
      final dLat = (lm.lat - point.latitude).abs();
      final dLng = (lm.lng - point.longitude).abs();
      if (dLat < 0.0035 && dLng < 0.0035) {
        return lm.title;
      }
    }

    // 3. Try Google Geocoding reverse lookup
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${point.latitude},${point.longitude}&key=$googleApiKey';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final results = res.data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final addr = results.first['formatted_address'] as String?;
          if (addr != null && addr.isNotEmpty) {
            final clean = addr.split(',').take(2).join(', ').trim();
            if (!clean.toLowerCase().contains('keraniganj') && !clean.toLowerCase().contains('sadarghat')) {
              return clean;
            }
          }
        }
      }
    } catch (_) {}

    // 4. Fallback to OpenStreetMap reverse
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map) {
        final addr = res.data['display_name'] as String?;
        if (addr != null && addr.isNotEmpty) {
          final clean = addr.split(',').take(2).join(', ').trim();
          if (!clean.toLowerCase().contains('keraniganj') && !clean.toLowerCase().contains('sadarghat')) {
            return clean;
          }
        }
      }
    } catch (_) {}

    return 'DIU Smart City, Ashulia';
  }

  /// Decodes Google encoded polyline string into List of LatLng points.
  /// Web-safe: Uses arithmetic shift inversion without `~` to prevent Dart2js unsigned integer overflow.
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      // Web-safe signed delta calculation (replaces `~(result >> 1)` which breaks in Dart2js)
      final int dlat = ((result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      // Web-safe signed delta calculation
      final int dlng = ((result & 1) != 0 ? -((result >> 1) + 1) : (result >> 1));
      lng += dlng;

      final double finalLat = lat / 1E5;
      final double finalLng = lng / 1E5;
      // Sanity clamp to valid Earth coordinates
      if (finalLat >= -90.0 && finalLat <= 90.0 && finalLng >= -180.0 && finalLng <= 180.0) {
        poly.add(LatLng(finalLat, finalLng));
      }
    }
    return poly;
  }

  static double _haversineDistanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final aVal = sinLat * sinLat +
        math.cos(a.latitude * math.pi / 180.0) *
            math.cos(b.latitude * math.pi / 180.0) *
            sinLng *
            sinLng;
    final c = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
    return r * c;
  }

  static List<LatLng> _generateSmoothRoute(LatLng a, LatLng b) {
    final List<LatLng> points = [];
    const steps = 12;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      // Add slight curvature
      final lat = a.latitude + (b.latitude - a.latitude) * t;
      final lng = a.longitude + (b.longitude - a.longitude) * t;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  static LatLng _approximateCoords(String title, String subtitle) {
    final cleanTitle = title.trim().toLowerCase();
    final s = '$title $subtitle'.toLowerCase();

    // 0. Catch legacy or external "Current GPS Location" strings or ISP IP anomalies
    if (s.contains('current gps location') && (s.contains('23.71') || s.contains('90.41') || !s.contains(','))) {
      return const LatLng(23.8765, 90.3204); // Default accurately to DIU Campus
    }

    // 1. Direct GPS coordinate regex check: e.g. "(23.8765, 90.3204)" or "23.8765, 90.3204"
    final coordMatch = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)').firstMatch(s);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        // Protect against ISP IP anomaly (23.71, 90.41)
        if ((lat - 23.7100).abs() < 0.025 && (lng - 90.4100).abs() < 0.025) {
          return const LatLng(23.8765, 90.3204); // DIU Campus Ashulia
        }
        return LatLng(lat, lng);
      }
    }

    // 2. Direct exact or substring campus landmarks match (title takes highest precedence)
    if (cleanTitle.isNotEmpty) {
      for (final lm in campusLandmarks) {
        final lmT = lm.title.toLowerCase();
        if (lmT == cleanTitle || cleanTitle.contains(lmT) || lmT.contains(cleanTitle)) {
          return LatLng(lm.lat, lm.lng);
        }
      }
    }

    // 3. Specific commute corridors & destinations (Checked BEFORE broad campus/ashulia terms!)
    if (s.contains('birulia')) return const LatLng(23.8685, 90.3340);
    if (s.contains('mirpur 10')) return const LatLng(23.8069, 90.3687);
    if (s.contains('mirpur 11')) return const LatLng(23.8180, 90.3660);
    if (s.contains('mirpur 12') || s.contains('pallabi')) return const LatLng(23.8290, 90.3645);
    if (s.contains('mirpur 1') || s.contains('sony')) return const LatLng(23.8005, 90.3530);
    if (s.contains('mirpur 2') || s.contains('stadium')) return const LatLng(23.8075, 90.3615);
    if (s.contains('mirpur 14')) return const LatLng(23.7980, 90.3820);
    if (s.contains('mirpur 6') || s.contains('mirpur 7')) return const LatLng(23.8110, 90.3605);
    if (s.contains('mirpur') || s.contains('mir')) return const LatLng(23.8069, 90.3687);
    if (s.contains('ecb')) return const LatLng(23.8225, 90.3934);
    if (s.contains('uttara north')) return const LatLng(23.8710, 90.3800);
    if (s.contains('uttara center')) return const LatLng(23.8640, 90.3850);
    if (s.contains('uttara') || s.contains('diabari')) return const LatLng(23.8710, 90.3800);
    if (s.contains('dhanmondi') || s.contains('panthapath') || s.contains('kalabagan')) return const LatLng(23.7538, 90.3768);
    if (s.contains('moti') || s.contains('shapla') || s.contains('dilkusha')) return const LatLng(23.7330, 90.4172);
    if (s.contains('farmgate') || s.contains('khamarbari')) return const LatLng(23.7570, 90.3888);
    if (s.contains('savar') || s.contains('hemayetpur')) return const LatLng(23.8488, 90.2575);
    if (s.contains('dhaka university') || s.contains('du') || s.contains('tsc') || s.contains('curzon')) return const LatLng(23.7337, 90.3929);
    if (s.contains('gulshan')) return const LatLng(23.7940, 90.4140);
    if (s.contains('banani')) return const LatLng(23.7937, 90.4043);
    if (s.contains('mohakhali')) return const LatLng(23.7776, 90.4000);
    if (s.contains('airport') || s.contains('jasimuddin')) return const LatLng(23.8510, 90.4000);
    if (s.contains('gabtoli')) return const LatLng(23.7840, 90.3470);

    // 4. Broad Campus & Ashulia matching (Only if no specific corridor above matched!)
    if (s.contains('ashulia') || s.contains('daffodil') || s.contains('diu') || s.contains('smart city') || s.contains('campus')) {
      return const LatLng(23.8765, 90.3204);
    }

    return const LatLng(23.8685, 90.3340); // Default to nearby Birulia hub
  }

  /// Public lookup to resolve coordinates by name or address query
  static LatLng lookupCoordinates(String locationName) {
    return _approximateCoords(locationName, '');
  }

  static List<LocationSearchResult> _deduplicate(List<LocationSearchResult> items) {
    final seen = <String>{};
    final unique = <LocationSearchResult>[];
    for (final item in items) {
      final key = '${item.title.toLowerCase()}_${item.lat.toStringAsFixed(2)}_${item.lng.toStringAsFixed(2)}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(item);
      }
    }
    return unique;
  }
}
