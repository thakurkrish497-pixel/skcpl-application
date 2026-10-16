import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/stock_transaction_model.dart';

/// Color-coded status badge widget for the approval workflow
class StatusBadge extends StatelessWidget {
  final TransactionStatus status;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  Color get _backgroundColor {
    switch (status) {
      case TransactionStatus.pendingAccounts:
        return AppColors.pendingSurface;
      case TransactionStatus.pendingAdmin:
        return const Color(0x1A8B5CF6); // Purple tint
      case TransactionStatus.approved:
        return AppColors.approvedSurface;
      case TransactionStatus.rejected:
        return AppColors.rejectedSurface;
    }
  }

  Color get _foregroundColor {
    switch (status) {
      case TransactionStatus.pendingAccounts:
        return AppColors.pending;
      case TransactionStatus.pendingAdmin:
        return const Color(0xFF8B5CF6); // Purple
      case TransactionStatus.approved:
        return AppColors.approved;
      case TransactionStatus.rejected:
        return AppColors.rejected;
    }
  }

  IconData get _icon {
    switch (status) {
      case TransactionStatus.pendingAccounts:
        return Icons.hourglass_top_rounded;
      case TransactionStatus.pendingAdmin:
        return Icons.admin_panel_settings_outlined;
      case TransactionStatus.approved:
        return Icons.check_circle_outline_rounded;
      case TransactionStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _foregroundColor.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: compact ? 12 : 14, color: _foregroundColor),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: (compact ? AppTextStyles.caption : AppTextStyles.labelMedium)
                .copyWith(color: _foregroundColor),
          ),
        ],
      ),
    );
  }
}
