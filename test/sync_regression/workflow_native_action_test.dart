import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/staff_reminder_provider.dart';
import 'package:skcpl_app/providers/workflow_monitor_provider.dart';
import 'package:skcpl_app/services/notification/notification_io.dart' as native;
import 'package:skcpl_app/services/workflow_navigation.dart';
import 'package:skcpl_app/widgets/workflow_monitor_host.dart';
import 'dashboard_widget_test.dart' show FixedAuth;

const channel = MethodChannel('dexterous.com/flutter/local_notifications');
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapNative(String payload) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(
              'didReceiveNotificationResponse',
              {'id': 1, 'notificationResponseType': 0, 'payload': payload})),
          (_) {});
}

void main() {
  testWidgets(
      'Cold-start notification opens its queue after the app restores its identity',
      (t) async {
    const action = WorkflowAction('owner', WorkflowKind.cash);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {
          'notificationLaunchedApp': true,
          'notificationResponse': {
            'id': 1,
            'notificationResponseType': 0,
            'payload': action.payload
          }
        };
      }
      return true;
    });
    WorkflowAction? opened;
    final restored = StateProvider<String?>((ref) => null);
    await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => FixedAuth(UserRole.accounts)),
          workflowRecipientProvider.overrideWith((ref) => ref.watch(restored)),
          workflowMonitorProvider
              .overrideWith((ref) async => const WorkflowSnapshot([]))
        ],
        child: MaterialApp(
            navigatorKey: workflowNavigatorKey,
            home: const WorkflowMonitorHost(
                child: Scaffold(body: Text('Dashboard'))),
            onGenerateRoute: (settings) {
              opened = settings.arguments as WorkflowAction;
              return MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('Cash action')));
            })));
    await settle(t);
    expect(opened, isNull);
    final container =
        ProviderScope.containerOf(t.element(find.byType(WorkflowMonitorHost)));
    container.read(restored.notifier).state = 'owner';
    await settle(t);
    expect(opened?.kind, WorkflowKind.cash);
    expect(find.text('Cash action'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
  testWidgets('Foreground native taps route only to their own account',
      (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    var opened = 0;
    await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => FixedAuth(UserRole.accounts)),
          workflowRecipientProvider.overrideWith((ref) => 'owner'),
          workflowMonitorProvider
              .overrideWith((ref) async => const WorkflowSnapshot([]))
        ],
        child: MaterialApp(
            navigatorKey: workflowNavigatorKey,
            home: const WorkflowMonitorHost(
                child: Scaffold(body: Text('Dashboard'))),
            onGenerateRoute: (settings) {
              opened++;
              return MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('Target queue')));
            })));
    await settle(t);
    await tapNative(
        const WorkflowAction('someone-else', WorkflowKind.stock).payload);
    await settle(t);
    expect(opened, 0);
    await tapNative(const WorkflowAction('owner', WorkflowKind.stock).payload);
    await settle(t);
    expect(opened, 1);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
  testWidgets(
      'Monitoring polls at five minutes, pauses in background, resumes and preserves draft text',
      (t) async {
    await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => FixedAuth(UserRole.accounts)),
          workflowRecipientProvider.overrideWith((ref) => 'owner'),
          workflowMonitorProvider
              .overrideWith((ref) async => const WorkflowSnapshot([]))
        ],
        child: const MaterialApp(
            home: WorkflowMonitorHost(
                child: Scaffold(body: TextField(key: ValueKey('draft')))))));
    await settle(t);
    final container =
        ProviderScope.containerOf(t.element(find.byType(WorkflowMonitorHost)));
    await t.enterText(find.byKey(const ValueKey('draft')), 'Work in progress');
    final initial = container.read(workflowPollProvider);
    await t.pump(const Duration(minutes: 4));
    expect(container.read(workflowPollProvider), initial);
    await t.pump(const Duration(minutes: 1));
    expect(container.read(workflowPollProvider), initial + 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    final paused = container.read(workflowPollProvider);
    await t.pump(const Duration(minutes: 10));
    expect(container.read(workflowPollProvider), paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(container.read(workflowPollProvider), paused + 1);
    expect(find.text('Work in progress'), findsOneWidget);
    expect(container.read(staffReminderForegroundProvider), isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 10));
    expect(t.takeException(), isNull);
  });
  test(
      'Native notification carries its workflow payload without changing other notification types',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    const action = WorkflowAction('owner', WorkflowKind.dsr);
    await native.showPlatformNotification(
        title: 'Pending DSR',
        body: 'Check report',
        payload: action.payload,
        tag: action.payload);
    final args = calls.lastWhere((c) => c.method == 'show').arguments as Map;
    expect(args['payload'], action.payload);
    final decoded = WorkflowAction.decode(args['payload'] as String)!;
    expect(decoded.kind, WorkflowKind.dsr);
    // Standard notices and birthdays still have no workflow navigation payload.
    calls.clear();
    await native.showPlatformNotification(
        title: 'Birthday', body: 'Happy birthday', tag: 'birthday_id');
    final birthdayPayload =
        (calls.lastWhere((c) => c.method == 'show').arguments as Map)['payload']
            as String?;
    expect(WorkflowAction.decode(birthdayPayload), isNull);
  });
}
