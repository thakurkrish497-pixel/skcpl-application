import '../../widgets/entry_date_picker.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dsr_history_provider.dart';
import '../../providers/site_provider.dart';
import '../../widgets/photo_thumbnail_strip.dart';

/// All management roles share this read-only archive, regardless of approval power.
class DsrHistoryScreen extends ConsumerStatefulWidget {
  final String? initialSiteId;
  const DsrHistoryScreen({super.key, this.initialSiteId});
  @override
  ConsumerState<DsrHistoryScreen> createState() => _DsrHistoryScreenState();
}

class _DsrHistoryScreenState extends ConsumerState<DsrHistoryScreen> {
  late String _site = widget.initialSiteId ?? 'all';
  DateTimeRange? _dates;
  String _status = 'all';
  Future<void> _chooseDates() async {
    final range = await showEntryDateRangePicker(
        context: context, firstDate: DateTime(1900), initialDateRange: _dates);
    if (range != null && mounted) setState(() => _dates = range);
  }

  Future<void> _refresh() async {
    try {
      await ref.refresh(dsrHistoryProvider.future).then<void>((_) {});
    } catch (_) {/* Error is displayed by the provider. */}
  }

  @override
  Widget build(BuildContext context) {
    if (!canViewDsrHistory(ref.watch(authProvider).user?.role)) {
      return const Scaffold(
          body: Center(
              child:
                  Text('Management sign-in is required to view DSR history.')));
    }
    final history = ref.watch(dsrHistoryProvider);
    final sites = ref.watch(allSitesProvider).valueOrNull ?? [];
    final names = {for (final site in sites) site.id: site.name};
    for (final entry in history.valueOrNull?.entries ?? <DsrHistoryEntry>[]) {
      names.putIfAbsent(entry.report.siteId,
          () => entry.report.siteName ?? entry.report.siteId);
    }
    if (_site != 'all') names.putIfAbsent(_site, () => _site);
    final ordered = names.keys.toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!));
    return Scaffold(
      appBar: AppBar(title: const Text('DSR History'), actions: [
        IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh DSR history',
            icon: const Icon(Icons.refresh))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Read-only history • approvals and original submissions are preserved'),
                          const SizedBox(height: 8),
                          Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                    width: 250,
                                    child: DropdownButtonFormField<String>(
                                        initialValue: _site,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Site'),
                                        items: [
                                          const DropdownMenuItem(
                                              value: 'all',
                                              child: Text('All sites')),
                                          ...ordered.map((id) =>
                                              DropdownMenuItem(
                                                  value: id,
                                                  child: Text(names[id]!,
                                                      overflow: TextOverflow
                                                          .ellipsis)))
                                        ],
                                        onChanged: (v) => setState(
                                            () => _site = v ?? 'all'))),
                                SizedBox(
                                    width: 250,
                                    child: DropdownButtonFormField<String>(
                                        initialValue: _status,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Review status'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'all',
                                              child: Text('All reports')),
                                          DropdownMenuItem(
                                              value: 'approved',
                                              child: Text('Approved')),
                                          DropdownMenuItem(
                                              value: 'reviewed',
                                              child: Text('Reviewed')),
                                          DropdownMenuItem(
                                              value: 'pending',
                                              child: Text('Pending review')),
                                          DropdownMenuItem(
                                              value: 'rejected',
                                              child: Text('Rejected'))
                                        ],
                                        onChanged: (v) => setState(
                                            () => _status = v ?? 'all'))),
                                OutlinedButton.icon(
                                    onPressed: _chooseDates,
                                    icon: const Icon(Icons.date_range),
                                    label: Text(_dates == null
                                        ? 'All dates'
                                        : '${DateFormat('dd MMM yyyy').format(_dates!.start)} – ${DateFormat('dd MMM yyyy').format(_dates!.end)}')),
                                if (_dates != null)
                                  TextButton(
                                      onPressed: () =>
                                          setState(() => _dates = null),
                                      child: const Text('Clear dates')),
                              ])
                        ])),
                Expanded(
                    child: history.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                            child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                          'Could not load DSR history: $error'),
                                      TextButton(
                                          onPressed: _refresh,
                                          child: const Text('Retry'))
                                    ]))),
                        data: (snapshot) {
                          final filtered = snapshot.entries.where((e) {
                            final d = e.report.date;
                            final day = DateTime(d.year, d.month, d.day);
                            return (_site == 'all' ||
                                    e.report.siteId == _site) &&
                                (_dates == null ||
                                    (!day.isBefore(_dates!.start) &&
                                        !day.isAfter(_dates!.end))) &&
                                switch (_status) {
                                  'approved' => e.approved,
                                  'reviewed' => e.reviewed,
                                  'pending' => !e.reviewed,
                                  'rejected' => e.rejected,
                                  _ => true
                                };
                          }).toList();
                          return RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    for (final warning in snapshot.warnings)
                                      Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(warning)),
                                    Text('${filtered.length} report(s)'),
                                    if (filtered.isEmpty)
                                      const Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text(
                                              'No DSRs match these filters.')),
                                    for (final entry in filtered)
                                      Card(
                                          child: ListTile(
                                              isThreeLine: true,
                                              title: Text(
                                                  '${names[entry.report.siteId] ?? entry.report.siteName ?? entry.report.siteId} • ${DateFormat('dd MMM yyyy').format(entry.report.date)}'),
                                              subtitle: Text(
                                                  '${entry.status}\nSubmitted by ${entry.report.submittedBy ?? 'Not recorded'}'),
                                              trailing: const Icon(
                                                  Icons.chevron_right),
                                              onTap: () => Navigator.of(context)
                                                  .push(MaterialPageRoute(
                                                      builder: (_) => DsrHistoryDetailsScreen(
                                                          entry: entry,
                                                          siteName: names[entry
                                                                  .report
                                                                  .siteId] ??
                                                              entry.report
                                                                  .siteName ??
                                                              entry.report
                                                                  .siteId))))),
                                  ]));
                        }))
              ]))),
    );
  }
}

