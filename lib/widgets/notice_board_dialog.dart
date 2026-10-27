import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/site_announcement_model.dart';
import '../providers/auth_provider.dart';
import '../providers/site_announcement_provider.dart';
import '../services/notification_service.dart';
import '../widgets/language_toggle_button.dart';
import '../core/localization/app_strings.dart';

/// Modal dialog providing the official SKCPL Notice Board:
/// - View all broadcast notices, Zoom meeting invitations & urgent alerts.
/// - Admin, Project Head, and Accounts can post new notices with 1-click broadcast to all staff.
class NoticeBoardDialog extends ConsumerStatefulWidget {
  const NoticeBoardDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const NoticeBoardDialog(),
    );
  }

  /// Directly opens the Post Announcement dialog (for Admin, Project Head, Accounts)
  static Future<void> showCreateDialog(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _CreateAnnouncementDialog(),
    );
  }

  @override
  ConsumerState<NoticeBoardDialog> createState() => _NoticeBoardDialogState();
}

class _NoticeBoardDialogState extends ConsumerState<NoticeBoardDialog> {
  String _selectedFilter = 'all'; // 'all', 'meeting', 'urgent'

  @override
  Widget build(BuildContext context) {
    final announcementsAsync = ref.watch(announcementsProvider);
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final canPost = canUserPostAnnouncements(user?.role);

    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.cardBorderDark.withValues(alpha: 0.8)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: AppColors.waveCyan, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('notice_board', defaultText: 'SKCPL Notice Board'),
                          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary, fontSize: 18),
                        ),
                        Text(
                          context.tr('active_notices', defaultText: 'Official Broadcasts, Zoom Meetings & Staff Announcements'),
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: LanguageToggleButton(isCompact: true),
                  ),
                  if (canPost)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(context.tr('post_notice', defaultText: 'Post Notice'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _showCreateAnnouncementDialog(context),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              // ── Phone & Desktop Notification Permission Banner ──
              FutureBuilder<bool>(
                future: NotificationService.isPermissionGranted(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.waveCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.waveCyan.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phonelink_ring_rounded, color: AppColors.waveCyan, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Receive instant popups on your phone & desktop for notices and Zoom meetings',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5),
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
                          onPressed: () async {
                            final granted = await NotificationService.requestPermission();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(granted
                                      ? '🔔 Phone & Desktop Notifications Activated!'
                                      : '⚠️ Notification permission not granted.'),
                                  backgroundColor: granted ? AppColors.approved : AppColors.goldAccent,
                                ),
                              );
                              setState(() {});
                            }
                          },
                          child: const Text('Enable Alerts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // ── Filter Chips ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(context.tr('all_notices', defaultText: 'All Notices'), 'all', Icons.all_inbox_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip(context.tr('zoom_meetings', defaultText: 'Zoom & Meetings'), 'meeting', Icons.video_camera_front_rounded),
                    const SizedBox(width: 8),
                    _buildFilterChip(context.tr('urgent_alerts', defaultText: 'Urgent Alerts'), 'urgent', Icons.warning_amber_rounded),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),

              // ── Notice List ──
              Expanded(
                child: announcementsAsync.when(
                  data: (list) {
                    final filtered = list.where((a) {
                      if (_selectedFilter == 'meeting') {
                        return a.category == AnnouncementCategory.meeting || a.hasMeetingLink;
                      }
                      if (_selectedFilter == 'urgent') {
                        return a.category == AnnouncementCategory.urgent;
                      }
                      return true;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mark_chat_unread_outlined, size: 48, color: AppColors.textTertiary),
                            const SizedBox(height: 12),
                            Text('No Notices Available', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                              'When Admin, Project Head or Accounts broadcast a notice, it appears here.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) => _buildNoticeCard(filtered[i], canPost),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.waveCyan)),
                  error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.rejected))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, IconData icon) {
    final isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.waveCyan.withValues(alpha: 0.18) : AppColors.cardDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.waveCyan : AppColors.cardBorderDark,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.waveCyan : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.waveCyan : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeCard(SiteAnnouncementModel notice, bool canDelete) {
    final catColor = notice.category.color;
    final isMeeting = notice.category == AnnouncementCategory.meeting || notice.hasMeetingLink;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMeeting ? AppColors.primary.withValues(alpha: 0.4) : AppColors.cardBorderDark,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category Badge & Timestamp
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: catColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(notice.category.icon, size: 12, color: catColor),
                    const SizedBox(width: 4),
                    Text(
                      notice.category.displayName,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: catColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.waveCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public_rounded, size: 11, color: AppColors.waveCyan),
                    SizedBox(width: 4),
                    Text(
                      'All Staff',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.waveCyan),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Timestamp
              Text(
                DateFormat('dd MMM, hh:mm a').format(notice.createdAt),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 10),
              ),

              if (canDelete) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _confirmDeleteNotice(notice),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Title
          Text(
            notice.title,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              fontSize: 14.5,
            ),
          ),

          // Scheduled Meeting Date/Time (if applicable)
          if (notice.scheduledAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.alarm_rounded, size: 14, color: AppColors.goldAccent),
                const SizedBox(width: 5),
                Text(
                  'Meeting Time: ${DateFormat('EEE, dd MMM yyyy • hh:mm a').format(notice.scheduledAt!)}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.goldAccent),
                ),
              ],
            ),
          ],

          const SizedBox(height: 6),

          // Message Body
          Text(
            notice.message,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),

          // Action: Join Zoom / Meeting link button
          if (notice.hasMeetingLink) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final url = notice.meetingLink!.trim();
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.video_camera_front_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Join Zoom / Video Call',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 6),

          // Footer: Author Information
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                'Posted by ${notice.createdByName} (${notice.createdByRole})',
                style: AppTextStyles.bodySmall.copyWith(fontSize: 10.5, color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteNotice(SiteAnnouncementModel notice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Delete Notice?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to delete "${notice.title}"?', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () {
              ref.read(announcementsProvider.notifier).removeAnnouncement(notice.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCreateAnnouncementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _CreateAnnouncementDialog(),
    );
  }
}

