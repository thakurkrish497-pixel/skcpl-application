import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Separate staged drafts from submissions awaiting cloud acknowledgement.
class DraftStore {
  static Future<void> _tail = Future<void>.value();
  static Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<Map<String, dynamic>?> load(String key) => _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(key);
        return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
      });

  static Future<void> save(String key, Map<String, dynamic> data) =>
      _locked(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(key, jsonEncode(data))) {
          throw StateError(
              'Could not save staged entries on this device. Keep this form open.');
        }
      });
}
