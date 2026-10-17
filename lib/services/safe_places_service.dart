import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
class SafeSpot {
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double distanceInMeters;

  SafeSpot({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceInMeters,
  });
}

class SafePlacesService {
  static const String _userAgent =
      'Dhundo-LostAndFound-App/1.0.0 (contact: saumyasura@example.com)';

  static Future<List<SafeSpot>> getNearbySafeSpots(
    double lat,
    double lon,
  ) async {
    final List<SafeSpot> spots = [];

    try {
      final policeUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=police+station&format=json&lat=$lat&lon=$lon&limit=4&addressdetails=1',
      );
      final cafeUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=cafe&format=json&lat=$lat&lon=$lon&limit=4&addressdetails=1',
      );

      final responses = await Future.wait([
        http
            .get(policeUrl, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 3)),
        http
            .get(cafeUrl, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 3)),
      ]);

      for (var response in responses) {
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          for (var item in data) {
            final double itemLat = double.tryParse(item['lat'] ?? '') ?? 0.0;
            final double itemLon = double.tryParse(item['lon'] ?? '') ?? 0.0;
            if (itemLat == 0.0 || itemLon == 0.0) continue;

            final distance = Geolocator.distanceBetween(
              lat,
              lon,
              itemLat,
              itemLon,
            );
            final String displayName = item['display_name'] ?? 'Public Spot';
            final String name = displayName.split(',')[0].trim();
            final String type = item['type'] ?? 'public';
            final String category = type == 'police'
                ? 'Police Station'
                : 'Cafe/Public Space';

            spots.add(
              SafeSpot(
                name: name,
                category: category,
                latitude: itemLat,
                longitude: itemLon,
                distanceInMeters: distance,
              ),
            );
          }
        }
      }
    } catch (_) {
      // If HTTP fails or times out, we fall back to generic suggestions below
    }

    // Sort by distance
    spots.sort((a, b) => a.distanceInMeters.compareTo(b.distanceInMeters));

    // If we have few or no results, add generic recommendations as fallback
    if (spots.length < 3) {
      spots.addAll([
        SafeSpot(
          name: 'Local Police Station Lobby',
          category: 'Recommended Safety Zone',
          latitude: lat + 0.001,
          longitude: lon + 0.001,
          distanceInMeters: 150,
        ),
        SafeSpot(
          name: 'Nearest Bank Branch Lobby',
          category: 'Recommended Safety Zone',
          latitude: lat - 0.001,
          longitude: lon - 0.001,
          distanceInMeters: 180,
        ),
        SafeSpot(
          name: 'Busy Coffee Shop or Mall Lobby',
          category: 'Recommended Public Space',
          latitude: lat + 0.001,
          longitude: lon - 0.001,
          distanceInMeters: 220,
        ),
      ]);
    }

    // Remove duplicates by name
    final seen = <String>{};
    return spots.where((spot) => seen.add(spot.name)).toList();
  }
}
