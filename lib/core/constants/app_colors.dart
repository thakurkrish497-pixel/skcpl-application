import 'package:flutter/material.dart';

/// SKCPL Design System — Color Palette
/// Tailored for the "Skcpl Connect to Waves" corporate branding:
/// Supports Dark Mode (cosmic deep navy, glowing cyan, gold) AND
/// Light Mode (executive clean white & royal blue combo matching the logo).
class AppColors {
  AppColors._();

  /// Reactive state indicating if Light Mode is currently active
  static bool isLight = false;

  // ── Dark Mode Palette ──
  static const Color appBackgroundDark = Color(0xFF070D1E);
  static const Color surfaceDark       = Color(0xFF0C162E);
  static const Color cardDark          = Color(0xFF111E3D);
  static const Color cardDarkAlt       = Color(0xFF16274E);
  static const Color cardBorderDark    = Color(0xFF223A6D);
  static const Color dividerDark       = Color(0xFF1D325E);
  static const Color textPrimaryDark   = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark  = Color(0xFF64748B);

  // ── Light Mode Palette (Executive White & Logo Blue) ──
  static const Color appBackgroundLight = Color(0xFFF1F5F9); // Crisp slate-100 ice white
  static const Color surfaceLight       = Color(0xFFFFFFFF); // Pure white
  static const Color cardLight          = Color(0xFFFFFFFF); // Pure white
  static const Color cardLightAlt       = Color(0xFFF8FAFC); // Slate-50 soft card backing
  static const Color cardBorderLight    = Color(0xFFE2E8F0); // Slate-200 clean border
  static const Color dividerLight       = Color(0xFFE2E8F0); // Slate-200 divider
  static const Color textPrimaryLight   = Color(0xFF0F172A); // Slate-900 deep navy
  static const Color textSecondaryLight = Color(0xFF475569); // Slate-600 subtext
  static const Color textTertiaryLight  = Color(0xFF94A3B8); // Slate-400 caption

  // ── Legacy Aliases as const (Guarantees 100% compile-time compatibility) ──
  static const Color appBackground   = appBackgroundDark;
  static const Color scaffoldDark    = Colors.transparent;
  static const Color cardBorder      = cardBorderDark;
  static const Color divider         = dividerDark;
  static const Color textPrimary     = textPrimaryDark;
  static const Color textSecondary   = textSecondaryDark;
  static const Color textTertiary    = textTertiaryDark;

  // ── Primary Accent (Electric / Cosmic Blue from Logo) ──
  static const Color primary         = Color(0xFF2563EB);
  static const Color primaryLight    = Color(0xFF60A5FA);
  static const Color primaryDark     = Color(0xFF1D4ED8);
  static const Color primarySurface  = Color(0x262563EB);

  // ── Signature Waves (Neon Cyan & Aqua) ──
  static const Color waveCyan        = Color(0xFF00E5FF);
  static const Color waveCyanLight   = Color(0xFF67E8F9);
  static const Color waveCyanGlow    = Color(0x3300E5FF);
  static const Color secondary       = Color(0xFF14B8A6);
  static const Color secondaryLight  = Color(0xFF2DD4BF);
  static const Color secondarySurface= Color(0x1A14B8A6);

  // ── Signature Gold & Amber (From 3D Logo Swoosh & Arrow) ──
  static const Color goldAccent      = Color(0xFFFBBF24);
  static const Color goldArrow       = Color(0xFFE5A00D);
  static const Color goldGlow        = Color(0x33FBBF24);

  // ── Status Colors ──
  static const Color pending         = Color(0xFFF59E0B);
  static const Color pendingSurface  = Color(0x1AF59E0B);
  static const Color approved        = Color(0xFF10B981);
  static const Color approvedSurface = Color(0x1A10B981);
  static const Color rejected        = Color(0xFFEF4444);
  static const Color rejectedSurface = Color(0x1AEF4444);
  static const Color textOnPrimary   = Color(0xFFFFFFFF);

  // ── Theme-Adaptive Dynamic Getters ──
  static Color get background => isLight ? appBackgroundLight : appBackgroundDark;
  static Color get surface => isLight ? surfaceLight : surfaceDark;
  static Color get card => isLight ? cardLight : cardDark;
  static Color get cardAlt => isLight ? cardLightAlt : cardDarkAlt;
  static Color get border => isLight ? cardBorderLight : cardBorderDark;
  static Color get lineDivider => isLight ? dividerLight : dividerDark;
  static Color get text => isLight ? textPrimaryLight : textPrimaryDark;
  static Color get textSub => isLight ? textSecondaryLight : textSecondaryDark;
  static Color get textMuted => isLight ? textTertiaryLight : textTertiaryDark;

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient waveGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), Color(0xFFEA580C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get heroCardGradient => isLight
      ? const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : const LinearGradient(
          colors: [Color(0xFF132247), Color(0xFF0C162E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static LinearGradient get cardGradient => isLight
      ? const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : const LinearGradient(
          colors: [Color(0xFF111E3D), Color(0xFF0C162E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static const LinearGradient stockGradient = LinearGradient(
    colors: [Color(0xFF0284C7), Color(0xFF00E5FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cashGradient = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient reportGradient = LinearGradient(
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Convenience BuildContext extension for effortless theme queries
extension AppThemeContextExtension on BuildContext {
  bool get isLightMode => Theme.of(this).brightness == Brightness.light;
  Color get cardColor => isLightMode ? AppColors.cardLight : AppColors.cardDark;
  Color get surfaceColor => isLightMode ? AppColors.surfaceLight : AppColors.surfaceDark;
  Color get backgroundColor => isLightMode ? AppColors.appBackgroundLight : AppColors.appBackgroundDark;
  Color get textColor => isLightMode ? AppColors.textPrimaryLight : AppColors.textPrimaryDark;
  Color get subtextColor => isLightMode ? AppColors.textSecondaryLight : AppColors.textSecondaryDark;
  Color get borderColor => isLightMode ? AppColors.cardBorderLight : AppColors.cardBorderDark;
}
