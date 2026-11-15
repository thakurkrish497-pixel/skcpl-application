import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
bool _isInitialized = false;
Future<void>? _initializing;

Future<void> _ensureInitialized() =>
    _initializing ??= _initialize().whenComplete(() => _initializing = null);

Future<void> _initialize() async {
  if (_isInitialized) return;

  try {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: WindowsInitializationSettings(
        appName: 'SKCPL',
        appUserModelId: 'SKCPL.ERP.Desktop',
        guid: 'e96b38cf-3f81-460c-9648-b327512770fb',
      ),
    );

    final initialized =
        await _localNotifications.initialize(settings: initSettings);
    if (initialized != true) {
      throw StateError('Native notifications could not initialize.');
    }
    _isInitialized = true;
  } catch (e) {
    debugPrint('[NotificationIO] Initialization error: $e');
    rethrow;
  }
}

Future<bool> requestPlatformNotificationPermission() async {
  await _ensureInitialized();

  try {
    if (Platform.isAndroid) {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } else if (Platform.isIOS) {
      final ios = _localNotifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    } else if (Platform.isMacOS) {
      final macos = _localNotifications.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await macos?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  } catch (e) {
    debugPrint('[NotificationIO] Permission request error: $e');
    return false;
  }
}

Future<bool> checkPlatformNotificationPermission() async {
  await _ensureInitialized();

  try {
    if (Platform.isAndroid) {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.areNotificationsEnabled();
      return granted ?? false;
    }
    if (Platform.isMacOS) {
      return (await _localNotifications
                  .resolvePlatformSpecificImplementation<
                      MacOSFlutterLocalNotificationsPlugin>()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    if (Platform.isIOS) {
      return (await _localNotifications
                  .resolvePlatformSpecificImplementation<
                      IOSFlutterLocalNotificationsPlugin>()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return Platform.isWindows || Platform.isLinux;
  } catch (e) {
    return false;
  }
}

Future<void> showPlatformNotification({
  required String title,
  required String body,
  String? tag,
  String? iconUrl,
}) async {
  await _ensureInitialized();

  try {
    const androidDetails = AndroidNotificationDetails(
      'skcpl_notifications',
      'SKCPL Operations & Alerts',
      channelDescription:
          'Notifications for missed cashbook entries, SLA alerts, and staff birthdays',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
      enableVibration: true,
      playSound: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: WindowsNotificationDetails(),
    );

    final notificationId = tag != null
        ? tag.codeUnits.fold<int>(
            2166136261, (hash, unit) => ((hash ^ unit) * 16777619) & 0x7fffffff)
        : DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  } catch (e) {
    debugPrint('[NotificationIO] Show notification error: $e');
    rethrow;
  }
}
