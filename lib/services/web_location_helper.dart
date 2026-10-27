import 'package:geolocator/geolocator.dart';
import 'web_location_stub.dart'
    if (dart.library.html) 'web_location_web.dart';

class WebLocationHelper {
  /// Fetches native browser geolocation directly via HTML5 window.navigator.geolocation
  static Future<Position?> getNativeWebLocation() async {
    return getWebBrowserLocation();
  }
}
