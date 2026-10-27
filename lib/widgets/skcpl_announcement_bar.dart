import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/site_staff_model.dart';
import '../providers/birthday_provider.dart';
import '../providers/site_announcement_provider.dart';
import '../providers/auth_provider.dart';
import 'notice_board_dialog.dart';
import 'photo_viewer_dialog.dart';

/// Top In-App Announcement & Notice Bar (Slightly larger, prominent & clean):
/// 1. If any employee has a birthday today: Shows "🎉 Happy Birthday {Name}! 🎂".
/// 2. Else if an active Broadcast Notice exists: Displays "📢 {Title} • {Details}".
/// 3. Otherwise: Displays "🏢 SKCPL GROUP • Connect to Waves" with 1-click access to Notice Board.
class SkcplAnnouncementBar extends ConsumerWidget {
  final EdgeInsetsGeometry? margin;

  const SkcplAnnouncementBar({super.key, this.margin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final canPost = canUserPostAnnouncements(authState.user?.role);
    final birthdays = ref.watch(todayBirthdayStaffProvider);
    final activeNotice = ref.watch(activeAnnouncementProvider);

    final hasBirthdays = birthdays.isNotEmpty;
    final hasActiveNotice = !hasBirthdays && activeNotice != null;

    final String titleText;
    final String? subtitleText;

    if (hasBirthdays) {
      titleText = getBirthdayBarTitle(birthdays);
      subtitleText = null;
    } else if (hasActiveNotice) {
      titleText = activeNotice.title;
      subtitleText = activeNotice.message.replaceAll('\n', ' ');
    } else {
      titleText = 'SKCPL GROUP';
      subtitleText = 'Connect to Waves';
    }

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (hasBirthdays) {
              _showBirthdayDialog(context, birthdays);
            } else {
              NoticeBoardDialog.show(context);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              gradient: hasBirthdays
                  ? LinearGradient(
                      colors: [
                        const Color(0xFFF59E0B).withValues(alpha: 0.28), // Festive Amber
                        const Color(0xFFEC4899).withValues(alpha: 0.22), // Celebration Pink
                        const Color(0xFF8B5CF6).withValues(alpha: 0.25), // Royal Purple
                        AppColors.cardDark,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : hasActiveNotice
                      ? LinearGradient(
                          colors: [
                            activeNotice.category.color.withValues(alpha: 0.25),
                            const Color(0xFF1E3A8A).withValues(alpha: 0.40),
                            AppColors.cardDark,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : LinearGradient(
                          colors: [
                            AppColors.surfaceDark,
                            AppColors.cardDark,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasBirthdays
                    ? AppColors.goldAccent.withValues(alpha: 0.65)
                    : hasActiveNotice
                        ? activeNotice.category.color.withValues(alpha: 0.70)
                        : AppColors.waveCyan.withValues(alpha: 0.30),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasBirthdays
                      ? AppColors.goldAccent.withValues(alpha: 0.2)
                      : hasActiveNotice
                          ? activeNotice.category.color.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                if (hasBirthdays)
                  const Icon(
                    Icons.cake_rounded,
                    size: 19,
                    color: AppColors.goldAccent,
                  )
                      .animate(onPlay: (controller) => controller.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1.15, 1.15),
                        duration: 800.ms,
                      )
                else if (hasActiveNotice)
                  Icon(
                    activeNotice.category.icon,
                    size: 18,
                    color: activeNotice.category.color,
                  )
                      .animate(onPlay: (controller) => controller.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.95, 0.95),
                        end: const Offset(1.1, 1.1),
                        duration: 1000.ms,
                      )
                else
                  const Icon(
                    Icons.corporate_fare_rounded,
                    size: 17,
                    color: AppColors.waveCyan,
                  ),

                const SizedBox(width: 10),

                // Main Title & Subtitle
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: hasBirthdays ? 0.3 : (hasActiveNotice ? 0.2 : 1.2),
                            color: hasBirthdays
                                ? AppColors.goldAccent
                                : (hasActiveNotice ? Colors.white : AppColors.textPrimary),
                          ),
                        ),
                      ),
                      if (subtitleText != null && subtitleText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasActiveNotice ? Colors.white60 : AppColors.waveCyan.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            subtitleText,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasActiveNotice ? FontWeight.w500 : FontWeight.w600,
                              color: hasActiveNotice
                                  ? Colors.white70
                                  : AppColors.waveCyan.withValues(alpha: 0.9),
                              letterSpacing: hasActiveNotice ? 0.1 : 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Action chips
                if (hasBirthdays)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.goldAccent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.celebration_rounded, size: 13, color: AppColors.goldAccent),
                        const SizedBox(width: 4),
                        Text(
                          birthdays.length > 1 ? 'View Birthdays' : 'View',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.goldAccent,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (hasActiveNotice)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: activeNotice.category.color.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: activeNotice.category.color.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          activeNotice.hasMeetingLink ? Icons.video_call_rounded : Icons.open_in_new_rounded,
                          size: 13,
                          color: activeNotice.category.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          activeNotice.hasMeetingLink ? 'Join Zoom' : 'View Notice',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: activeNotice.category.color,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  InkWell(
                    onTap: () => NoticeBoardDialog.show(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.waveCyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.waveCyan.withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_rounded, size: 13, color: AppColors.waveCyan),
                          SizedBox(width: 4),
                          Text(
                            'Notice Board',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.waveCyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Direct "+ Post Notice" button for Admin, Project Head, and Accounts
                if (canPost) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => NoticeBoardDialog.showCreateDialog(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 14, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'Post Notice',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBirthdayDialog(BuildContext context, List<SiteStaffModel> birthdays) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppColors.goldAccent.withValues(alpha: 0.4)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          title: Row(
            children: [
              const Text('🎉', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  birthdays.length == 1
                      ? 'Today\'s Birthday Celebration!'
                      : 'Today\'s Birthday Celebrations (${birthdays.length})',
                  style: AppTextStyles.h4.copyWith(
                    color: AppColors.goldAccent,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...birthdays.map((staff) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.cardDark,
                          const Color(0xFFF59E0B).withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.goldAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.goldAccent.withValues(alpha: 0.2),
                              child: const Icon(
                                Icons.cake_rounded,
                                color: AppColors.goldAccent,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    staff.name,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    staff.role.displayName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.waveCyan,
                                    ),
                                  ),
                                  if (staff.age != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Turning ${staff.age} Years Today! 🎈',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.goldAccent,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (staff.hasAadharCard || staff.hasPanCard) ...[
                          const SizedBox(height: 10),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (staff.hasAadharCard)
                                TextButton.icon(
                                  icon: const Icon(Icons.badge_outlined, size: 14, color: AppColors.primary),
                                  label: const Text('Aadhar', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                                  onPressed: () {
                                    PhotoViewerDialog.show(context, [staff.aadharCardUrl!]);
                                  },
                                ),
                              if (staff.hasPanCard)
                                TextButton.icon(
                                  icon: const Icon(Icons.credit_card_rounded, size: 14, color: AppColors.secondary),
                                  label: const Text('PAN', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                                  onPressed: () {
                                    PhotoViewerDialog.show(context, [staff.panCardUrl!]);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.waveCyan, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SKCPL Group wishes all birthday stars good health, boundless joy and immense success!',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.campaign_outlined, size: 16, color: AppColors.waveCyan),
              label: const Text('Open Notice Board', style: TextStyle(color: AppColors.waveCyan)),
              onPressed: () {
                Navigator.pop(ctx);
                NoticeBoardDialog.show(context);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: AppColors.goldAccent)),
            ),
          ],
        );
      },
    );
  }
}
