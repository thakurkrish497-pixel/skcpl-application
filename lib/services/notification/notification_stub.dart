/// Stub implementation for non-web platforms (IO fallback)
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
  // Fallback for IO / mock
}
