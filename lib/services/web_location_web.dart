import 'dart:async';
import 'dart:html' as html;
import 'package:geolocator/geolocator.dart';

Future<Position?> getWebBrowserLocation() async {
  try {
    final geolocation = html.window.navigator.geolocation;
    if (geolocation == null) return null;

    final completer = Completer<Position?>();

    geolocation.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 8),
    ).then((pos) {
      final coords = pos.coords;
      if (coords != null && coords.latitude != null && coords.longitude != null) {
        completer.complete(Position(
          latitude: coords.latitude!.toDouble(),
          longitude: coords.longitude!.toDouble(),
          timestamp: DateTime.now(),
          accuracy: (coords.accuracy ?? 10.0).toDouble(),
          altitude: (coords.altitude ?? 0.0).toDouble(),
          altitudeAccuracy: (coords.altitudeAccuracy ?? 0.0).toDouble(),
          heading: (coords.heading ?? 0.0).toDouble(),
          headingAccuracy: 0.0,
          speed: (coords.speed ?? 0.0).toDouble(),
          speedAccuracy: 0.0,
        ));
      } else {
        completer.complete(null);
      }
    }).catchError((err) {
      // If high accuracy times out on laptop, retry without high accuracy
      geolocation.getCurrentPosition(
        enableHighAccuracy: false,
        timeout: const Duration(seconds: 10),
      ).then((pos) {
        final coords = pos.coords;
        if (coords != null && coords.latitude != null && coords.longitude != null) {
          completer.complete(Position(
            latitude: coords.latitude!.toDouble(),
            longitude: coords.longitude!.toDouble(),
            timestamp: DateTime.now(),
            accuracy: (coords.accuracy ?? 20.0).toDouble(),
            altitude: (coords.altitude ?? 0.0).toDouble(),
            altitudeAccuracy: (coords.altitudeAccuracy ?? 0.0).toDouble(),
            heading: (coords.heading ?? 0.0).toDouble(),
            headingAccuracy: 0.0,
            speed: (coords.speed ?? 0.0).toDouble(),
            speedAccuracy: 0.0,
          ));
        } else {
          completer.complete(null);
        }
      }).catchError((e2) {
        completer.complete(null);
      });
    });

    return completer.future;
  } catch (_) {
    return null;
  }
}
