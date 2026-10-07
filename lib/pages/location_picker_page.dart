import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/cached_tile_provider.dart';

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();
  
  LatLng _selectedCoords = const LatLng(28.6139, 77.2090); // Default to New Delhi
  bool _loadingLocation = true;
  bool _reverseGeocoding = false;
  bool _searching = false;
  List<dynamic> _searchResults = [];
  Timer? _debounceTimer;

  static const String _userAgent = 'Dhundo-LostAndFound-App/1.0.0 (contact: saumyasura@example.com)';

  @override
  void initState() {
    super.initState();
    _determinePosition();
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
      _mapController.move(userCoords, 15.0);
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
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords.latitude}&lon=${coords.longitude}&zoom=18&addressdetails=1'
      );
      final response = await http.get(url, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String name = '';
        if (data['address'] != null) {
          final addr = data['address'] as Map;
          name = addr['amenity'] ?? 
                 addr['cafe'] ?? 
                 addr['shop'] ?? 
                 addr['tourism'] ?? 
                 addr['building'] ?? 
                 addr['road'] ?? 
                 addr['suburb'] ?? 
                 '';
        }
        if (name.isEmpty && data['display_name'] != null) {
          name = data['display_name'].toString().split(',')[0];
        }
        if (name.isEmpty) {
          name = 'Shared Spot';
        }
        setState(() {
          _labelController.text = name;
        });
      }
    } catch (_) {
      // Ignore geocoding failure, user can manually name it
    } finally {
      setState(() {
        _reverseGeocoding = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
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
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1'
      );
      final response = await http.get(url, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 4));
      
      if (response.statusCode == 200) {
        setState(() {
          _searchResults = json.decode(response.body);
        });
      }
    } catch (_) {
      // Silence network errors
    } finally {
      setState(() {
        _searching = false;
      });
    }
  }

  void _selectSearchResult(dynamic result) {
    final lat = double.tryParse(result['lat'] ?? '') ?? 0.0;
    final lon = double.tryParse(result['lon'] ?? '') ?? 0.0;
    if (lat == 0.0 || lon == 0.0) return;

    final targetCoords = LatLng(lat, lon);
    
    // Extract short name
    String name = '';
    if (result['address'] != null) {
      final addr = result['address'] as Map;
      name = addr['amenity'] ?? 
             addr['cafe'] ?? 
             addr['shop'] ?? 
             addr['tourism'] ?? 
             addr['building'] ?? 
             addr['road'] ?? 
             addr['suburb'] ?? 
             '';
    }
    if (name.isEmpty && result['display_name'] != null) {
      name = result['display_name'].toString().split(',')[0];
    }
    
    setState(() {
      _selectedCoords = targetCoords;
      _searchResults = [];
      _searchController.clear();
      _labelController.text = name.isNotEmpty ? name : 'Shared Spot';
    });

    FocusScope.of(context).unfocus();
    _mapController.move(targetCoords, 16.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Share a Location'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedCoords,
              initialZoom: 15.0,
              onTap: (_, point) {
                setState(() {
                  _selectedCoords = point;
                });
                _reverseGeocode(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.dhundo',
                tileProvider: CachedTileProvider(),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedCoords,
                    width: 50,
                    height: 50,
                    child: const Icon(
                      Icons.location_pin,
                      color: AppTheme.lostColor,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
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
                    color: AppTheme.cardBg.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border, width: 1.2),
                    boxShadow: [AppTheme.cardShadow],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search places, cafes, landmarks...',
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
                      color: AppTheme.cardBg.withOpacity(0.95),
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
                            res['display_name'] ?? 'Place',
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
                  const Text(
                    'Selected Location Details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondary,
                    ),
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
                            fontSize: 15,
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
                          label: const Text('Confirm Share', style: TextStyle(fontSize: 13)),
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
          
          if (_loadingLocation)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}
