import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class RouteStep {
  final String instruction;
  final String streetName;
  final double distanceInMeters;
  final String maneuverType;
  final String modifier;

  RouteStep({
    required this.instruction,
    required this.streetName,
    required this.distanceInMeters,
    required this.maneuverType,
    this.modifier = '',
  });
}

class RouteDetails {
  final List<LatLng> polylinePoints;
  final double distanceInMeters;
  final double durationInSeconds;
  final List<RouteStep> steps;

  RouteDetails({
    required this.polylinePoints,
    required this.distanceInMeters,
    required this.durationInSeconds,
    this.steps = const [],
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
        '?overview=full&geometries=geojson&steps=true'
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

          // Parse turn-by-turn steps
          final List<RouteStep> steps = [];
          if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
            final leg = route['legs'][0];
            if (leg['steps'] != null) {
              for (var s in leg['steps']) {
                final dist = (s['distance'] as num?)?.toDouble() ?? 0.0;
                final name = s['name'] as String? ?? '';
                final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
                final mType = maneuver['type'] as String? ?? 'straight';
                final mMod = maneuver['modifier'] as String? ?? '';

                String instruction = 'Continue straight';
                if (mType == 'depart') {
                  instruction = name.isNotEmpty ? 'Head on $name' : 'Head towards destination';
                } else if (mType == 'arrive') {
                  instruction = 'You have arrived at destination';
                } else if (mType == 'turn') {
                  instruction = mMod.isNotEmpty
                      ? 'Turn $mMod${name.isNotEmpty ? ' onto $name' : ''}'
                      : 'Turn${name.isNotEmpty ? ' onto $name' : ''}';
                } else if (mType == 'end of road') {
                  instruction = mMod.isNotEmpty
                      ? 'Turn $mMod at end of road${name.isNotEmpty ? ' onto $name' : ''}'
                      : 'Turn at end of road';
                } else if (mType == 'fork') {
                  instruction = 'Take $mMod fork${name.isNotEmpty ? ' onto $name' : ''}';
                } else if (name.isNotEmpty) {
                  instruction = 'Continue on $name';
                }

                steps.add(
                  RouteStep(
                    instruction: instruction,
                    streetName: name,
                    distanceInMeters: dist,
                    maneuverType: mType,
                    modifier: mMod,
                  ),
                );
              }
            }
          }

          return RouteDetails(
            polylinePoints: points,
            distanceInMeters: distance,
            durationInSeconds: duration,
            steps: steps,
          );
        }
      }
    } catch (_) {
      // Fallback below
    }

    // Default Fallback: Straight-line route
    final double distance = _calculateDistance(start, destination);
    final double duration = distance / 83.3 * 60;

    return RouteDetails(
      polylinePoints: [start, destination],
      distanceInMeters: distance,
      durationInSeconds: duration,
      steps: [
        RouteStep(
          instruction: 'Head straight towards destination',
          streetName: '',
          distanceInMeters: distance,
          maneuverType: 'straight',
        ),
      ],
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
