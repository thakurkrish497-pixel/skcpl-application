import 'dart:js_interop';
import 'package:web/web.dart' as web;

void Function(String)? _tapHandler;
void setPlatformNotificationTapHandler(void Function(String)? handler) {
  _tapHandler = handler;
}

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
    String? iconUrl,
    String? payload}) async {
  if (web.Notification.permission != 'granted') {
    throw StateError('Notification permission is not granted.');
  }
  final notification = web.Notification(
      title,
      web.NotificationOptions(
          body: body, tag: tag ?? '', icon: iconUrl ?? 'icons/Icon-192.png'));
  if (payload != null) {
    notification.onclick = ((web.Event event) {
      _tapHandler?.call(payload);
    }).toJS;
  }
}
