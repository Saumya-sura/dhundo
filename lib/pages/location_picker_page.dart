import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/google_maps_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/street_view_dialog.dart';

class LocationPickerPage extends StatefulWidget {
  final LatLng? initialCoords;
  final String? initialAddress;
  final String title;
  final String confirmButtonText;
  final bool isLost;

  const LocationPickerPage({
    super.key,
    this.initialCoords,
    this.initialAddress,
    this.title = 'Share a Location',
    this.confirmButtonText = 'Confirm Share',
    this.isLost = true,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();

  LatLng _selectedCoords = const LatLng(28.6139, 77.2090); // Default to New Delhi
  bool _loadingLocation = true;
  bool _reverseGeocoding = false;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialCoords != null) {
      _selectedCoords = widget.initialCoords!;
      _loadingLocation = false;
      if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
        _labelController.text = widget.initialAddress!;
      } else {
        _reverseGeocode(widget.initialCoords!);
      }
    } else {
      _determinePosition();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _labelController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _loadingLocation = false);
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _loadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _loadingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userCoords = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedCoords = userCoords;
        _loadingLocation = false;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(userCoords, 16.0));
      _reverseGeocode(userCoords);
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  Future<void> _reverseGeocode(LatLng coords) async {
    setState(() {
      _reverseGeocoding = true;
    });

    try {
      final address = await GoogleMapsService.reverseGeocode(
        coords.latitude,
        coords.longitude,
      );
      if (mounted) {
        setState(() {
          _labelController.text = address;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _reverseGeocoding = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().length > 2) {
        _performSearch(query.trim());
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _searching = true;
    });

    try {
      final results = await GoogleMapsService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = result['lat'] as double;
    final lng = result['lng'] as double;
    final targetCoords = LatLng(lat, lng);
    final address = result['address'] as String? ?? 'Shared Spot';

    setState(() {
      _selectedCoords = targetCoords;
      _searchResults = [];
      _searchController.clear();
      _labelController.text = address;
    });

    FocusScope.of(context).unfocus();
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(targetCoords, 16.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            style: GoogleMapsService.darkMapStyle,
            initialCameraPosition: CameraPosition(
              target: widget.initialCoords ?? _selectedCoords,
              zoom: 15.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            markers: {
              Marker(
                markerId: const MarkerId('picked_location'),
                position: _selectedCoords,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  widget.isLost ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
                ),
                draggable: true,
                onDragEnd: (newCoords) {
                  setState(() {
                    _selectedCoords = newCoords;
                  });
                  _reverseGeocode(newCoords);
                },
              ),
            },
            onTap: (coords) {
              setState(() {
                _selectedCoords = coords;
              });
              _reverseGeocode(coords);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),

          // Search Bar Overlay
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border, width: 1.2),
                    boxShadow: [AppTheme.cardShadow],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search places with Google Maps...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.secondary),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                    });
                                  },
                                )
                              : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border, width: 1),
                      boxShadow: [AppTheme.cardShadow],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
                      itemBuilder: (context, index) {
                        final res = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, color: AppTheme.secondary, size: 20),
                          title: Text(
                            res['address'] ?? 'Place',
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(res),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Bottom card overlay containing Selected Place details
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
                      const Text(
                        'Selected Location Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondary,
                        ),
                      ),
                      // Street View inspection button
                      InkWell(
                        onTap: () {
                          StreetViewDialog.show(
                            context,
                            latitude: _selectedCoords.latitude,
                            longitude: _selectedCoords.longitude,
                            locationTitle: _labelController.text.isNotEmpty
                                ? _labelController.text
                                : 'Selected Location',
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.streetview_rounded, size: 14, color: AppTheme.secondary),
                            SizedBox(width: 4),
                            Text(
                              'Street View',
                              style: TextStyle(fontSize: 12, color: AppTheme.secondary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.edit_location_alt_rounded, color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _labelController,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Name this location...',
                            hintStyle: const TextStyle(color: AppTheme.textMuted),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            fillColor: Colors.transparent,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppTheme.secondary),
                            ),
                          ),
                        ),
                      ),
                      if (_reverseGeocoding)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lat: ${_selectedCoords.latitude.toStringAsFixed(6)}, Lng: ${_selectedCoords.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const Divider(color: AppTheme.border, height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _determinePosition,
                          icon: const Icon(Icons.my_location, size: 16),
                          label: const Text('My Location', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: const BorderSide(color: AppTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final label = _labelController.text.trim();
                            Navigator.pop(context, {
                              'latitude': _selectedCoords.latitude,
                              'longitude': _selectedCoords.longitude,
                              'name': label.isNotEmpty ? label : 'Shared Spot',
                            });
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(widget.confirmButtonText, style: const TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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

          // Floating Zoom & Recenter Controls
          Positioned(
            right: 16,
            bottom: 235,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardBg.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(Icons.add_rounded, size: 20, color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                  Container(width: 28, height: 1, color: AppTheme.border),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.zero,
                      onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(Icons.remove_rounded, size: 20, color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                  Container(width: 28, height: 1, color: AppTheme.border),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      onTap: () => _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_selectedCoords, 16.0),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(Icons.filter_center_focus_rounded, size: 20, color: AppTheme.secondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_loadingLocation)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}
