import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/street_view_dialog.dart';
import '../services/google_maps_service.dart';
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
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  bool _loading = true;
  String _profile = 'foot'; // 'foot' or 'driving'
  List<LatLng> _routePoints = [];
  List<RouteStep> _routeSteps = [];
  double _distanceRemaining = 0.0; // in meters
  double _durationRemaining = 0.0; // in seconds
  StreamSubscription<Position>? _positionStreamSubscription;

  // Active Navigation Mode (Google Maps style)
  bool _isNavigating = false;
  double _currentBearing = 0.0;
  double _currentSpeed = 0.0;

  // Optional simulation for desktop demo testing
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
        _currentBearing = position.heading;
        _currentSpeed = position.speed;
      });

      await _fetchRoute();

      // Listen to real-time changes
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
        ),
      ).listen((Position pos) {
        if (!_isSimulating && mounted) {
          final newPos = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _currentPosition = newPos;
            if (pos.heading > 0) {
              _currentBearing = pos.heading;
            }
            _currentSpeed = pos.speed;
          });

          if (_isNavigating && _mapController != null) {
            _followUserInNavigation(newPos, _currentBearing);
          }
        }
      });
    } catch (_) {
      _useFallbackLocation();
    }
  }

  void _useFallbackLocation() async {
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
        _routeSteps = routeDetails.steps;
        _distanceRemaining = routeDetails.distanceInMeters;
        _durationRemaining = routeDetails.durationInSeconds;
        _loading = false;
      });

      if (!_isNavigating) {
        _fitRouteBounds();
      }
    }
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty || _mapController == null) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (final p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    if (_currentPosition != null) {
      if (_currentPosition!.latitude < minLat) minLat = _currentPosition!.latitude;
      if (_currentPosition!.latitude > maxLat) maxLat = _currentPosition!.latitude;
      if (_currentPosition!.longitude < minLng) minLng = _currentPosition!.longitude;
      if (_currentPosition!.longitude > maxLng) maxLng = _currentPosition!.longitude;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80.0,
      ),
    );
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180);
    final lon1 = from.longitude * (math.pi / 180);
    final lat2 = to.latitude * (math.pi / 180);
    final lon2 = to.longitude * (math.pi / 180);
    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x) * (180 / math.pi);
    return (brng + 360) % 360;
  }

  void _followUserInNavigation(LatLng pos, double bearing) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          zoom: 18.0,
          tilt: 50.0,
          bearing: bearing,
        ),
      ),
    );
  }

  void _startNavigation() {
    if (_currentPosition == null) return;

    double bearing = _currentBearing;
    if (_routePoints.length > 1) {
      bearing = _calculateBearing(_routePoints[0], _routePoints[1]);
    }

    setState(() {
      _isNavigating = true;
      _currentBearing = bearing;
    });

    _followUserInNavigation(_currentPosition!, bearing);
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      if (_isSimulating) {
        _stopSimulation();
      }
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition ?? widget.destinationCoords,
          zoom: 15.0,
          tilt: 0.0,
          bearing: 0.0,
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      _fitRouteBounds();
    });
  }

  void _recenterNavigation() {
    if (_currentPosition != null) {
      _followUserInNavigation(_currentPosition!, _currentBearing);
    }
  }

  Future<void> _openGoogleMapsExternal() async {
    final mode = _profile == 'foot' ? 'walking' : 'driving';
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${widget.destinationCoords.latitude},${widget.destinationCoords.longitude}&travelmode=$mode',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
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

  // Simulation mode (kept in overflow menu for desktop PC demonstration)
  void _startSimulation() {
    if (_routePoints.isEmpty) return;
    _positionStreamSubscription?.pause();
    _simulationTimer?.cancel();

    setState(() {
      _isSimulating = true;
      _isNavigating = true;
      _simulationIndex = 0;
      _currentPosition = _routePoints[0];
    });

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_simulationIndex < _routePoints.length - 1) {
        final p1 = _routePoints[_simulationIndex];
        final p2 = _routePoints[_simulationIndex + 1];
        final bearing = _calculateBearing(p1, p2);

        setState(() {
          _simulationIndex++;
          _currentPosition = p2;
          _currentBearing = bearing;
          _currentSpeed = _profile == 'foot' ? 1.4 : 9.5;

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
          _durationRemaining = remainingDist / _currentSpeed;
        });

        _followUserInNavigation(_currentPosition!, bearing);
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
            onPressed: () {
              Navigator.pop(dialogContext);
              _stopNavigation();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showStepsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Turn-by-Turn Directions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppTheme.border),
              Expanded(
                child: _routeSteps.isEmpty
                    ? const Center(
                        child: Text(
                          'Follow the highlighted blue route on the map.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _routeSteps.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: AppTheme.border, height: 1),
                        itemBuilder: (context, index) {
                          final step = _routeSteps[index];
                          IconData stepIcon = Icons.navigation_rounded;
                          if (step.modifier.contains('left')) {
                            stepIcon = Icons.turn_left_rounded;
                          } else if (step.modifier.contains('right')) {
                            stepIcon = Icons.turn_right_rounded;
                          } else if (step.maneuverType == 'arrive') {
                            stepIcon = Icons.place_rounded;
                          }

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.foundColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(stepIcon, color: AppTheme.foundColor, size: 20),
                            ),
                            title: Text(
                              step.instruction,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            subtitle: step.distanceInMeters > 0
                                ? Text(
                                    _formatDistance(step.distanceInMeters),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '1 min';
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

  String _getArrivalTime() {
    final arrival = DateTime.now().add(Duration(seconds: _durationRemaining.round()));
    return DateFormat('h:mm a').format(arrival);
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{
      // Destination marker
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationCoords,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.destinationName),
      ),
    };

    // Current position marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You are here'),
          flat: true,
          rotation: _currentBearing,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('navigation_route'),
        points: _routePoints,
        color: const Color(0xFF4285F4), // Google Maps Navigation Blue
        width: 6,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final String modeLabel = _profile == 'foot' ? 'Walking' : 'Driving';
    final RouteStep? currentStep = _routeSteps.isNotEmpty ? _routeSteps[0] : null;

    IconData maneuverIcon = Icons.navigation_rounded;
    if (currentStep != null) {
      if (currentStep.modifier.contains('left')) {
        maneuverIcon = Icons.turn_left_rounded;
      } else if (currentStep.modifier.contains('right')) {
        maneuverIcon = Icons.turn_right_rounded;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            style: GoogleMapsService.darkMapStyle,
            initialCameraPosition: CameraPosition(
              target: widget.destinationCoords,
              zoom: 15.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitRouteBounds();
            },
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            trafficEnabled: _profile == 'driving',
          ),

          // -------------------------------------------------------------
          // TOP NAVIGATION HEADER (GOOGLE MAPS STYLE)
          // -------------------------------------------------------------
          if (_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F392B), // Solid Google Maps Navigation Green
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.foundColor, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.foundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        maneuverIcon,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentStep != null
                                ? currentStep.instruction
                                : 'Head towards ${widget.destinationName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _routeSteps.length > 1
                                ? 'Then: ${_routeSteps[1].instruction}'
                                : 'Distance: ${_formatDistance(_distanceRemaining)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Quick exit button in the header
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                      tooltip: 'Exit Navigation',
                      onPressed: _stopNavigation,
                    ),
                  ],
                ),
              ),
            )
          else
            // Standard Route Preview Top Bar
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  // Back button
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A2B),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 1),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Mode switcher (Walking vs Driving)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A2B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border, width: 1),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
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
                  const Spacer(),
                  // Street View 360° Inspector
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A2B),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 1),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.streetview_rounded, color: AppTheme.secondary),
                      tooltip: 'Street View 360°',
                      onPressed: () {
                        StreetViewDialog.show(
                          context,
                          latitude: widget.destinationCoords.latitude,
                          longitude: widget.destinationCoords.longitude,
                          locationTitle: widget.destinationName,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Overflow menu
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A2B),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 1),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
                      color: const Color(0xFF161A2B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onSelected: (val) {
                        if (val == 'sim') {
                          _startSimulation();
                        } else if (val == 'refresh') {
                          _fetchRoute();
                        } else if (val == 'steps') {
                          _showStepsBottomSheet();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'steps',
                          child: Row(
                            children: [
                              Icon(Icons.list_alt_rounded, size: 18, color: AppTheme.secondary),
                              SizedBox(width: 10),
                              Text('View Turn Directions'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 18, color: AppTheme.textSecondary),
                              SizedBox(width: 10),
                              Text('Recalculate Route'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'sim',
                          child: Row(
                            children: [
                              Icon(Icons.play_circle_outline, size: 18, color: AppTheme.textMuted),
                              SizedBox(width: 10),
                              Text('Simulate Walk (Demo)'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // -------------------------------------------------------------
          // RECENTER & SPEED BUTTONS IN ACTIVE NAVIGATION
          // -------------------------------------------------------------
          if (_isNavigating)
            Positioned(
              right: 16,
              bottom: 140,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'recenterNavBtn',
                    mini: true,
                    backgroundColor: const Color(0xFF161A2B),
                    foregroundColor: AppTheme.secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    onPressed: _recenterNavigation,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A2B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      '${(_currentSpeed * 3.6).toStringAsFixed(0)} km/h',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // -------------------------------------------------------------
          // BOTTOM NAVIGATION CONTROLS (SOLID OPAQUE GOOGLE MAPS DOCK)
          // -------------------------------------------------------------
          Positioned(
            bottom: 16,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161A2B), // Completely opaque solid card
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: _isNavigating
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ETA, Distance, Arrival
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _formatDuration(_durationRemaining),
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.foundColor,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '(${_formatDistance(_distanceRemaining)})',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Arrival: ${_getArrivalTime()} • $modeLabel',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // View Steps button
                            IconButton.filledTonal(
                              onPressed: _showStepsBottomSheet,
                              icon: const Icon(Icons.list_alt_rounded, size: 20, color: AppTheme.secondary),
                              tooltip: 'Turn Directions',
                              style: IconButton.styleFrom(backgroundColor: AppTheme.border),
                            ),
                            const SizedBox(width: 8),
                            // Exit button
                            ElevatedButton.icon(
                              onPressed: _stopNavigation,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Exit'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.lostColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Direct Open in Google Maps button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openGoogleMapsExternal,
                            icon: const Icon(Icons.navigation_rounded, size: 16, color: AppTheme.secondary),
                            label: const Text(
                              'Open in Google Maps (Turn-by-Turn Voice)',
                              style: TextStyle(fontSize: 13, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.secondary),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.destinationName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Arrival: ${_getArrivalTime()} • ${_formatDistance(_distanceRemaining)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () {
                                if (_currentPosition != null) {
                                  _fitRouteBounds();
                                }
                              },
                              icon: const Icon(Icons.center_focus_strong, size: 20),
                              tooltip: 'Fit Route',
                              style: IconButton.styleFrom(backgroundColor: AppTheme.border),
                            ),
                          ],
                        ),
                        const Divider(color: AppTheme.border, height: 20),
                        // Route details bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildRouteMetric(
                              Icons.access_time_filled_rounded,
                              _formatDuration(_durationRemaining),
                              'Travel Time',
                            ),
                            Container(width: 1, height: 32, color: AppTheme.border),
                            _buildRouteMetric(
                              Icons.navigation_rounded,
                              _formatDistance(_distanceRemaining),
                              'Distance',
                            ),
                            Container(width: 1, height: 32, color: AppTheme.border),
                            _buildRouteMetric(
                              Icons.schedule_rounded,
                              _getArrivalTime(),
                              'Arrival',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Action buttons: "Start Navigation" and "Open in Google Maps"
                        Row(
                          children: [
                            // Big Google Maps "Start" Button
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: _startNavigation,
                                icon: const Icon(Icons.navigation_rounded, size: 20),
                                label: const Text(
                                  'Start',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.foundColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Direct Google Maps app button
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                onPressed: _openGoogleMapsExternal,
                                icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.secondary),
                                label: const Text(
                                  'Google Maps',
                                  style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.secondary),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),

          if (_loading && _routePoints.isEmpty)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.foundColor),
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
          borderRadius: BorderRadius.circular(10),
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
            Icon(icon, color: AppTheme.secondary, size: 16),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
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
