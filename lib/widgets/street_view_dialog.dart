import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/google_maps_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

class StreetViewDialog extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String locationTitle;

  const StreetViewDialog({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.locationTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
    required String locationTitle,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StreetViewDialog(
        latitude: latitude,
        longitude: longitude,
        locationTitle: locationTitle,
      ),
    );
  }

  @override
  State<StreetViewDialog> createState() => _StreetViewDialogState();
}

class _StreetViewDialogState extends State<StreetViewDialog> {
  int _heading = 0; // 0 to 360 real-time
  int _fov = 90; // 30 to 120 real-time
  int _pitch = 0; // -80 to 80 real-time

  int _activeHeading = 0;
  int _activeFov = 90;
  int _activePitch = 0;

  Timer? _dragDebounceTimer;
  bool _isDragging = false;
  bool _showGestureHint = true;

  bool _loading = true;
  bool _hasStreetView = true;
  StreetViewMetadata? _metadata;
  int _searchRadius = 1000;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _dragDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAvailability({int radius = 1000}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _searchRadius = radius;
    });

    final metadata = await GoogleMapsService.getStreetViewMetadata(
      widget.latitude,
      widget.longitude,
      radius: radius,
    );

    if (mounted) {
      setState(() {
        _metadata = metadata;
        _hasStreetView = metadata.isAvailable;
        _loading = false;
      });
    }
  }

  String get _currentStreetViewUrl {
    return GoogleMapsService.getStreetViewUrl(
      lat: widget.latitude,
      lng: widget.longitude,
      panoId: _metadata?.panoId,
      radius: _searchRadius,
      fov: _activeFov,
      heading: _activeHeading,
      pitch: _activePitch,
    );
  }

  Future<void> _openInGoogleMaps() async {
    Uri url;
    if (_metadata?.panoId != null && _metadata!.panoId!.isNotEmpty) {
      url = Uri.parse(
        'https://www.google.com/maps/@?api=1&map_action=pano&pano=${_metadata!.panoId}',
      );
    } else {
      url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}',
      );
    }
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.streetview_rounded, color: AppTheme.secondary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google Street View',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        widget.locationTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Street View viewport container with Touch Pan/Drag Gestures
            Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isDragging ? AppTheme.secondary : AppTheme.border,
                  width: _isDragging ? 1.8 : 1.5,
                ),
                color: AppTheme.darkBg,
              ),
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(color: AppTheme.secondary),
                          SizedBox(height: 12),
                          Text(
                            'Searching Street View nearby...',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : !_hasStreetView
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBg,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: const Icon(
                                    Icons.explore_off_rounded,
                                    color: AppTheme.secondary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Street View Not Mapped Here',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'No 360° capture within ${_searchRadius >= 1000 ? '${(_searchRadius / 1000).toStringAsFixed(0)} km' : '$_searchRadius m'}. Showing satellite view:',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Fallback satellite image preview
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl:
                                        'https://maps.googleapis.com/maps/api/staticmap?center=${widget.latitude},${widget.longitude}&zoom=17&size=600x240&scale=2&maptype=hybrid&markers=color:0x818cf8%7C${widget.latitude},${widget.longitude}&key=${GoogleMapsService.apiKey}',
                                    height: 105,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      height: 105,
                                      color: AppTheme.darkBg,
                                      child: const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      height: 105,
                                      color: AppTheme.darkBg,
                                      child: const Center(
                                        child: Text(
                                          'Satellite preview unavailable',
                                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : GestureDetector(
                          onScaleStart: (details) {
                            setState(() {
                              _isDragging = true;
                              _showGestureHint = false;
                            });
                          },
                          onScaleUpdate: (details) {
                            if (details.pointerCount == 1) {
                              final dx = details.focalPointDelta.dx;
                              final dy = details.focalPointDelta.dy;

                              int newHeading = (_heading - (dx * 0.45)).round() % 360;
                              if (newHeading < 0) newHeading += 360;

                              int newPitch = (_pitch + (dy * 0.35)).round().clamp(-80, 80);

                              setState(() {
                                _heading = newHeading;
                                _pitch = newPitch;
                              });

                              _dragDebounceTimer?.cancel();
                              _dragDebounceTimer = Timer(const Duration(milliseconds: 140), () {
                                if (mounted) {
                                  setState(() {
                                    _activeHeading = _heading;
                                    _activePitch = _pitch;
                                  });
                                }
                              });
                            } else if (details.pointerCount > 1 && details.scale != 1.0) {
                              final delta = (1.0 - details.scale) * 12;
                              final newFov = (_fov + delta).round().clamp(30, 120);
                              if (newFov != _fov) {
                                setState(() {
                                  _fov = newFov;
                                });
                                _dragDebounceTimer?.cancel();
                                _dragDebounceTimer = Timer(const Duration(milliseconds: 140), () {
                                  if (mounted) {
                                    setState(() {
                                      _activeFov = _fov;
                                    });
                                  }
                                });
                              }
                            }
                          },
                          onScaleEnd: (details) {
                            _dragDebounceTimer?.cancel();
                            setState(() {
                              _isDragging = false;
                              _activeHeading = _heading;
                              _activePitch = _pitch;
                              _activeFov = _fov;
                            });
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                key: ValueKey('${_metadata?.panoId}-$_activeHeading-$_activeFov-$_activePitch'),
                                imageUrl: _currentStreetViewUrl,
                                fit: BoxFit.cover,
                                fadeInDuration: const Duration(milliseconds: 150),
                                placeholder: (context, url) => Container(
                                  color: AppTheme.darkBg,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.secondary,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Center(
                                  child: Text('Failed to load Street View imagery'),
                                ),
                              ),

                              // Interactive Crosshair Indicator while panning
                              if (_isDragging)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.6), width: 1),
                                    ),
                                    child: const Icon(
                                      Icons.all_out_rounded,
                                      size: 18,
                                      color: AppTheme.secondary,
                                    ),
                                  ),
                                ),

                              // Compass badge overlay (real-time 60fps rotation)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isDragging ? AppTheme.secondary : Colors.white24,
                                      width: _isDragging ? 1 : 0.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Transform.rotate(
                                        angle: (_heading * 3.14159) / 180,
                                        child: const Icon(
                                          Icons.navigation_rounded,
                                          color: AppTheme.foundColor,
                                          size: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_heading°',
                                        style: TextStyle(
                                          color: _isDragging ? AppTheme.secondary : Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Distance badge overlay
                              if (_metadata?.distanceMeters != null)
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _metadata!.distanceMeters! < 30
                                            ? AppTheme.foundColor.withValues(alpha: 0.6)
                                            : AppTheme.secondary.withValues(alpha: 0.6),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.near_me_rounded,
                                          size: 11,
                                          color: _metadata!.distanceMeters! < 30
                                              ? AppTheme.foundColor
                                              : AppTheme.secondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _metadata!.distanceMeters! < 30
                                              ? 'Exact Spot (360°)'
                                              : 'Nearest street (~${_metadata!.distanceMeters!.round()}m)',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Floating Gesture Tutorial / Hint pill
                              if (_showGestureHint)
                                Positioned(
                                  bottom: 10,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppTheme.secondary.withValues(alpha: 0.4),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.touch_app_rounded, color: AppTheme.secondary, size: 14),
                                          SizedBox(width: 5),
                                          Text(
                                            'Drag to look 360° • Pinch to zoom',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                              // Date & copyright badge overlay
                              if (_metadata?.date != null || _metadata?.copyright != null)
                                Positioned(
                                  bottom: 8,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      [
                                        if (_metadata?.date != null) _metadata!.date!,
                                        if (_metadata?.copyright != null) _metadata!.copyright!,
                                      ].join(' • '),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),

            if (_hasStreetView && !_loading) ...[
              const SizedBox(height: 12),
              // Panoramic 360 Look controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlBtn(
                    icon: Icons.rotate_left_rounded,
                    label: 'Turn Left',
                    onTap: () {
                      setState(() {
                        _heading = (_heading - 45 + 360) % 360;
                        _activeHeading = _heading;
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    label: 'Look Up',
                    onTap: () {
                      setState(() {
                        _pitch = (_pitch + 15).clamp(-80, 80);
                        _activePitch = _pitch;
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reset',
                    onTap: () {
                      setState(() {
                        _heading = 0;
                        _pitch = 0;
                        _fov = 90;
                        _activeHeading = 0;
                        _activePitch = 0;
                        _activeFov = 90;
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    label: 'Look Down',
                    onTap: () {
                      setState(() {
                        _pitch = (_pitch - 15).clamp(-80, 80);
                        _activePitch = _pitch;
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.rotate_right_rounded,
                    label: 'Turn Right',
                    onTap: () {
                      setState(() {
                        _heading = (_heading + 45) % 360;
                        _activeHeading = _heading;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Zoom FOV slider
              Row(
                children: [
                  const Icon(Icons.zoom_out_rounded, size: 16, color: AppTheme.textMuted),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: AppTheme.secondary,
                        inactiveTrackColor: AppTheme.border,
                        thumbColor: AppTheme.secondary,
                      ),
                      child: Slider(
                        value: _fov.toDouble(),
                        min: 30,
                        max: 120,
                        onChanged: (val) {
                          setState(() {
                            _fov = val.round();
                            _activeFov = _fov;
                          });
                        },
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in_rounded, size: 16, color: AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: 6),
              // Open in Google Maps button
              OutlinedButton.icon(
                onPressed: _openInGoogleMaps,
                icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppTheme.secondary),
                label: const Text(
                  'Open Interactive 360° in Google Maps',
                  style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ] else if (!_hasStreetView && !_loading) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_searchRadius < 3000)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _checkAvailability(radius: 3000),
                        icon: const Icon(Icons.travel_explore_rounded, size: 14, color: AppTheme.secondary),
                        label: const Text(
                          'Search 3 km Radius',
                          style: TextStyle(fontSize: 11, color: AppTheme.secondary),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  if (_searchRadius < 3000) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openInGoogleMaps,
                      icon: const Icon(Icons.map_rounded, size: 14),
                      label: const Text(
                        'Open in Maps',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.secondary.withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.secondary, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
