import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleMapsService {
  static const String apiKey = 'AIzaSyAUjRVcmsVbmK6y5MO3COPCrvuZwi6ziIg';

  /// Obsidian dark theme JSON styling for Google Maps
  static const String darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#0b0d17"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#8e95a5"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#0b0d17"}]
    },
    {
      "featureType": "administrative.locality",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#c4cbd8"}]
    },
    {
      "featureType": "poi",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#818cf8"}]
    },
    {
      "featureType": "poi.park",
      "elementType": "geometry",
      "stylers": [{"color": "#111827"}]
    },
    {
      "featureType": "poi.park",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#34d399"}]
    },
    {
      "featureType": "road",
      "elementType": "geometry",
      "stylers": [{"color": "#181d2f"}]
    },
    {
      "featureType": "road",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#111625"}]
    },
    {
      "featureType": "road",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#9ca3af"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry",
      "stylers": [{"color": "#232b45"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "geometry.stroke",
      "stylers": [{"color": "#181e31"}]
    },
    {
      "featureType": "road.highway",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#cbd5e1"}]
    },
    {
      "featureType": "transit",
      "elementType": "geometry",
      "stylers": [{"color": "#141928"}]
    },
    {
      "featureType": "transit.station",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#818cf8"}]
    },
    {
      "featureType": "water",
      "elementType": "geometry",
      "stylers": [{"color": "#070a14"}]
    },
    {
      "featureType": "water",
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#3b82f6"}]
    },
    {
      "featureType": "water",
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#070a14"}]
    }
  ]
  ''';

  /// Reverse geocode coordinates to a human-readable address
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
          final results = data['results'] as List;
          // Prefer a shorter address or first formatted address
          final first = results[0];
          return first['formatted_address'] ?? 'Selected Location';
        }
      }
    } catch (_) {}
    return 'Selected Location';
  }

  /// Search places by text query using Google Geocoding API
  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          return results.map((item) {
            final loc = item['geometry']['location'];
            return {
              'address': item['formatted_address'] as String? ?? query,
              'lat': (loc['lat'] as num).toDouble(),
              'lng': (loc['lng'] as num).toDouble(),
            };
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Generate a high-resolution dark-themed static map snapshot
  static String getStaticMapUrl({
    required double lat,
    required double lng,
    int zoom = 15,
    int width = 600,
    int height = 300,
    bool isLost = true,
  }) {
    final markerColor = isLost ? '0xEF4444' : '0x10B981';
    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$lat,$lng'
        '&zoom=$zoom'
        '&size=${width}x$height'
        '&scale=2'
        '&markers=color:$markerColor%7C$lat,$lng'
        '&style=element:geometry%7Ccolor:0x0b0d17'
        '&style=element:labels.text.fill%7Ccolor:0x8e95a5'
        '&style=element:labels.text.stroke%7Ccolor:0x0b0d17'
        '&style=feature:road%7Celement:geometry%7Ccolor:0x1b2135'
        '&style=feature:water%7Celement:geometry%7Ccolor:0x070c18'
        '&key=$apiKey';
  }

  /// Generate Google Street View static image URL
  static String getStreetViewUrl({
    required double lat,
    required double lng,
    int width = 600,
    int height = 400,
    int fov = 90,
  }) {
    return 'https://maps.googleapis.com/maps/api/streetview'
        '?size=${width}x$height'
        '&location=$lat,$lng'
        '&fov=$fov'
        '&key=$apiKey';
  }

  /// Check if Google Street View imagery exists for given coordinates
  static Future<bool> hasStreetView(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/streetview/metadata?location=$lat,$lng&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'OK';
      }
    } catch (_) {}
    return false;
  }
}
