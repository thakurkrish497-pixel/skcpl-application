import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/providers/workflow_monitor_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/widgets/workflow_monitor_panel.dart';
import 'package:skcpl_app/screens/workflow_action_screen.dart';
import 'package:skcpl_app/screens/accounts/accounts_dashboard.dart';
import 'package:skcpl_app/screens/project_head/project_head_dashboard.dart';
import 'package:skcpl_app/screens/admin/admin_review_screen.dart';
import 'dashboard_widget_test.dart' show FixedAuth;

const snapshot = WorkflowSnapshot([
  WorkflowAlert(WorkflowKind.cash, 3, 1, 40, 'Cash vouchers: 3 pending',
      '1 overdue • tap to review')
]);
void main() {
  for (final width in [320.0, 844.0, 1440.0]) {
    testWidgets('Workflow card fits $width and routes to the matching queue',
        (t) async {
      t.view.physicalSize = Size(width, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      WorkflowAction? tapped;
      await t.pumpWidget(ProviderScope(
          overrides: [
            workflowMonitorProvider.overrideWith((ref) async => snapshot),
            workflowRecipientProvider
                .overrideWith((ref) => 'management:user:accounts')
          ],
          child: MaterialApp(
              home: const Scaffold(
                  body: SingleChildScrollView(child: WorkflowMonitorPanel())),
              onGenerateRoute: (settings) {
                tapped = settings.arguments as WorkflowAction;
                return MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Text('Pending cash queue')));
              })));
      await t.pumpAndSettle();
      expect(find.text('Cash vouchers: 3 pending'), findsOneWidget);
      await t.tap(find.text('Cash vouchers: 3 pending'));
      await t.pumpAndSettle();
      expect(tapped!.kind, WorkflowKind.cash);
      expect(tapped!.recipient, 'management:user:accounts');
      expect(find.text('Pending cash queue'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('A notification for a different employee cannot open any queue',
      (t) async {
    await t.pumpWidget(ProviderScope(
        overrides: [
          workflowRecipientProvider.overrideWith((ref) => 'staff:site:other')
        ],
        child: const MaterialApp(
            home: WorkflowActionScreen(
                action:
                    WorkflowAction('staff:site:original', WorkflowKind.dsr)))));
    await t.pumpAndSettle();
    expect(find.textContaining('account this reminder belongs to'),
        findsOneWidget);
    expect(find.byType(ProjectHeadDashboard), findsNothing);
  });
  for (final role in [
    UserRole.accounts,
    UserRole.projectHead,
    UserRole.admin
  ]) {
    testWidgets(
        '$role cash action targets the correct tab without advancing workflow',
        (t) async {
      await t.pumpWidget(ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => FixedAuth(role)),
            workflowRecipientProvider.overrideWith((ref) => 'owner'),
            workflowMonitorProvider
                .overrideWith((ref) async => const WorkflowSnapshot([]))
          ],
          child: const MaterialApp(
              home: WorkflowActionScreen(
                  action: WorkflowAction('owner', WorkflowKind.cash)))));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      if (role == UserRole.accounts) {
        expect(
            t
                .widget<AccountsDashboard>(find.byType(AccountsDashboard))
                .initialTab,
            1);
      }
      if (role == UserRole.projectHead) {
        expect(
            t
                .widget<ProjectHeadDashboard>(find.byType(ProjectHeadDashboard))
                .initialTab,
            0);
      }
      if (role == UserRole.admin) {
        expect(
            t
                .widget<AdminReviewScreen>(find.byType(AdminReviewScreen))
                .initialTab,
            1);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('Incomplete checks display a warning and preserve a typed draft',
      (t) async {
    await t.pumpWidget(ProviderScope(
        overrides: [
          workflowMonitorProvider.overrideWith((ref) async =>
              const WorkflowSnapshot([], warnings: ['Unavailable']))
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: Column(children: [
          WorkflowMonitorPanel(),
          TextField(key: ValueKey('draft'))
        ])))));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('draft')), 'Unsaved entry');
    expect(find.textContaining('may be incomplete'), findsOneWidget);
    expect(find.text('Unsaved entry'), findsOneWidget);
  });
}
