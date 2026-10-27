// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> requestPlatformNotificationPermission() async {
  try {
    if (!html.Notification.supported) return false;
    final permission = await html.Notification.requestPermission();
    return permission == 'granted';
  } catch (_) {
    return false;
  }
}

Future<bool> checkPlatformNotificationPermission() async {
  try {
    if (!html.Notification.supported) return false;
    return html.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> showPlatformNotification({
  required String title,
  required String body,
  String? tag,
  String? iconUrl,
}) async {
  try {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'granted') {
      html.Notification(
        title,
        body: body,
        tag: tag,
        icon: iconUrl ?? 'icons/Icon-192.png',
      );
    }
  } catch (_) {}
}
