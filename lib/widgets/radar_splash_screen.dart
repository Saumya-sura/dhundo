import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RadarSplashScreen extends StatefulWidget {
  final String statusText;

  const RadarSplashScreen({
    super.key,
    this.statusText = 'Connecting to spatial network...',
  });

  @override
  State<RadarSplashScreen> createState() => _RadarSplashScreenState();
}

class _RadarSplashScreenState extends State<RadarSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background ambient gradient glow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.secondary.withValues(alpha: 0.12),
                    AppTheme.primary.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Central animated radar ripple and beacon
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ripple ring
                  _buildPulseRing(
                    scale: 1.0 + (_controller.value * 1.4),
                    opacity: (1.0 - _controller.value).clamp(0.0, 1.0) * 0.45,
                    color: AppTheme.secondary,
                    size: 160,
                  ),
                  // Middle ripple ring
                  _buildPulseRing(
                    scale: 1.0 + (((_controller.value + 0.33) % 1.0) * 1.2),
                    opacity: (1.0 - ((_controller.value + 0.33) % 1.0)).clamp(0.0, 1.0) * 0.35,
                    color: AppTheme.primaryAccent,
                    size: 140,
                  ),
                  // Inner ripple ring
                  _buildPulseRing(
                    scale: 1.0 + (((_controller.value + 0.66) % 1.0) * 0.9),
                    opacity: (1.0 - ((_controller.value + 0.66) % 1.0)).clamp(0.0, 1.0) * 0.3,
                    color: AppTheme.secondary,
                    size: 120,
                  ),

                  // Rotating radar sweep indicator
                  Transform.rotate(
                    angle: _controller.value * 2 * math.pi,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Colors.transparent,
                            AppTheme.secondary.withValues(alpha: 0.0),
                            AppTheme.secondary.withValues(alpha: 0.25),
                          ],
                          stops: const [0.0, 0.75, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Core glowing beacon
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.secondary.withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.radar_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Brand Title, Tagline & Status at Bottom
          Positioned(
            bottom: 70,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // DHUNDO title with gradient
                Text(
                  'DHUNDO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    letterSpacing: 4.0,
                    foreground: Paint()
                      ..shader = AppTheme.primaryGradient.createShader(
                        const Rect.fromLTWH(0.0, 0.0, 260.0, 70.0),
                      ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'AI LOST & FOUND MESH',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),

                // Pulsing Status Capsule
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppTheme.secondary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseRing({
    required double scale,
    required double opacity,
    required Color color,
    required double size,
  }) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
