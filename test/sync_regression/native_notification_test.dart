import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/services/notification_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/services/notification/notification_io.dart' as native;

void main() {
  test(
      'macOS checks permission silently, requests only explicitly and propagates delivery failures',
      () async {
    if (!Platform.isMacOS) return;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });
    final calls = <MethodCall>[];
    var granted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      if (call.method == 'checkPermissions') return {'isEnabled': granted};
      if (call.method == 'requestPermissions') {
        granted = true;
        return true;
      }
      if (call.method == 'show') {
        throw PlatformException(code: 'delivery_failed');
      }
      return true;
    });
    expect(await native.checkPlatformNotificationPermission(), isFalse);
    expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
    final settings =
        calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
    expect(settings['requestAlertPermission'], isFalse);
    expect(settings['requestBadgePermission'], isFalse);
    expect(settings['requestSoundPermission'], isFalse);
    await NotificationService.requestPermissionOnFirstUse();
    await NotificationService.requestPermissionOnFirstUse();
    expect(calls.where((c) => c.method == 'requestPermissions'), hasLength(1));
    await (await SharedPreferences.getInstance())
        .setBool('skcpl_notifications_enabled_v1', false);
    expect(await NotificationService.isPermissionGranted(), isTrue);
    expect(await native.requestPlatformNotificationPermission(), isTrue);
    expect(await native.checkPlatformNotificationPermission(), isTrue);
    await expectLater(
        native.showPlatformNotification(
            title: 'Title', body: 'Message', tag: 'test'),
        throwsA(isA<PlatformException>()));
  });
}
