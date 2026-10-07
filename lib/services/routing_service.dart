import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class RouteDetails {
  final List<LatLng> polylinePoints;
  final double distanceInMeters;
  final double durationInSeconds;

  RouteDetails({
    required this.polylinePoints,
    required this.distanceInMeters,
    required this.durationInSeconds,
  });
}

class RoutingService {
  static const String _userAgent = 'Dhundo-LostAndFound-App/1.0.0 (contact: saumyasura@example.com)';

  static Future<RouteDetails> getRoute({
    required LatLng start,
    required LatLng destination,
    String profile = 'foot', // 'foot' or 'driving'
  }) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/$profile/'
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson'
      );

      final response = await http.get(url, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          final List<LatLng> points = coordinates.map((coord) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();

          return RouteDetails(
            polylinePoints: points,
            distanceInMeters: distance,
            durationInSeconds: duration,
          );
        }
      }
    } catch (_) {
      // Fallback below
    }

    // Default Fallback: Straight-line route
    final double distance = _calculateDistance(start, destination);
    // Rough walking estimate: 5 km/h -> 83 meters/minute
    final double duration = distance / 83.3 * 60; 

    return RouteDetails(
      polylinePoints: [start, destination],
      distanceInMeters: distance,
      durationInSeconds: duration,
    );
  }

  // Haversine distance calculator in meters
  static double _calculateDistance(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(
      p1.latitude,
      p1.longitude,
      p2.latitude,
      p2.longitude,
    );
  }
}
