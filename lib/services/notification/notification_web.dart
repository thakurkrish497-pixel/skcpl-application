import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> requestPlatformNotificationPermission() async {
  try {
    return (await web.Notification.requestPermission().toDart).toDart ==
        'granted';
  } catch (_) {
    return false;
  }
}

Future<bool> checkPlatformNotificationPermission() async {
  try {
    return web.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> showPlatformNotification(
    {required String title,
    required String body,
    String? tag,
    String? iconUrl}) async {
  try {
    if (web.Notification.permission == 'granted') {
      web.Notification(
          title,
          web.NotificationOptions(
              body: body,
              tag: tag ?? '',
              icon: iconUrl ?? 'icons/Icon-192.png'));
    }
  } catch (_) {}
}
