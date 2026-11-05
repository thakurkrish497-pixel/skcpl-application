import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'web_location_helper.dart';

/// Detailed result of a location fetch attempt with actionable diagnostic info
class LocationFetchResult {
  final Position? position;
  final String? errorMessage;
  final bool isPermissionDenied;
  final bool isDeniedForever;

  const LocationFetchResult({
    this.position,
    this.errorMessage,
    this.isPermissionDenied = false,
    this.isDeniedForever = false,
  });

  bool get isSuccess => position != null;
}

/// Service providing live GPS coordinates, Geofence distance calculations,
/// and resilient browser/device diagnostic fallbacks.
class LocationService {
  /// Request GPS permission and retrieve the current position with multi-tier fallback
  static Future<Position?> getCurrentLocation() async {
    final result = await getCurrentLocationDetailed();
    return result.position;
  }

  /// Request GPS with granular diagnostics to explain why signal was blocked
  static Future<LocationFetchResult> getCurrentLocationDetailed() async {
    // 1. If running on Web, use native HTML5 Geolocation directly!
    // This completely avoids MissingPluginException and works directly with browser permissions.
    if (kIsWeb) {
      try {
        final webPos = await WebLocationHelper.getNativeWebLocation();
        if (webPos != null) {
          return LocationFetchResult(position: webPos);
        }
      } catch (_) {}
    }

    // 2. Standard Geolocator implementation (Mobile / Desktop / Fallback)
    try {
      bool serviceEnabled = true;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {}

      if (!serviceEnabled && !kIsWeb) {
        return const LocationFetchResult(
          errorMessage: 'Location Services are turned off on your device. Please turn ON Location in device Settings.',
        );
      }

      LocationPermission permission = LocationPermission.unableToDetermine;
      try {
        permission = await Geolocator.checkPermission();
      } catch (_) {}

      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (_) {}
      }

      final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return LocationFetchResult(
          isPermissionDenied: true,
          isDeniedForever: permission == LocationPermission.deniedForever,
          errorMessage: isMac
              ? 'macOS Location Permission Required: Open System Settings > Privacy & Security > Location Services, turn "SKCPL - Connect to Waves" toggle OFF and then back ON, then restart the app.'
              : (kIsWeb
                  ? 'Location is blocked. Click the tune/padlock icon next to the URL bar and allow Location.'
                  : 'Location is blocked. Please open Device Settings > Apps > SKCPL and enable Location permissions.'),
        );
      }

      final isDesktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux);

      final primaryAccuracy = isDesktop ? LocationAccuracy.medium : LocationAccuracy.high;

      // Try primary accuracy (12s timeout)
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: primaryAccuracy,
          timeLimit: const Duration(seconds: 12),
        );
        return LocationFetchResult(position: pos);
      } catch (e1) {
        // Fallback to low accuracy (Wi-Fi / cell triangulation)
        try {
          final fallbackPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 12),
          );
          return LocationFetchResult(position: fallbackPos);
        } catch (e2) {
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              return LocationFetchResult(position: lastKnown);
            }
          } catch (_) {}

          final errStr = '$e1 $e2'.toLowerCase();
          final isPerm = errStr.contains('denied') || errStr.contains('permission');

          return LocationFetchResult(
            isPermissionDenied: isPerm,
            errorMessage: isPerm
                ? (isMac
                    ? 'macOS Location Permission Required: Open System Settings > Privacy & Security > Location Services, toggle "SKCPL - Connect to Waves" OFF and ON, then restart the app.'
                    : 'Location permission was denied. Please allow location access to verify site attendance.')
                : (kIsWeb
                    ? 'GPS acquisition timed out. Please ensure Location is allowed in browser and OS settings.'
                    : 'GPS signal timed out. Please ensure Device Location is turned ON and you have clear network/Wi-Fi coverage.'),
          );
        }
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isPerm = errStr.contains('denied') || errStr.contains('permission');
      final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
      return LocationFetchResult(
        isPermissionDenied: isPerm,
        errorMessage: isPerm
            ? (isMac
                ? 'macOS Location Permission Required: In System Settings > Privacy & Security > Location Services, toggle "SKCPL - Connect to Waves" OFF and ON, then restart the app.'
                : 'Location permission denied. Please allow location access in your device Settings.')
            : (kIsWeb
                ? 'Unable to acquire GPS ($e). Please ensure Chrome has Location allowed in macOS System Settings > Privacy & Security > Location Services.'
                : 'Unable to acquire GPS ($e). Please verify Location Services are enabled on your device.'),
      );
    }
  }

  /// Open device app settings so user can grant blocked permissions with 1 tap
  static Future<bool> openAppSettings() async => Geolocator.openAppSettings();

  /// Open device GPS toggle settings
  static Future<bool> openLocationSettings() async => Geolocator.openLocationSettings();

  /// Calculates distance in meters between user's coordinates and site center
  static double calculateDistanceMeters({
    required double userLat,
    required double userLng,
    required double siteLat,
    required double siteLng,
  }) {
    return Geolocator.distanceBetween(userLat, userLng, siteLat, siteLng);
  }

  /// Checks if coordinates are within the site's allowed radius
  static bool isWithinGeofence({
    required double userLat,
    required double userLng,
    required double? siteLat,
    required double? siteLng,
    double allowedRadiusMeters = 10000.0,
  }) {
    if (siteLat == null || siteLng == null) {
      // If site has no coordinates configured yet, default to allow
      return true;
    }
    final distance = calculateDistanceMeters(
      userLat: userLat,
      userLng: userLng,
      siteLat: siteLat,
      siteLng: siteLng,
    );
    return distance <= allowedRadiusMeters;
  }
}
