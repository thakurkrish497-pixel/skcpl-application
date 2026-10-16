import 'package:flutter/material.dart';

/// SKCPL Design System — Color Palette
/// Premium dark theme with construction-grade accent colors
class AppColors {
  AppColors._();

  // ── Base / Background ──
  static const Color scaffoldDark    = Color(0xFF0A0E1A);
  static const Color surfaceDark     = Color(0xFF111827);
  static const Color cardDark        = Color(0xFF1A2332);
  static const Color cardDarkAlt     = Color(0xFF1E293B);
  static const Color divider         = Color(0xFF2A3441);

  // ── Primary Accent (Electric Blue) ──
  static const Color primary         = Color(0xFF3B82F6);
  static const Color primaryLight    = Color(0xFF60A5FA);
  static const Color primaryDark     = Color(0xFF1D4ED8);
  static const Color primarySurface  = Color(0x1A3B82F6); // 10% opacity

  // ── Secondary Accent (Teal) ──
  static const Color secondary       = Color(0xFF14B8A6);
  static const Color secondaryLight  = Color(0xFF2DD4BF);
  static const Color secondarySurface= Color(0x1A14B8A6);

  // ── Status Colors ──
  static const Color pending         = Color(0xFFF59E0B); // Amber
  static const Color pendingSurface  = Color(0x1AF59E0B);
  static const Color approved        = Color(0xFF10B981); // Emerald
  static const Color approvedSurface = Color(0x1A10B981);
  static const Color rejected        = Color(0xFFEF4444); // Rose
  static const Color rejectedSurface = Color(0x1AEF4444);

  // ── Text ──
  static const Color textPrimary     = Color(0xFFF1F5F9);
  static const Color textSecondary   = Color(0xFF94A3B8);
  static const Color textTertiary    = Color(0xFF64748B);
  static const Color textOnPrimary   = Color(0xFFFFFFFF);

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A2332), Color(0xFF111827)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient stockGradient = LinearGradient(
    colors: [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cashGradient = LinearGradient(
    colors: [Color(0xFF14B8A6), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
