import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/cached_tile_provider.dart';
import '../services/routing_service.dart';

class LocationNavigationPage extends StatefulWidget {
  final LatLng destinationCoords;
  final String destinationName;

  const LocationNavigationPage({
    super.key,
    required this.destinationCoords,
    required this.destinationName,
  });

  @override
  State<LocationNavigationPage> createState() => _LocationNavigationPageState();
}

class _LocationNavigationPageState extends State<LocationNavigationPage> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  bool _loading = true;
  String _profile = 'foot'; // 'foot' or 'driving'
  List<LatLng> _routePoints = [];
  double _distanceRemaining = 0.0; // in meters
  double _durationRemaining = 0.0; // in seconds
  StreamSubscription<Position>? _positionStreamSubscription;

  // Simulation parameters
  bool _isSimulating = false;
  int _simulationIndex = 0;
  Timer? _simulationTimer;

  @override
  void initState() {
    super.initState();
    _initNavigation();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initNavigation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _useFallbackLocation();
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _useFallbackLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _useFallbackLocation();
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userCoords = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = userCoords;
      });

      await _fetchRoute();

      // Listen to real-time changes
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position pos) {
        if (!_isSimulating && mounted) {
          setState(() {
            _currentPosition = LatLng(pos.latitude, pos.longitude);
          });
          _fetchRoute();
        }
      });
    } catch (_) {
      _useFallbackLocation();
    }
  }

  void _useFallbackLocation() async {
    // If GPS fails, place user coordinates slightly off from destination to allow demo navigation
    final fallbackCoords = LatLng(
      widget.destinationCoords.latitude - 0.008,
      widget.destinationCoords.longitude - 0.008,
    );
    setState(() {
      _currentPosition = fallbackCoords;
    });
    await _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    if (_currentPosition == null) return;

    setState(() => _loading = true);
    final routeDetails = await RoutingService.getRoute(
      start: _currentPosition!,
      destination: widget.destinationCoords,
      profile: _profile,
    );

    if (mounted) {
      setState(() {
        _routePoints = routeDetails.polylinePoints;
        _distanceRemaining = routeDetails.distanceInMeters;
        _durationRemaining = routeDetails.durationInSeconds;
        _loading = false;
      });

      _fitRouteBounds();
    }
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_routePoints),
            padding: const EdgeInsets.symmetric(horizontal: 50.0, vertical: 80.0),
          ),
        );
      }
    });
  }

  void _changeProfile(String newProfile) {
    if (_profile == newProfile) return;
    setState(() {
      _profile = newProfile;
    });
    if (_isSimulating) {
      _stopSimulation();
    }
    _fetchRoute();
  }

  // Navigation simulation logic
  void _startSimulation() {
    if (_routePoints.isEmpty) return;
    _positionStreamSubscription?.pause();
    _simulationTimer?.cancel();
    
    setState(() {
      _isSimulating = true;
      _simulationIndex = 0;
      _currentPosition = _routePoints[0];
    });

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_simulationIndex < _routePoints.length - 1) {
        setState(() {
          _simulationIndex++;
          _currentPosition = _routePoints[_simulationIndex];
          
          // Calculate remaining route segment
          final remainingPoints = _routePoints.sublist(_simulationIndex);
          double remainingDist = 0.0;
          for (int i = 0; i < remainingPoints.length - 1; i++) {
            remainingDist += Geolocator.distanceBetween(
              remainingPoints[i].latitude,
              remainingPoints[i].longitude,
              remainingPoints[i + 1].latitude,
              remainingPoints[i + 1].longitude,
            );
          }
          _distanceRemaining = remainingDist;
          // Dynamically scale duration based on speed
          final speed = _profile == 'foot' ? 1.4 : 8.0; // speed in m/s
          _durationRemaining = remainingDist / speed;
        });
        
        _mapController.move(_currentPosition!, 17.0);
      } else {
        _stopSimulation();
        _showArrivalDialog();
      }
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulating = false;
    });
    _positionStreamSubscription?.resume();
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.border, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: AppTheme.foundColor),
            SizedBox(width: 8),
            Text('Arrived!'),
          ],
        ),
        content: Text('You have reached ${widget.destinationName} successfully.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return 'Less than 1 min';
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      return '$hours hr $remainingMins min';
    }
    return '$minutes mins';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final String modeLabel = _profile == 'foot' ? 'Walking' : 'Driving';
    
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text('Navigation to ${widget.destinationName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _fetchRoute,
            tooltip: 'Recalculate route',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.destinationCoords,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.dhundo',
                tileProvider: CachedTileProvider(),
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: AppTheme.primary,
                      strokeWidth: 4.5,
                      borderColor: AppTheme.primaryAccent.withOpacity(0.5),
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Destination marker
                  Marker(
                    point: widget.destinationCoords,
                    width: 50,
                    height: 50,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.lostColor,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [AppTheme.cardShadow],
                          ),
                          child: Text(
                            widget.destinationName,
                            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.lostColor,
                          size: 32,
                        ),
                      ],
                    ),
                  ),
                  // Current location marker
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.secondary.withOpacity(0.35),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.secondary,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Route profile switcher overlays
          Positioned(
            top: 12,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.cardBg.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileButton('foot', Icons.directions_walk_rounded),
                  const SizedBox(width: 4),
                  _buildProfileButton('driving', Icons.directions_car_rounded),
                ],
              ),
            ),
          ),

          // Simulated Navigation trigger
          Positioned(
            top: 12,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'simNavBtn',
              onPressed: _isSimulating ? _stopSimulation : _startSimulation,
              backgroundColor: _isSimulating ? AppTheme.lostColor : AppTheme.foundColor,
              label: Text(_isSimulating ? 'Stop Sim' : 'Simulate'),
              icon: Icon(_isSimulating ? Icons.stop_rounded : Icons.play_arrow_rounded),
            ),
          ),

          // Bottom card overlay containing route distance and time estimates
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.destinationName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            '$modeLabel Navigation Route',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      IconButton.filledTonal(
                        onPressed: () {
                          if (_currentPosition != null) {
                            _fitRouteBounds();
                          }
                        },
                        icon: const Icon(Icons.center_focus_strong, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.border,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppTheme.border, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildRouteMetric(
                        Icons.access_time_filled_rounded,
                        _formatDuration(_durationRemaining),
                        'Duration',
                      ),
                      Container(width: 1, height: 36, color: AppTheme.border),
                      _buildRouteMetric(
                        Icons.navigation_rounded,
                        _formatDistance(_distanceRemaining),
                        'Distance',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (_loading && _routePoints.isEmpty)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileButton(String profile, IconData icon) {
    final isSelected = _profile == profile;
    return GestureDetector(
      onTap: () => _changeProfile(profile),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildRouteMetric(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.secondary, size: 18),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}
