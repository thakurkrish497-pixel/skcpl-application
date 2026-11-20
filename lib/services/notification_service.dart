import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification/notification_stub.dart'
    if (dart.library.js_interop) 'notification/notification_web.dart'
    if (dart.library.io) 'notification/notification_io.dart';

/// Serialized notification delivery only; never accesses transaction queues.
class NotificationDelivery {
  final Future<bool> Function() permission;
  final Future<void> Function(
      {required String title, required String body, String? tag}) show;
  final DateTime Function() now;
  Future<void> _tail = Future.value();
  static const ledgerKey = 'skcpl_sent_sla_alerts_v1';

  NotificationDelivery(
      {required this.permission, required this.show, DateTime Function()? now})
      : now = now ?? DateTime.now;

  Future<void> send(
      {required String key,
      required String title,
      required String body,
      Duration? repeatAfter,
      bool Function()? stillRelevant}) {
    final result = _tail.then((_) async {
      try {
        if (stillRelevant?.call() == false) return;
        if (!await permission()) return;
        if (stillRelevant?.call() == false) return;
        final prefs = await SharedPreferences.getInstance();
        final sent = prefs.getStringList(ledgerKey) ?? [];
        final time = now();
        final stamp = time.millisecondsSinceEpoch;
        final previous = sent.where((e) => e.startsWith('$key:'));
        if (previous.isNotEmpty) {
          final last = int.tryParse(previous.last.substring(key.length + 1));
          if (last != null &&
              (repeatAfter == null ||
                  stamp - last < repeatAfter.inMilliseconds)) {
            return;
          }
        }
        if (stillRelevant?.call() == false) return;
        await show(title: title, body: body, tag: key);
        sent.removeWhere((e) => e.startsWith('$key:'));
        // Keep all birthday recipients for today, even in a large workforce.
        // Retain notice deduplication for 90 days; old SLA and birthday keys expire.
        sent.removeWhere((e) {
          final split = e.lastIndexOf(':');
          final last = split < 0 ? null : int.tryParse(e.substring(split + 1));
          if (last == null) return true;
          final age = stamp - last;
          return age >
              (e.startsWith('announcement_')
                      ? const Duration(days: 90)
                      : const Duration(days: 2))
                  .inMilliseconds;
        });
        sent.add('$key:$stamp');
        await prefs.setStringList(ledgerKey, sent);
      } catch (error) {
        // A failed native delivery must remain eligible for retry.
        debugPrint('[Notifications] Delivery unavailable: $error');
      }
    });
    _tail = result;
    return result;
  }
}

class NotificationService {
  static final _workflowActions = StreamController<String>.broadcast();
  static bool _actionsBound = false;
  static Stream<String> get workflowActions {
    if (!_actionsBound) {
      _actionsBound = true;
      setPlatformNotificationTapHandler(
          (payload) => _workflowActions.add(payload));
    }
    return _workflowActions.stream;
  }

  static Future<void> initializeWorkflowActions() async {
    await isPermissionGranted(); // Silent initialization, including launch taps.
  }

  static Future<void> showWorkflowReminder(
          {required String payload,
          required String title,
          required String body,
          required bool Function() stillRelevant,
          Duration? repeatAfter = const Duration(hours: 6)}) =>
      _delivery.send(
          key: payload,
          title: title,
          body: body,
          repeatAfter: repeatAfter,
          stillRelevant: stillRelevant);

  static final _permissionChanges = StreamController<void>.broadcast();
  static Stream<void> get permissionChanges => _permissionChanges.stream;
  static final _delivery = NotificationDelivery(
      permission: isPermissionGranted,
      show: ({required title, required body, tag}) => showPlatformNotification(
          title: title,
          body: body,
          tag: tag,
          payload: tag?.startsWith('workflow.v1.') == true ? tag : null));

  static Future<void>? _startupPermission;
  static Future<void> requestPermissionOnFirstUse() => _startupPermission ??=
      _requestOnFirstUse().whenComplete(() => _startupPermission = null);
  static Future<void> _requestOnFirstUse() async {
    if (kIsWeb) return; // Browser permission needs an explicit button gesture.
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'skcpl_notification_permission_prompted_v1';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
      if (!await isPermissionGranted()) await requestPermission();
    } catch (_) {/* Optional notifications never block sign-in. */}
  }

  static Future<bool> requestPermission() async {
    try {
      final granted = await requestPlatformNotificationPermission();
      _permissionChanges.add(null);
      return granted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPermissionGranted() async {
    try {
      return await checkPlatformNotificationPermission();
    } catch (_) {
      return false;
    }
  }

  static Future<void> showDailyTaskReminder(
          {required String key,
          required String title,
          required String body,
          required bool Function() stillRelevant}) =>
      _delivery.send(
          key: key, title: title, body: body, stillRelevant: stillRelevant);

  static Future<void> showSlaNotification(
          {required String title,
          required String body,
          required String alertKey}) =>
      _delivery.send(
          key: alertKey,
          title: title,
          body: body,
          repeatAfter: const Duration(hours: 6));

  static Future<void> showBirthdayNotification(
      {required String staffId, required String staffName}) {
    final now = DateTime.now();
    return _delivery.send(
        key: 'birthday_${staffId}_${now.year}_${now.month}_${now.day}',
        title: '🎂 Happy Birthday $staffName!',
        body: "SKCPL wishes $staffName happiness, good health & success!");
  }

  static Future<void> showAnnouncementNotification(
          {required String announcementId,
          required String title,
          required String body,
          String? targetSiteName}) =>
      _delivery.send(
          key: 'announcement_$announcementId',
          title: targetSiteName != null &&
                  targetSiteName.isNotEmpty &&
                  targetSiteName != 'All Sites' &&
                  targetSiteName != 'All Staff'
              ? '📢 [$targetSiteName] $title'
              : '📢 $title',
          body: body);
}
