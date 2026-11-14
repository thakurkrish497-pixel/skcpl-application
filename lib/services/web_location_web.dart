import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:geolocator/geolocator.dart';

Future<Position?> _locate(bool accurate) async {
  final completer = Completer<Position?>();
  web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition pos) {
        if (completer.isCompleted) return;
        final c = pos.coords;
        completer.complete(Position(
            latitude: c.latitude,
            longitude: c.longitude,
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(pos.timestamp.toInt()),
            accuracy: c.accuracy,
            altitude: c.altitude ?? 0,
            altitudeAccuracy: c.altitudeAccuracy ?? 0,
            heading: c.heading ?? 0,
            headingAccuracy: 0,
            speed: c.speed ?? 0,
            speedAccuracy: 0));
      }).toJS,
      ((web.GeolocationPositionError error) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS,
      web.PositionOptions(
          enableHighAccuracy: accurate, timeout: 8000, maximumAge: 0));
  return completer.future
      .timeout(const Duration(seconds: 10), onTimeout: () => null);
}

Future<Position?> getWebBrowserLocation() async {
  try {
    return await _locate(true) ?? await _locate(false);
  } catch (_) {
    return null;
  }
}
