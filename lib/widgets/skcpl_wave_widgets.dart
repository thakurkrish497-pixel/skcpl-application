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
    this.subtitle = 'Real-time sync across all construction sites & head office',
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
            color: Colors.black.withValues(alpha: AppColors.isLight ? 0.05 : 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.waveCyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Legend chips
              Row(
                children: [
                  _LegendIndicator(color: AppColors.waveCyan, label: 'Stock & DSR'),
                  const SizedBox(width: 12),
                  _LegendIndicator(color: AppColors.goldAccent, label: 'Cash & Attend.'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Painted Wave Graph
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveChartPainter(),
            ),
          ),

          const SizedBox(height: 10),
          // Day labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _AxisLabel('Mon'),
              _AxisLabel('Tue'),
              _AxisLabel('Wed'),
              _AxisLabel('Thu'),
              _AxisLabel('Fri'),
              _AxisLabel('Sat'),
              _AxisLabel('Today (Sun)'),
            ],
          ),
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
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.4)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    const int lines = 4;
    for (int i = 0; i <= lines; i++) {
      final y = size.height * (i / lines);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Cyan Wave (Smooth cubic bezier curve)
    final cyanPath = Path();
    final cyanFill = Path();
    final List<Offset> cyanPoints = [
      Offset(0, size.height * 0.75),
      Offset(size.width * 0.16, size.height * 0.60),
      Offset(size.width * 0.33, size.height * 0.30),
      Offset(size.width * 0.50, size.height * 0.55),
      Offset(size.width * 0.66, size.height * 0.20),
      Offset(size.width * 0.83, size.height * 0.40),
      Offset(size.width, size.height * 0.15),
    ];

    cyanPath.moveTo(cyanPoints[0].dx, cyanPoints[0].dy);
    cyanFill.moveTo(cyanPoints[0].dx, cyanPoints[0].dy);

    for (int i = 0; i < cyanPoints.length - 1; i++) {
      final p0 = cyanPoints[i];
      final p1 = cyanPoints[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      cyanPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p1.dx, p1.dy);
      cyanFill.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p1.dx, p1.dy);
    }

    cyanFill.lineTo(size.width, size.height);
    cyanFill.lineTo(0, size.height);
    cyanFill.close();

    // Fill cyan gradient
    final cyanGradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.waveCyan.withValues(alpha: 0.25),
          AppColors.waveCyan.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(cyanFill, cyanGradient);

    // Cyan stroke
    final cyanStroke = Paint()
      ..color = AppColors.waveCyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(cyanPath, cyanStroke);

    // Gold Wave (Undulating secondary wave)
    final goldPath = Path();
    final List<Offset> goldPoints = [
      Offset(0, size.height * 0.55),
      Offset(size.width * 0.16, size.height * 0.35),
      Offset(size.width * 0.33, size.height * 0.70),
      Offset(size.width * 0.50, size.height * 0.25),
      Offset(size.width * 0.66, size.height * 0.45),
      Offset(size.width * 0.83, size.height * 0.28),
      Offset(size.width, size.height * 0.50),
    ];

    goldPath.moveTo(goldPoints[0].dx, goldPoints[0].dy);
    for (int i = 0; i < goldPoints.length - 1; i++) {
      final p0 = goldPoints[i];
      final p1 = goldPoints[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      goldPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p1.dx, p1.dy);
    }

    final goldStroke = Paint()
      ..color = AppColors.goldAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(goldPath, goldStroke);

    // Highlight dot on latest data point
    final lastPoint = cyanPoints.last;
    final dotGlow = Paint()
      ..color = AppColors.waveCyan.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 8, dotGlow);

    final dotInner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 3.5, dotInner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Aesthetic Hero Banner for the Home & Admin screens
/// Replicating the "Connecting You to Waves of Innovation" hero panel from the user's design!
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
                              color: AppColors.goldAccent.withValues(alpha: 0.15),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.waveCyan.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.waves_rounded, size: 14, color: AppColors.waveCyan),
                        const SizedBox(width: 6),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.goldAccent.withValues(alpha: 0.4),
                      ),
                      onPressed: onQuickAction,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            quickActionLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
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
