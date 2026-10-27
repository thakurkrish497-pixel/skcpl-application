import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

enum LogoVariant { compact, standard, hero }

/// Official SKCPL Brand Logo component
/// Displays the 3D Earth Globe, Gold Orbital Swooshes, and Waves of Innovation logo
class SkcplBrandLogo extends StatelessWidget {
  final LogoVariant variant;
  final double? customSize;
  final bool showTagline;
  final Color? textColor;

  const SkcplBrandLogo({
    super.key,
    this.variant = LogoVariant.standard,
    this.customSize,
    this.showTagline = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case LogoVariant.compact:
        final size = customSize ?? 38.0;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.waveCyan.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.waveCyan.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/skcpl_logo_transparent.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/images/skcpl_logo.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
        );

      case LogoVariant.hero:
        final size = customSize ?? 88.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.waveCyan, AppColors.goldAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.waveCyan.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: AppColors.goldAccent.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.isLight ? Colors.transparent : const Color(0xFF080E1E),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/skcpl_logo_transparent.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/skcpl_logo.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'SKCPL',
              style: AppTextStyles.h1.copyWith(
                color: textColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            if (showTagline) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.waveCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Connect to Waves',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.goldAccent,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.goldAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case LogoVariant.standard:
        final size = customSize ?? 46.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.waveCyan, AppColors.goldAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.waveCyan.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/skcpl_logo_transparent.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/skcpl_logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SKCPL',
                      style: AppTextStyles.h3.copyWith(
                        color: textColor ?? AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.waveCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.waveCyan.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'PRO',
                        style: TextStyle(
                          color: AppColors.waveCyan,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                if (showTagline)
                  Text(
                    'Connect to Waves',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
              ],
            ),
          ],
        );
    }
  }
}
