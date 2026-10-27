import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/sla_alert_provider.dart';
import '../services/notification_service.dart';
import 'notification_bell_button.dart';

/// In-App Notification Bar specifically for >36h Overdue Stock & Cash Approval Alerts
class SlaNotificationBar extends ConsumerStatefulWidget {
  final VoidCallback? onAlertTap;

  const SlaNotificationBar({super.key, this.onAlertTap});

  @override
  ConsumerState<SlaNotificationBar> createState() => _SlaNotificationBarState();
}

class _SlaNotificationBarState extends ConsumerState<SlaNotificationBar> {
  bool _isDismissed = false;
  bool _hasCheckedPermission = false;
  bool _isPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await NotificationService.isPermissionGranted();
    if (mounted) {
      setState(() {
        _isPermissionGranted = granted;
        _hasCheckedPermission = true;
      });
    }
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService.requestPermission();
    if (mounted) {
      setState(() => _isPermissionGranted = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
              ? '🔔 Desktop & Phone Notifications Enabled!'
              : '⚠️ Notification permission was not granted by your browser/device.',
          ),
          backgroundColor: granted ? AppColors.approved : AppColors.goldAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) return const SizedBox.shrink();

    // RESTRICTION: Only Accounts, Project Head, and Admin see SLA approval alerts.
    final authState = ref.watch(authProvider);
    final userRole = authState.user?.role;
    final isApprovalAuthority = userRole == UserRole.admin ||
        userRole == UserRole.projectHead ||
        userRole == UserRole.accounts;
    if (!isApprovalAuthority) return const SizedBox.shrink();

    final alerts = ref.watch(slaAlertsProvider);
    if (alerts.isEmpty && _isPermissionGranted) {
      return const SizedBox.shrink();
    }

    // If there are alerts, show the glowing overdue notification bar
    if (alerts.isNotEmpty) {
      final topAlert = alerts.first;
      final totalCount = alerts.length;

      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFDC2626).withValues(alpha: 0.22), // Soft Crimson
              const Color(0xFFF59E0B).withValues(alpha: 0.16), // Amber
              AppColors.cardDark,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Glowing Warning Icon
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notification_important_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),

            // Notification Message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$totalCount OVERDUE (>36h)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          topAlert.title,
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalCount > 1
                        ? '${topAlert.message} (+$totalCount more overdue items across sites)'
                        : topAlert.message,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Action: View All Details
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.waveCyan.withValues(alpha: 0.15),
                foregroundColor: AppColors.waveCyan,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppColors.waveCyan.withValues(alpha: 0.4)),
                ),
              ),
              onPressed: () {
                showSlaAlertsModal(context, ref);
                widget.onAlertTap?.call();
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: const Text('View All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),

            // Close / Dismiss Icon
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 18),
              tooltip: 'Dismiss banner',
              onPressed: () => setState(() => _isDismissed = true),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.08);
    }

    // Permission Prompt Bar (if user hasn't enabled phone/desktop notifications yet)
    if (!_isPermissionGranted && _hasCheckedPermission) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: AppColors.waveCyan, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable phone & desktop alerts to never miss overdue stock entries (>36h).',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.waveCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: _requestPermission,
              child: const Text(
                'Enable Alerts',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 16),
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _isDismissed = true),
              padding: const EdgeInsets.only(left: 6),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
