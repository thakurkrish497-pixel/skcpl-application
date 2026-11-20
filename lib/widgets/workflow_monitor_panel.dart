import '../services/workflow_navigation.dart';
import '../services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/workflow_monitor_provider.dart';
import 'notice_board_dialog.dart';

void openWorkflowAction(
    BuildContext context, WidgetRef ref, WorkflowKind kind) {
  final recipient = ref.read(workflowRecipientProvider);
  if (recipient != null) {
    (workflowNavigatorKey.currentState ?? Navigator.maybeOf(context))
        ?.pushNamed('/workflow-action',
            arguments: WorkflowAction(recipient, kind));
  }
}

class WorkflowMonitorPanel extends ConsumerWidget {
  const WorkflowMonitorPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workflowMonitorProvider);
    if (state.isLoading) {
      return const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Checking workflow reminders…'));
    }
    final snapshot = state.valueOrNull;
    if (snapshot == null) {
      return const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
              'Workflow checks are temporarily unavailable. Your work is unaffected.'));
    }
    if (snapshot.alerts.isEmpty && snapshot.warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (snapshot.warnings.isNotEmpty)
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
                'Some workflow checks are unavailable. Counts may be incomplete.')),
      for (final alert in snapshot.alerts)
        Card(
            child: ListTile(
                leading: Icon(
                    alert.needsPhone
                        ? Icons.notification_important_outlined
                        : Icons.pending_actions,
                    color:
                        alert.oldestHours >= 36 ? Colors.red : Colors.orange),
                title: Text(alert.title),
                subtitle: Text(alert.message),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openWorkflowAction(context, ref, alert.kind))),
    ]);
  }
}

void showWorkflowAlerts(BuildContext context) {
  showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('Workflow reminders'),
              content: const SizedBox(
                  width: 460,
                  child: SingleChildScrollView(child: WorkflowMonitorPanel())),
              actions: [
                TextButton(
                    onPressed: () async {
                      final granted =
                          await NotificationService.requestPermission();
                      if (ctx.mounted) {
                        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
                            content: Text(granted
                                ? 'Phone/desktop alerts enabled.'
                                : 'Notification permission was not granted. Dashboard reminders remain available.')));
                      }
                    },
                    child: const Text('Enable device alerts')),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NoticeBoardDialog.show(context);
                    },
                    child: const Text('Notice Board')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ]));
}
