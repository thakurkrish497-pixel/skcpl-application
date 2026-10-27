import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// App-wide background widget that renders a subtle, elegant, non-distracting
/// company logo watermark (without background) behind the application at all times.
/// Dynamically adapts between Dark Mode and Light Mode (White & Blue).
class AppBackgroundWatermark extends StatelessWidget {
  final Widget child;

  const AppBackgroundWatermark({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = (size.shortestSide * 0.72).clamp(260.0, 480.0);
    final isLight = AppColors.isLight;

    return Material(
      color: AppColors.appBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background Ambient Glow & Watermark Logo ──
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: isLight ? 0.08 : 0.12, // Subtle, corporate, non-distracting
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isLight ? AppColors.primary : AppColors.waveCyan)
                              .withValues(alpha: isLight ? 0.07 : 0.12),
                          blurRadius: 60,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: AppColors.goldAccent
                              .withValues(alpha: isLight ? 0.04 : 0.08),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/skcpl_logo_transparent.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/skcpl_logo.jpg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Application Content Layer ──
          child,
        ],
      ),
    );
  }
}
