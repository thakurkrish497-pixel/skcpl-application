import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/management_review_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/site_report_provider.dart';
import '../providers/site_provider.dart';
import '../services/management_support.dart';
import 'photo_thumbnail_strip.dart';

export '../providers/management_review_provider.dart';

class NonFinancialReviewQueue extends ConsumerStatefulWidget {
  final String module, site;
  const NonFinancialReviewQueue(
      {super.key, required this.module, this.site = 'all'});
  @override
  ConsumerState<NonFinancialReviewQueue> createState() =>
      _NonFinancialReviewQueueState();
}

class _NonFinancialReviewQueueState
    extends ConsumerState<NonFinancialReviewQueue> {
  final _busy = <String>{};
  Future<void> _decide(ReviewQueueEntry entry, bool approve) async {
    if (_busy.contains(entry.id)) return;
    final note = TextEditingController();
    var halfDay = false;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
                    title: Text(approve
                        ? 'Verify ${widget.module.toUpperCase()}'
                        : 'Reject ${widget.module.toUpperCase()}'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: note,
                          maxLength: 2000,
                          maxLines: 3,
                          decoration: InputDecoration(
                              labelText: approve
                                  ? 'Note (optional)'
                                  : 'Reason (required)')),
                      if (approve && widget.module == 'attendance')
                        CheckboxListTile(
                            title: const Text('Recommend / approve half-day'),
                            value: halfDay,
                            onChanged: (v) =>
                                setDialogState(() => halfDay = v ?? false)),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () {
                            if (!approve && note.text.trim().isEmpty) return;
                            Navigator.pop(ctx, true);
                          },
                          child: Text(approve
                              ? 'Confirm approval'
                              : 'Confirm rejection'))
                    ])));
    final reason = note.text;
    note.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(entry.id));
    try {
      await ref.read(managementReviewServiceProvider).decide(
          widget.module, entry,
          approve: approve, note: reason, halfDay: halfDay);
      if (!mounted) return;
      ref.invalidate(managementReviewQueueProvider);
      ref.invalidate(pendingRegularizationRequestsProvider);
      ref.invalidate(todayAttendanceForSiteProvider);
      ref.invalidate(allDailyReportsProvider);
      ref.invalidate(siteReportsForSiteProvider);
      ref.invalidate(siteReportsForDateProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve
              ? 'Review saved. Any remaining checkpoints still apply.'
              : 'Rejected with your reason.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Review not saved: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final siteNames = {
      for (final site in ref.watch(allSitesProvider).valueOrNull ?? [])
        site.id: site.name
    };
    final entries = ref.watch(managementReviewQueueProvider(
        (module: widget.module, site: widget.site)));
    return entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(isMissingManagementBackend(error)
                      ? 'Secure review controls require deployment of the new backend.'
                      : error.toString()),
                  TextButton(
                      onPressed: () =>
                          ref.invalidate(managementReviewQueueProvider),
                      child: const Text('Refresh'))
                ]))),
        data: (rows) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(managementReviewQueueProvider);
            },
            child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: rows.isEmpty ? 1 : rows.length,
                itemBuilder: (context, index) {
                  if (rows.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'No entries are waiting at your enabled review checkpoint.'));
                  }
                  final entry = rows[index];
                  final d = entry.data;
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    (d['staff_name'] ??
                                            d['site_name'] ??
                                            d['date'] ??
                                            widget.module.toUpperCase())
                                        .toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 8),
                                Text((d['regularization_reason'] ??
                                        d['notes'] ??
                                        d['remarks'] ??
                                        'Review the recorded entry.')
                                    .toString()),
                                if (d['site_id'] != null)
                                  Text(
                                      'Site: ${d['site_name'] ?? siteNames[d['site_id']] ?? d['site_id']}'),
                                if (d['date'] != null)
                                  Text('Date: ${d['date']}'),
                                for (final field in const {
                                  'raw_transcript': 'Voice transcript',
                                  'work_done': 'Work completed',
                                  'tomorrow_plan': 'Tomorrow’s plan',
                                  'manpower_details': 'Manpower',
                                  'materials_used': 'Materials',
                                  'remarks': 'Remarks',
                                  'punch_in_time': 'Punch in',
                                  'punch_out_time': 'Punch out',
                                  'punch_in_address': 'Punch location',
                                  'regularization_reason':
                                      'Regularization reason'
                                }.entries)
                                  if (d[field.key] != null &&
                                      d[field.key].toString().isNotEmpty)
                                    Text(
                                        '${field.value}: ${d[field.key] is List ? (d[field.key] as List).join('; ') : d[field.key]}'),
                                if (d['photo_urls'] is List)
                                  PhotoThumbnailStrip(
                                      photoUrls: (d['photo_urls'] as List)
                                          .whereType<String>()
                                          .toList(),
                                      title: 'Progress photos • Tap to zoom'),
                                if (d['selfie_url'] is String)
                                  PhotoThumbnailStrip(
                                      photoUrls: [d['selfie_url'] as String],
                                      title: 'Attendance selfie • Tap to zoom'),
                                const SizedBox(height: 12),
                                Wrap(spacing: 12, children: [
                                  TextButton(
                                      onPressed: _busy.contains(entry.id)
                                          ? null
                                          : () => _decide(entry, false),
                                      child: const Text('Reject')),
                                  ElevatedButton(
                                      onPressed: _busy.contains(entry.id)
                                          ? null
                                          : () => _decide(entry, true),
                                      child: _busy.contains(entry.id)
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Text('Approve checkpoint')),
                                ])
                              ])));
                })));
  }
}