class DsrHistoryDetailsScreen extends ConsumerWidget {
  final DsrHistoryEntry entry;
  final String siteName;
  const DsrHistoryDetailsScreen(
      {super.key, required this.entry, required this.siteName});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canViewDsrHistory(ref.watch(authProvider).user?.role)) {
      return const Scaffold(
          body: Center(
              child:
                  Text('Management sign-in is required to view DSR history.')));
    }
    final r = entry.report;
    String stamp(DateTime d) =>
        DateFormat('dd MMM yyyy, hh:mm:ss a').format(d.toLocal());
    Widget field(String label, Object? value) => value == null ||
            value.toString().trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(value is List
                  ? value.join('\n')
                  : value is Map
                      ? const JsonEncoder.withIndent('  ').convert(value)
                      : value.toString())
            ]));
    final reviews = entry.reviewState.entries
        .where((e) =>
            e.value is Map &&
            (e.key != 'final' ||
                !entry.reviewState.entries.any((other) =>
                    other.key != 'final' &&
                    jsonEncode(other.value) == jsonEncode(e.value))))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('DSR Details')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          field('Site', siteName),
                          field('Report date',
                              DateFormat('dd MMM yyyy').format(r.date)),
                          field('Review status', entry.status),
                          field('Submitted by', r.submittedBy),
                          field(
                              'Submitted at',
                              DateTime.tryParse(
                                          '${entry.submittedData['created_at']}') ==
                                      null
                                  ? 'Not recorded'
                                  : stamp(DateTime.parse(
                                      '${entry.submittedData['created_at']}'))),
                          field(
                              'Last updated',
                              DateTime.tryParse(
                                          '${entry.submittedData['updated_at']}') ==
                                      null
                                  ? 'Not recorded'
                                  : stamp(DateTime.parse(
                                      '${entry.submittedData['updated_at']}'))),
                          field('Work progress notes', r.notes),
                          field('Voice transcript', r.rawTranscript),
                          if (r.workDone.isNotEmpty)
                            field('Work completed', r.workDone),
                          if (r.tomorrowPlan.isNotEmpty)
                            field('Tomorrow’s plan', r.tomorrowPlan),
                          field('Labour / manpower details', r.manpowerDetails),
                          for (final item in entry.submittedData.entries.where(
                              (e) =>
                                  e.key != 'manpower_details' &&
                                  RegExp(r'labou?r|manpower',
                                          caseSensitive: false)
                                      .hasMatch(e.key)))
                            field(item.key.replaceAll('_', ' '), item.value),
                          field('Materials used', r.materialsUsed),
                          field('Original remarks and approval labels',
                              r.remarks),
                          if (r.aiSummary.isNotEmpty)
                            field('Submitted summary', r.aiSummary),
                          if (r.photoUrls.isNotEmpty)
                            PhotoThumbnailStrip(
                                photoUrls: r.photoUrls,
                                title: 'Progress photos • Tap to zoom'),
                          if (r.audioUrl != null && r.audioUrl!.isNotEmpty)
                            OutlinedButton.icon(
                                onPressed: () async {
                                  final uri = Uri.tryParse(r.audioUrl!);
                                  if (uri != null) {
                                    try {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Could not open the original voice recording.')));
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text(
                                    'Open original voice recording')),
                          const SizedBox(height: 16),
                          Text('Review history',
                              style: Theme.of(context).textTheme.titleLarge),
                          if (reviews.isEmpty)
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                    'Detailed review timestamps were not recorded for this legacy report. Existing approval labels are preserved above.')),
                          for (final review in reviews) ...[
                            const Divider(),
                            field(
                                'Checkpoint',
                                switch (review.key) {
                                  'project_head' => 'Project Head',
                                  'accounts' => 'Accounts',
                                  'admin' => 'Admin',
                                  'final' => 'Final decision',
                                  _ => review.key
                                }),
                            field('Decision', review.value['decision']),
                            field('Reviewed by', review.value['reviewed_by']),
                            field(
                                'Reviewed at',
                                DateTime.tryParse(
                                            '${review.value['reviewed_at']}')
                                        is DateTime
                                    ? stamp(DateTime.parse(
                                        '${review.value['reviewed_at']}'))
                                    : 'Not recorded'),
                            field('Review note', review.value['note']),
                          ],
                          field('Report ID', r.id),
                        ])))));
  }
}
