import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

/// Warning banner displayed on locked/approved form records
class LockedFormBanner extends StatelessWidget {
  final String message;
  final bool isRejected;

  const LockedFormBanner({
    super.key,
    this.message = 'This record is under review or approved. You can no longer edit it.',
    this.isRejected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isRejected ? AppColors.rejected : AppColors.pending;
    final bgColor = isRejected ? AppColors.rejectedSurface : AppColors.pendingSurface;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isRejected ? Icons.cancel_rounded : Icons.lock_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
