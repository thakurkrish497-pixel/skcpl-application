import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLanguagePrefKey = 'app_language_code';

/// Notifier to manage active App Locale with SharedPreferences persistence
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_kLanguagePrefKey);
      if (savedCode != null && (savedCode == 'en' || savedCode == 'hi')) {
        state = Locale(savedCode);
      }
    } catch (e) {
      debugPrint('Error loading saved locale: $e');
    }
  }

  /// Change locale and persist to phone's SharedPreferences
  Future<void> setLocale(Locale newLocale) async {
    if (state.languageCode == newLocale.languageCode) return;
    state = newLocale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLanguagePrefKey, newLocale.languageCode);
    } catch (e) {
      debugPrint('Error saving locale: $e');
    }
  }

  /// Toggle between English and Hindi
  Future<void> toggleLocale() async {
    final nextCode = state.languageCode == 'hi' ? 'en' : 'hi';
    await setLocale(Locale(nextCode));
  }

  bool get isHindi => state.languageCode == 'hi';
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
