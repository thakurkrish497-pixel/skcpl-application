Future<bool> requestPlatformNotificationPermission() async {
  return true;
}

Future<bool> checkPlatformNotificationPermission() async {
  return true;
}

Future<void> showPlatformNotification({
  required String title,
  required String body,
  String? tag,
  String? iconUrl,
}) async {
  // Graceful no-op on non-web platforms without native FCM plugin
}
