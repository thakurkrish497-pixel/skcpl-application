import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_colors.dart';

const String _kThemePrefKey = 'app_theme_mode';

/// Notifier to manage active App ThemeMode (Dark Mode vs Light Mode) with persistence
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_kThemePrefKey);
      if (savedTheme == 'light') {
        state = ThemeMode.light;
        AppColors.isLight = true;
      } else {
        state = ThemeMode.dark;
        AppColors.isLight = false;
      }
    } catch (e) {
      debugPrint('Error loading saved theme: $e');
    }
  }

  /// Change theme and persist to SharedPreferences
  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    AppColors.isLight = (mode == ThemeMode.light);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemePrefKey, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }

  /// Toggle between Dark Mode and Light Mode
  Future<void> toggleTheme() async {
    final nextMode = (state == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    await setTheme(nextMode);
  }

  bool get isLight => state == ThemeMode.light;
  bool get isDark => state == ThemeMode.dark;
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
