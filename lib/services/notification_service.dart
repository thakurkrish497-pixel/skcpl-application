import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification/notification_stub.dart'
    if (dart.library.html) 'notification/notification_web.dart'
    if (dart.library.io) 'notification/notification_io.dart';

/// Cross-platform notification service for phone and desktop alerts
class NotificationService {
  static const String _keyNotificationPref = 'skcpl_notifications_enabled_v1';
  static const String _keySentAlerts = 'skcpl_sent_sla_alerts_v1';

  /// Request browser or device notification permission
  static Future<bool> requestPermission() async {
    final granted = await requestPlatformNotificationPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationPref, granted);
    return granted;
  }

  /// Check whether notifications are permitted
  static Future<bool> isPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    final userPref = prefs.getBool(_keyNotificationPref);
    if (userPref == false) return false;
    return await checkPlatformNotificationPermission();
  }

  /// Show a desktop/phone notification with intelligent 6-hour rate limiting
  static Future<void> showSlaNotification({
    required String title,
    required String body,
    required String alertKey, // Unique key for this alert (e.g. 'stock_pending_id_36h')
  }) async {
    final permitted = await isPermissionGranted();
    if (!permitted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sentMap = prefs.getStringList(_keySentAlerts) ?? [];

      // Check if this alert was already triggered within the last 6 hours
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final recentEntry = sentMap.firstWhere(
        (e) => e.startsWith('$alertKey:'),
        orElse: () => '',
      );

      if (recentEntry.isNotEmpty) {
        final lastSentMs = int.tryParse(recentEntry.split(':')[1]) ?? 0;
        if (nowMs - lastSentMs < 6 * 3600 * 1000) {
          // Already notified recently, skip duplicate ping
          return;
        }
      }

      // Show native platform notification
      await showPlatformNotification(
        title: title,
        body: body,
        tag: alertKey,
      );

      // Record timestamp
      sentMap.removeWhere((e) => e.startsWith('$alertKey:'));
      sentMap.add('$alertKey:$nowMs');
      // Keep last 100 entries
      if (sentMap.length > 100) sentMap.removeAt(0);
      await prefs.setStringList(_keySentAlerts, sentMap);
    } catch (e) {
      debugPrint('[NotificationService] Failed to show notification: $e');
    }
  }

  /// Show birthday notification for an employee, rate-limited to once per calendar day per employee.
  /// If there are multiple employees with birthdays today, this is called for each employee
  /// so users receive notifications for all celebrating staff members.
  static Future<void> showBirthdayNotification({
    required String staffId,
    required String staffName,
  }) async {
    final permitted = await isPermissionGranted();
    if (!permitted) return;

    final now = DateTime.now();
    final todayKey = '${now.year}_${now.month}_${now.day}';
    final alertKey = 'birthday_${staffId}_$todayKey';

    try {
      final prefs = await SharedPreferences.getInstance();
      final sentMap = prefs.getStringList(_keySentAlerts) ?? [];

      if (sentMap.any((e) => e.startsWith('$alertKey:'))) {
        return; // Already notified today
      }

      await showPlatformNotification(
        title: '🎂 Happy Birthday $staffName!',
        body: 'Today is $staffName\'s Birthday! SKCPL wishes them happiness, good health & success!',
        tag: alertKey,
      );

      final nowMs = now.millisecondsSinceEpoch;
      sentMap.add('$alertKey:$nowMs');
      if (sentMap.length > 100) sentMap.removeAt(0);
      await prefs.setStringList(_keySentAlerts, sentMap);
    } catch (e) {
      debugPrint('[NotificationService] Failed to show birthday notification: $e');
    }
  }

  /// Show company-wide or sitewise broadcast announcement notification on desktop & phone
  static Future<void> showAnnouncementNotification({
    required String announcementId,
    required String title,
    required String body,
    String? targetSiteName,
  }) async {
    final permitted = await isPermissionGranted();
    if (!permitted) return;

    final alertKey = 'announcement_$announcementId';

    try {
      final prefs = await SharedPreferences.getInstance();
      final sentMap = prefs.getStringList(_keySentAlerts) ?? [];

      if (sentMap.any((e) => e.startsWith('$alertKey:'))) {
        return; // Already notified
      }

      final header = (targetSiteName != null &&
              targetSiteName != 'All Sites' &&
              targetSiteName.isNotEmpty)
          ? '📢 [$targetSiteName] $title'
          : '📢 $title';

      await showPlatformNotification(
        title: header,
        body: body,
        tag: alertKey,
      );

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      sentMap.add('$alertKey:$nowMs');
      if (sentMap.length > 100) sentMap.removeAt(0);
      await prefs.setStringList(_keySentAlerts, sentMap);
    } catch (e) {
      debugPrint('[NotificationService] Failed to show announcement notification: $e');
    }
  }
}
