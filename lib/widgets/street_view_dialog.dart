import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  int _heading = 0; // 0 to 360
  int _fov = 90; // 10 to 120
  int _pitch = 0; // -90 to 90
  bool _loading = true;
  bool _hasStreetView = true;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final available = await GoogleMapsService.hasStreetView(
      widget.latitude,
      widget.longitude,
    );
    if (mounted) {
      setState(() {
        _hasStreetView = available;
        _loading = false;
      });
    }
  }

  String get _currentStreetViewUrl {
    return 'https://maps.googleapis.com/maps/api/streetview'
        '?size=600x400'
        '&location=${widget.latitude},${widget.longitude}'
        '&fov=$_fov'
        '&heading=$_heading'
        '&pitch=$_pitch'
        '&key=${GoogleMapsService.apiKey}';
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

            // Street View viewport container
            Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border, width: 1.5),
                color: AppTheme.darkBg,
              ),
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.secondary),
                    )
                  : !_hasStreetView
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.hide_image_outlined,
                                  color: AppTheme.textMuted,
                                  size: 40,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Street View is unavailable at this exact coordinate.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Fallback satellite image preview
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl:
                                        'https://maps.googleapis.com/maps/api/staticmap?center=${widget.latitude},${widget.longitude}&zoom=17&size=300x120&maptype=satellite&key=${GoogleMapsService.apiKey}',
                                    height: 100,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              key: ValueKey('$_heading-$_fov-$_pitch'),
                              imageUrl: _currentStreetViewUrl,
                              fit: BoxFit.cover,
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
                            // Compass badge overlay
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24, width: 0.5),
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    label: 'Look Up',
                    onTap: () {
                      setState(() {
                        _pitch = (_pitch + 15).clamp(-80, 80);
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    label: 'Look Down',
                    onTap: () {
                      setState(() {
                        _pitch = (_pitch - 15).clamp(-80, 80);
                      });
                    },
                  ),
                  _buildControlBtn(
                    icon: Icons.rotate_right_rounded,
                    label: 'Turn Right',
                    onTap: () {
                      setState(() {
                        _heading = (_heading + 45) % 360;
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
                          });
                        },
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in_rounded, size: 16, color: AppTheme.textMuted),
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
