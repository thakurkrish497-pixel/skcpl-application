import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

/// Interactive & Aesthetic Wave Chart replicating the "Connectivity" graph
/// from the Skcpl SaaS Dashboard design mockup.
class SkcplConnectivityWaveChart extends StatelessWidget {
  final double height;
  final String title;
  final String subtitle;
  final List<double>? cyanValues;
  final List<double>? goldValues;

  const SkcplConnectivityWaveChart({
    super.key,
    this.height = 160,
    this.title = 'Site Connectivity & Activity Pulse',
    this.subtitle =
        'Real-time sync across all construction sites & head office',
    this.cyanValues,
    this.goldValues,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: AppColors.isLight ? 0.05 : 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppTextStyles.labelLarge
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: AppTextStyles.caption),
            const SizedBox(height: 8),
            const Wrap(spacing: 12, runSpacing: 4, children: [
              _LegendIndicator(
                  color: AppColors.waveCyan, label: 'Stock entries'),
              _LegendIndicator(
                  color: AppColors.goldAccent, label: 'Cash entries'),
            ]),
          ]),
          const SizedBox(height: 16),

          // Custom Painted Wave Graph
          SizedBox(
            height: height,
            width: double.infinity,
            child: cyanValues == null && goldValues == null
                ? const Center(child: Text('Activity data is unavailable'))
                : CustomPaint(
                    painter: _WaveChartPainter(
                        cyanValues ?? const [], goldValues ?? const [])),
          ),

          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 7; i++)
              _AxisLabel(i == 6
                  ? 'Today'
                  : DateFormat('EEE')
                      .format(DateTime.now().subtract(Duration(days: 6 - i)))),
          ]),
        ],
      ),
    );
  }
}

class _LegendIndicator extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendIndicator({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AxisLabel extends StatelessWidget {
  final String text;
  const _AxisLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
    );
  }
}

class _WaveChartPainter extends CustomPainter {
  final List<double> cyan, gold;
  _WaveChartPainter(this.cyan, this.gold);
  @override
  void paint(Canvas canvas, Size size) {
    final values = [...cyan, ...gold].where((v) => v.isFinite && v >= 0);
    final max = values.fold<double>(1, (a, b) => a > b ? a : b);
    final grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final (series, color) in [
      (cyan, AppColors.waveCyan),
      (gold, AppColors.goldAccent)
    ]) {
      final path = Path();
      for (var i = 0; i < series.length; i++) {
        final value = series[i].isFinite && series[i] >= 0 ? series[i] : 0;
        final x =
            series.length < 2 ? 0.0 : size.width * i / (series.length - 1);
        final y = size.height * (1 - value / max);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveChartPainter old) =>
      !listEquals(old.cyan, cyan) || !listEquals(old.gold, gold);
}

class SkcplHeroBanner extends StatelessWidget {
  final VoidCallback? onQuickAction;
  final String quickActionLabel;

  const SkcplHeroBanner({
    super.key,
    this.onQuickAction,
    this.quickActionLabel = 'Get Started',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 540;
        final logoSize = isCompact ? 85.0 : 145.0;
        final rightPadding = isCompact ? 95.0 : 185.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: AppColors.isLight
                  ? [const Color(0xFF1E3A8A), const Color(0xFF0284C7)]
                  : [const Color(0xFF0F2042), const Color(0xFF091224)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.waveCyan.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.waveCyan.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Hero logo emblem on right — clean transparent and vertically centered
                Positioned(
                  right: isCompact ? 14 : 28,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.waveCyan.withValues(alpha: 0.22),
                              blurRadius: isCompact ? 18 : 30,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color:
                                  AppColors.goldAccent.withValues(alpha: 0.15),
                              blurRadius: isCompact ? 12 : 20,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/skcpl_logo_transparent.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: EdgeInsets.fromLTRB(22, 22, rightPadding, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.waveCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.waveCyan.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: const Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(Icons.waves_rounded,
                                size: 14, color: AppColors.waveCyan),
                            SizedBox(width: 6),
                            Text(
                              'SKCPL CONNECT TO WAVES',
                              style: TextStyle(
                                color: AppColors.waveCyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Headline
                      Text(
                        'Connect to Waves',
                        style: AppTextStyles.h2.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Next-Gen Construction & Operations Management Suite',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),

                      if (onQuickAction != null) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.goldAccent,
                            foregroundColor: const Color(0xFF070D1E),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor:
                                AppColors.goldAccent.withValues(alpha: 0.4),
                          ),
                          onPressed: onQuickAction,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    quickActionLabel,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded,
                                      size: 16),
                                ],
                              )),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
