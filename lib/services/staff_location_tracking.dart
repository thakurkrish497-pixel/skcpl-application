import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';

/// Quality gate and independent, bounded telemetry lane. No submission queues.
class StaffLocationTracking {
  final Future<void> Function(Position) publish;
  final DateTime Function() now;
  Position? _accepted, _suspect, _pending;
  DateTime? _lastSent, _lastAttempt;
  bool _busy = false, _disposed = false;
  StaffLocationTracking({required this.publish, DateTime Function()? now})
      : now = now ?? DateTime.now;
  bool accept(Position fix) {
    if (_disposed ||
        !LocationService.isUsableAttendancePosition(fix, now: now())) {
      return false;
    }
    final previous = _accepted;
    if (previous != null) {
      final seconds =
          fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
      if (seconds <= 0) return false;
      final meters = LocationService.calculateDistanceMeters(
          userLat: fix.latitude,
          userLng: fix.longitude,
          siteLat: previous.latitude,
          siteLng: previous.longitude);
      if (meters > 60 * seconds + previous.accuracy + fix.accuracy + 30) {
        final suspect = _suspect;
        _suspect = fix;
        if (suspect == null ||
            fix.timestamp.difference(suspect.timestamp) <
                const Duration(seconds: 3) ||
            LocationService.calculateDistanceMeters(
                    userLat: fix.latitude,
                    userLng: fix.longitude,
                    siteLat: suspect.latitude,
                    siteLng: suspect.longitude) >
                50 + fix.accuracy + suspect.accuracy) {
          return false;
        }
      }
    }
    _suspect = null;
    _accepted = fix;
    if (_lastSent != null &&
        now().difference(_lastSent!) < const Duration(seconds: 20)) {
      return true;
    }
    _pending = fix;
    unawaited(_drain());
    return true;
  }

  Future<void> _drain() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      while (_pending != null && !_disposed) {
        final fix = _pending!;
        _pending = null;
        if (!LocationService.isUsableAttendancePosition(fix, now: now())) {
          continue;
        }
        if (_lastAttempt != null &&
            now().difference(_lastAttempt!) < const Duration(seconds: 20)) {
          continue;
        }
        _lastAttempt = now();
        try {
          await publish(fix);
          _lastSent = now();
        } catch (_) {/* Retry on the next valid foreground fix. */}
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
  }
}
