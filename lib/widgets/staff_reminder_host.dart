import '../providers/workflow_monitor_provider.dart';
import 'workflow_monitor_panel.dart';
import '../services/entry_date_policy.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/staff_reminder_provider.dart';
import '../services/notification_service.dart';

/// Optional reminder layer. No background wake locks or submission/queue calls.
class StaffReminderHost extends ConsumerStatefulWidget {
  final Widget child;
  const StaffReminderHost({super.key, required this.child});
  @override
  ConsumerState<StaffReminderHost> createState() => _StaffReminderHostState();
}

class _StaffReminderHostState extends ConsumerState<StaffReminderHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  final _dismissed = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(staffReminderForegroundProvider.notifier).state =
        state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(staffReminderIdentityProvider);
    final foreground = ref.watch(staffReminderForegroundProvider);
    if (identity == null || !foreground) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) ref.invalidate(staffReminderCheckProvider);
      });
    }
    ref.listen(staffReminderCheckProvider, (_, next) {
      final value = next.valueOrNull;
      if (value == null || next.isLoading || identity == null || !foreground) {
        return;
      }
      for (final task in value.tasks) {
        final recipient = ref.read(workflowRecipientProvider);
        if (recipient == null) continue;
        final kind = task.task.name == 'dsr'
            ? WorkflowKind.dsr
            : WorkflowKind.attendance;
        final day = EntryDatePolicy.today().toIso8601String().substring(0, 10);
        unawaited(NotificationService.showWorkflowReminder(
            repeatAfter: null,
            payload:
                WorkflowAction(recipient, kind, day: '$day-${task.task.name}')
                    .payload,
            title: '${value.staffName}: daily task reminder',
            body: task.message,
            stillRelevant: () =>
                mounted &&
                ref.read(staffReminderIdentityProvider) == identity &&
                ref.read(staffReminderForegroundProvider) &&
                !ref.read(staffReminderCheckProvider).isLoading &&
                ((ref
                        .read(staffReminderCheckProvider)
                        .valueOrNull
                        ?.tasks
                        .any((t) => t.key == task.key)) ??
                    false)));
      }
    });
    final result = ref.watch(staffReminderCheckProvider).valueOrNull;
    final tasks =
        result?.tasks.where((t) => !_dismissed.contains(t.key)).toList() ?? [];
    return Column(children: [
      if (identity != null && foreground && tasks.isNotEmpty)
        Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
                bottom: false,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.notifications_active_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              '${result!.staffName} • ${tasks.map((t) => t.task.name == 'dsr' ? 'DSR' : t.task.name == 'punchIn' ? 'Punch-in' : 'Punch-out').join(' / ')} pending. Open the relevant entry screen to complete it.',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis)),
                      TextButton(
                          onPressed: () => openWorkflowAction(
                              context,
                              ref,
                              tasks.first.task.name == 'dsr'
                                  ? WorkflowKind.dsr
                                  : WorkflowKind.attendance),
                          child: const Text('Open')),
                      IconButton(
                          tooltip: 'Recheck daily tasks',
                          onPressed: () =>
                              ref.invalidate(staffReminderCheckProvider),
                          icon: const Icon(Icons.refresh)),
                      IconButton(
                          tooltip: 'Dismiss today’s task warning',
                          onPressed: () => setState(
                              () => _dismissed.addAll(tasks.map((t) => t.key))),
                          icon: const Icon(Icons.close)),
                    ])))),
      Expanded(
          key: const ValueKey('staff-reminder-preserved-app'),
          child: widget.child),
    ]);
  }
}
