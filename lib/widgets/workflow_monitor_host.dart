import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_reminder_provider.dart';
import '../providers/workflow_monitor_provider.dart';
import '../services/notification_service.dart';
import '../services/entry_date_policy.dart';
import '../services/workflow_navigation.dart';

/// Foreground observation only: no background services, wake locks or queue calls.
class WorkflowMonitorHost extends ConsumerStatefulWidget {
  final Widget child;
  const WorkflowMonitorHost({super.key, required this.child});
  @override
  ConsumerState<WorkflowMonitorHost> createState() =>
      _WorkflowMonitorHostState();
}

class _WorkflowMonitorHostState extends ConsumerState<WorkflowMonitorHost>
    with WidgetsBindingObserver {
  WorkflowAction? _pendingAction;
  Timer? _timer;
  StreamSubscription<String>? _actions;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _actions = NotificationService.workflowActions.listen(_open);
    unawaited(NotificationService.initializeWorkflowActions());
  }

  void _open(String payload) {
    _pendingAction = WorkflowAction.decode(payload);
    _tryOpen();
  }

  void _tryOpen() {
    if (_pendingAction == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingAction == null) return;
      final recipient = ref.read(workflowRecipientProvider);
      if (recipient == null) {
        return; // Wait for the saved session/employee selection.
      }
      final action = _pendingAction!;
      _pendingAction = null;
      if (action.recipient != recipient) return;
      workflowNavigatorKey.currentState
          ?.pushNamed('/workflow-action', arguments: action);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(staffReminderForegroundProvider.notifier).state =
        state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = null;
    } else {
      ref.read(workflowPollProvider.notifier).state++;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _actions?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipient = ref.watch(workflowRecipientProvider);
    ref.listen(workflowRecipientProvider, (_, next) {
      if (next != null) _tryOpen();
    });
    final foreground = ref.watch(staffReminderForegroundProvider);
    final role = ref.watch(authProvider.select((a) => a.user?.role));
    final active = recipient != null &&
        foreground &&
        role != null &&
        role != UserRole.worker;
    if (active) {
      _timer ??= Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) ref.read(workflowPollProvider.notifier).state++;
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
    ref.listen(workflowMonitorProvider, (_, next) {
      final snapshot = next.valueOrNull;
      if (!active ||
          next.isLoading ||
          snapshot == null ||
          snapshot.warnings.isNotEmpty) {
        return;
      }
      final day = EntryDatePolicy.today().toIso8601String().substring(0, 10);
      for (final alert in snapshot.alerts.where((a) => a.needsPhone)) {
        // Admin gets one summary instead of separate, overlapping overdue popups.
        if (role == UserRole.admin && alert.kind != WorkflowKind.summary) {
          continue;
        }
        final action = WorkflowAction(recipient, alert.kind, day: day);
        unawaited(NotificationService.showWorkflowReminder(
            payload: action.payload,
            title: alert.title,
            body: alert.message,
            stillRelevant: () =>
                mounted &&
                ref.read(workflowRecipientProvider) == recipient &&
                ref.read(staffReminderForegroundProvider) &&
                !ref.read(workflowMonitorProvider).isLoading &&
                (ref
                        .read(workflowMonitorProvider)
                        .valueOrNull
                        ?.warnings
                        .isEmpty ??
                    false) &&
                (ref
                        .read(workflowMonitorProvider)
                        .valueOrNull
                        ?.alerts
                        .any((a) => a.kind == alert.kind && a.needsPhone) ??
                    false)));
      }
    });
    return widget.child;
  }
}