/// Simplified Dialog for publishing an announcement (Authorized: Admin, Project Head, Accounts)
/// Straightforward broadcast to everyone across the company.
class _CreateAnnouncementDialog extends ConsumerStatefulWidget {
  const _CreateAnnouncementDialog();

  @override
  ConsumerState<_CreateAnnouncementDialog> createState() =>
      _CreateAnnouncementDialogState();
}

class _CreateAnnouncementDialogState
    extends ConsumerState<_CreateAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _linkController = TextEditingController();

  AnnouncementCategory _category = AnnouncementCategory.general;
  DateTime? _scheduledAt;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.campaign_rounded, color: AppColors.waveCyan, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Broadcast Notice',
                            style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary, fontSize: 17),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Category Selector ──
                  const Text('Notice Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AnnouncementCategory.values.map((cat) {
                      final isSelected = _category == cat;
                      return ChoiceChip(
                        selected: isSelected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.icon, size: 14, color: isSelected ? Colors.white : cat.color),
                            const SizedBox(width: 5),
                            Text(cat.displayName, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : AppColors.textPrimary)),
                          ],
                        ),
                        selectedColor: cat.color,
                        backgroundColor: AppColors.cardDark,
                        onSelected: (val) {
                          if (val) setState(() => _category = cat);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // ── Broadcast Badge ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.waveCyan.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.public_rounded, size: 16, color: AppColors.waveCyan),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Broadcast Notice (Notifies all staff across all sites)',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Title Field ──
                  TextFormField(
                    controller: _titleController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      labelText: 'Notice Title *',
                      hintText: _category == AnnouncementCategory.meeting
                          ? 'e.g. Hatpipliya Zoom Meeting at 4:00 PM'
                          : 'e.g. Holiday Tomorrow / Saturday Review',
                      filled: true,
                      fillColor: AppColors.cardDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                  ),

                  const SizedBox(height: 14),

                  // ── Meeting Link & Scheduled Time (Optional) ──
                  if (_category == AnnouncementCategory.meeting) ...[
                    TextFormField(
                      controller: _linkController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Zoom / Video Call Link (Optional)',
                        hintText: 'https://zoom.us/j/... or Google Meet URL',
                        prefixIcon: const Icon(Icons.link_rounded, size: 18, color: AppColors.primary),
                        filled: true,
                        fillColor: AppColors.cardDark,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickMeetingDateTime,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.goldAccent),
                            const SizedBox(width: 8),
                            Text(
                              _scheduledAt == null
                                  ? 'Set Meeting Date & Time (Optional)'
                                  : 'Scheduled: ${DateFormat('dd MMM yyyy, hh:mm a').format(_scheduledAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _scheduledAt == null ? FontWeight.normal : FontWeight.bold,
                                color: _scheduledAt == null ? AppColors.textSecondary : AppColors.goldAccent,
                              ),
                            ),
                            const Spacer(),
                            if (_scheduledAt != null)
                              InkWell(
                                onTap: () => setState(() => _scheduledAt = null),
                                child: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textTertiary),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Message Body ──
                  TextFormField(
                    controller: _messageController,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      labelText: 'Notice Details / Message *',
                      hintText: 'Enter full details, instructions or agenda for the team...',
                      filled: true,
                      fillColor: AppColors.cardDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter notice details' : null,
                  ),

                  const SizedBox(height: 20),

                  // ── Submit Button ──
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isSubmitting ? 'Broadcasting Notice...' : 'Broadcast Notice to All',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSubmitting ? null : () => _submit(user?.fullName ?? user?.email, user?.role.displayName),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickMeetingDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _scheduledAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _submit(String? creatorName, String? creatorRole) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final model = SiteAnnouncementModel(
        id: '',
        title: _titleController.text.trim(),
        message: _messageController.text.trim(),
        category: _category,
        targetSiteId: 'all',
        targetSiteName: 'All Staff',
        meetingLink: _linkController.text.trim().isNotEmpty ? _linkController.text.trim() : null,
        scheduledAt: _scheduledAt,
        createdByName: creatorName ?? 'SKCPL Management',
        createdByRole: creatorRole ?? 'Admin',
        createdAt: DateTime.now(),
      );

      await ref.read(announcementsProvider.notifier).postAnnouncement(model);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📢 Notice Broadcasted Successfully to All Staff!'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: $e'), backgroundColor: AppColors.rejected),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
