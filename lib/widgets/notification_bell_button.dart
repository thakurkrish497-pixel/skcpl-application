import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/sla_alert_provider.dart';
import '../services/notification_service.dart';
import 'notice_board_dialog.dart';

/// Notification Bell with red alert badge counter for AppBar
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RESTRICTION: Only Accounts, Project Head, and Admin have the notification bell.
    final authState = ref.watch(authProvider);
    final userRole = authState.user?.role;
    final isApprovalAuthority = userRole == UserRole.admin ||
        userRole == UserRole.projectHead ||
        userRole == UserRole.accounts;
    if (!isApprovalAuthority) return const SizedBox.shrink();

    final alerts = ref.watch(slaAlertsProvider);
    final count = alerts.length;

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(
            count > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
            color: count > 0 ? const Color(0xFFF59E0B) : AppColors.textSecondary,
          ),
          tooltip: count > 0 ? '$count Overdue Alerts (>36h)' : 'Notifications & Alerts',
          onPressed: () => showSlaAlertsModal(context, ref),
        ),
        if (count > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Modal showing the comprehensive list of >36h SLA Alerts and push notification toggles
void showSlaAlertsModal(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final alerts = ref.watch(slaAlertsProvider);

        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.cardBorder, width: 1.2),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notification_important_rounded,
                  color: Color(0xFFF59E0B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SLA Alerts & Notifications',
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Overdue requests & missed site entries (>36h)',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phone & Desktop Alert Setting Tile
                  FutureBuilder<bool>(
                    future: NotificationService.isPermissionGranted(),
                    builder: (context, snapshot) {
                      final isGranted = snapshot.data ?? false;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isGranted ? AppColors.approved.withValues(alpha: 0.4) : AppColors.cardBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isGranted ? Icons.check_circle_rounded : Icons.phonelink_ring_rounded,
                              color: isGranted ? AppColors.approved : AppColors.waveCyan,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isGranted
                                        ? 'Phone & Desktop Alerts Active'
                                        : 'Enable Phone & Desktop Notifications',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    isGranted
                                        ? 'You will receive instant alerts on phone & desktop for broadcast notices, Zoom meetings & birthdays.'
                                        : 'Get notified for announcements, Zoom meetings & approvals even when app is minimized.',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isGranted)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.waveCyan,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () async {
                                  final ok = await NotificationService.requestPermission();
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(ok
                                            ? '🔔 Desktop & Phone Notifications Enabled!'
                                            : '⚠️ Permission not granted.'),
                                        backgroundColor: ok ? AppColors.approved : AppColors.goldAccent,
                                      ),
                                    );
                                    Navigator.pop(ctx);
                                  }
                                },
                                child: const Text(
                                  'Enable',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Alerts List
                  if (alerts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(Icons.verified_rounded, color: AppColors.approved, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            'All Caught Up!',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No pending approval requests have exceeded the 36-hour threshold.',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: alerts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final alert = alerts[index];
                        final isStock = alert.type == SlaAlertType.pendingStock;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isStock
                                      ? Icons.inventory_2_rounded
                                      : Icons.account_balance_wallet_rounded,
                                  color: const Color(0xFFEF4444),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${alert.hoursElapsed}H OVERDUE',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            alert.siteName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alert.message,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.campaign_rounded, size: 16, color: AppColors.waveCyan),
              label: const Text('Open Notice Board', style: TextStyle(color: AppColors.waveCyan)),
              onPressed: () {
                Navigator.pop(ctx);
                NoticeBoardDialog.show(context);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        );
      },
    ),
  );
}
