import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/site_provider.dart';
import '../providers/workflow_monitor_provider.dart';
import '../widgets/nonfinancial_review_queue.dart';
import 'accounts/accounts_dashboard.dart';
import 'project_head/project_head_dashboard.dart';
import 'admin/admin_review_screen.dart';
import 'attendance/punch_attendance_screen.dart';
import 'site_reports/record_site_report_screen.dart';

class WorkflowActionScreen extends ConsumerWidget {
  final WorkflowAction action;
  const WorkflowActionScreen({super.key, required this.action});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (action.recipient != ref.watch(workflowRecipientProvider)) {
      return const Scaffold(
          body: Center(
              child: Text('Sign in to the account this reminder belongs to.')));
    }
    final role = ref.watch(authProvider).user?.role;
    if (role == null || role == UserRole.worker) {
      if (action.kind == WorkflowKind.attendance) {
        return const PunchAttendanceScreen();
      }
      if (action.kind == WorkflowKind.dsr) {
        return const RecordSiteReportScreen();
      }
      return const Scaffold(
          body: Center(
              child: Text('This reminder is unavailable for this account.')));
    }
    switch (action.kind) {
      case WorkflowKind.cash:
      case WorkflowKind.stock:
        final cash = action.kind == WorkflowKind.cash;
        if (role == UserRole.admin) {
          return AdminReviewScreen(initialTab: cash ? 1 : 0);
        }
        if (role == UserRole.accounts) {
          return AccountsDashboard(initialTab: cash ? 1 : 0);
        }
        return ProjectHeadDashboard(initialTab: cash ? 0 : 1);
      case WorkflowKind.dsr:
      case WorkflowKind.attendance:
        return Scaffold(
            appBar: AppBar(
                title: Text(action.kind == WorkflowKind.dsr
                    ? 'Pending DSR checks'
                    : 'Pending attendance reviews')),
            body: NonFinancialReviewQueue(module: action.kind.name));
      case WorkflowKind.summary:
        if (role != UserRole.admin) {
          return const Scaffold(
              body: Center(child: Text('Admin access required.')));
        }
        final snapshot = ref.watch(workflowMonitorProvider);
        final sites = ref.watch(allSitesProvider).valueOrNull ?? [];
        return Scaffold(
            appBar: AppBar(title: const Text('Overdue site workflow')),
            body: snapshot.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                    child:
                        Text('Workflow checks are unavailable. Please retry.')),
                data: (data) => ListView(children: [
                      if (data.warnings.isNotEmpty)
                        const ListTile(
                            title: Text(
                                'Some checks are unavailable. This list may be incomplete.')),
                      if (data.bottlenecks.isEmpty)
                        const ListTile(
                            title: Text('No verified overdue items.')),
                      for (final item in data.bottlenecks)
                        ListTile(
                            title: Text(sites
                                    .where((s) => s.id == item.siteId)
                                    .firstOrNull
                                    ?.name ??
                                'Site ${item.siteId}'),
                            subtitle: Text(
                                '${item.kind.name.toUpperCase()} • waiting for ${item.waitingFor} • submitted ${item.hours}h ago'),
                            trailing: item.waitingFor == 'Admin'
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: item.waitingFor == 'Admin'
                                ? () => Navigator.of(context).pushNamed(
                                    '/workflow-action',
                                    arguments: WorkflowAction(
                                        action.recipient, item.kind))
                                : null),
                    ])));
    }
  }
}
