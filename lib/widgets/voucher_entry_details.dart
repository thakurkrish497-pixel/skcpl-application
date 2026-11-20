import 'rejected_entry_actions.dart';
import '../models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/site_staff_model.dart';
import '../providers/auth_provider.dart';
import '../providers/site_provider.dart';
import '../providers/site_staff_provider.dart';
import 'photo_thumbnail_strip.dart';

/// Minimal, read-only lookup shared by management presentation. No voucher writes.
final voucherUserNamesProvider =
    FutureProvider<Map<String, ({String name, String role})>>((ref) async {
  final actor =
      ref.watch(authProvider.select((a) => (a.user?.id, a.user?.role)));
  if (![UserRole.admin, UserRole.projectHead, UserRole.accounts]
      .contains(actor.$2)) {
    return {};
  }
  final client = ref.read(supabaseClientProvider);
  final result = <String, ({String name, String role})>{};
  String? cursor;
  while (true) {
    var q = client.from('users').select('id,full_name,email,role');
    if (cursor != null) q = q.gt('id', cursor);
    final rows =
        List<Map<String, dynamic>>.from(await q.order('id').limit(200));
    for (final row in rows) {
      final role = switch (row['role']) {
        'admin' => 'Admin',
        'project_head' => 'Project Head',
        'accounts' => 'Accounts',
        'worker' => 'Site Worker',
        _ => 'Role not recorded'
      };
      final name = (row['full_name']?.toString().trim().isNotEmpty ?? false)
          ? row['full_name'].toString().trim()
          : 'Name not recorded (account: ${row['email'] ?? row['id']})';
      result[row['id'].toString()] = (name: name, role: role);
    }
    if (rows.length < 200) break;
    final next = rows.last['id'].toString();
    if (next == cursor) throw StateError('Submitter lookup did not advance');
    cursor = next;
  }
  return result;
});

String voucherSiteLabel(
    String id, String? recorded, Map<String, String> sites) {
  final current = sites[id]?.trim();
  if (current != null && current.isNotEmpty) return current;
  if (recorded != null && recorded.trim().isNotEmpty) return recorded.trim();
  return 'Site name unavailable • ID: $id';
}

String voucherSubmitterLabel(
    {String? snapshot,
    String? reference,
    Map<String, ({String name, String role})> users = const {},
    List<SiteStaffModel> staff = const [],
    String? siteId}) {
  final label = snapshot?.trim();
  if (label != null && label.isNotEmpty) {
    return RegExp(r'\([^()]+\)\s*$').hasMatch(label)
        ? label
        : '$label (role not recorded)';
  }
  final id = reference?.trim();
  if (id == null || id.isEmpty) return 'Name and role not recorded';
  final people =
      staff.where((s) => s.id == id && (siteId == null || s.siteId == siteId));
  if (people.isNotEmpty) {
    final s = people.first;
    return '${s.name} (${s.designation?.trim().isNotEmpty == true ? s.designation : s.role.displayName}) • linked profile';
  }
  final user = users[id];
  if (user != null) return '${user.name} (${user.role}) • linked profile';
  if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
      .hasMatch(id)) {
    return RegExp(r'\([^()]+\)\s*$').hasMatch(id)
        ? id
        : '$id (role not recorded)';
  }
  return 'Name and role unavailable • recorded ID: $id';
}

class VoucherEntryIdentity extends ConsumerWidget {
  final CashTransactionModel? cash;
  final StockTransactionModel? stock;
  const VoucherEntryIdentity({super.key, this.cash, this.stock})
      : assert((cash != null) != (stock != null));
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final siteId = cash?.siteId ?? stock!.siteId;
    final management = [UserRole.admin, UserRole.projectHead, UserRole.accounts]
        .contains(ref.watch(authProvider).user?.role);
    final sites = ref
            .watch(management ? allSitesProvider : activeSitesProvider)
            .valueOrNull ??
        [];
    final names = {for (final site in sites) site.id: site.name};
    final saved = cash?.submitterName ?? stock?.submitterName;
    final id = cash?.submittedBy ?? stock?.submittedBy;
    final users = (management && saved?.trim().isNotEmpty != true && id != null)
        ? ref.watch(voucherUserNamesProvider).valueOrNull
        : null;
    final staff = (management && saved?.trim().isNotEmpty != true && id != null)
        ? ref.watch(allStaffProvider).valueOrNull
        : null;
    final name =
        voucherSiteLabel(siteId, cash?.siteName ?? stock?.siteName, names);
    final who = voucherSubmitterLabel(
        snapshot: saved,
        reference: id,
        siteId: siteId,
        users: users ?? {},
        staff: staff ?? []);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Site: $name', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Submitted by: $who', style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }
}

/// One consistent parameter layout for review queues, history and detail views.
/// Approval actions belong to the existing dashboards, never this widget.
class VoucherEntryDetails extends StatelessWidget {
  final CashTransactionModel? cash;
  final StockTransactionModel? stock;
  const VoucherEntryDetails({super.key, this.cash, this.stock})
      : assert((cash != null) != (stock != null));
  @override
  Widget build(BuildContext context) {
    final c = cash;
    final s = stock;
    final money =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    String amount(double value) =>
        value.isFinite ? money.format(value) : 'Not recorded correctly';
    final date = c?.date ?? s!.date;
    final remarks = c?.remarks ?? s?.remarks;
    final bill = c?.billNo ??
        s?.billNo ??
        RegExp(r'\[(?:Challan|Voucher|Invoice):\s*([^\]]+)\]',
                caseSensitive: false)
            .firstMatch(remarks ?? '')
            ?.group(1);
    final batch = c?.batchId ?? s?.batchId;
    final status = c?.status ?? s!.status;
    final age =
        DateTime.now().difference(c?.createdAt ?? s?.createdAt ?? date).inHours;
    final photos = c?.photoUrls ?? s!.photoUrls;
    final pending = c?.pendingPhotos ?? s!.pendingPhotos;
    final fields = <String, String>{
      'Entry type': c != null
          ? (c.amountReceived > 0 && c.expenseAmount == 0
              ? 'Cash received / Top-up'
              : c.amountReceived > 0
                  ? 'Cash received and expense'
                  : 'Cash expense')
          : (s!.type == TransactionType.inbound
              ? 'Stock IN / Delivery'
              : 'Stock OUT / Usage'),
      'Entry date': DateFormat('dd MMM yyyy').format(date),
      if (c != null) ...{
        'Cash received': amount(c.amountReceived),
        'Expense amount': amount(c.expenseAmount),
        'Recorded cash in hand': amount(c.cashInHand),
        'Party / Source': c.partyName ??
            (c.amountReceived > 0 ? c.customExpenseType : null) ??
            'Not recorded',
      },
      if (s != null) ...{
        'Quantity': '${s.quantity} ${s.displayMetricUnitName}',
        'Rate': s.rate == null ? 'Not recorded' : amount(s.rate!),
        'SGST': '${s.sgst}%',
        'IGST': '${s.igst}%',
        s.finalAmount == null ? 'Calculated total' : 'Recorded total':
            amount(s.finalAmount ?? s.calculatedFinalAmount),
        'Vendor / Party': s.displayVendorName == 'None'
            ? 'Not recorded'
            : s.displayVendorName,
      },
      'Bill / Challan / Voucher':
          bill?.trim().isNotEmpty == true ? bill! : 'Not recorded',
      'Remarks': c?.cleanRemarks ?? s?.cleanRemarks ?? 'Not recorded',
      if (batch != null) 'Batch ID': batch,
      if (c?.supervisorReviewNote ?? s?.supervisorReviewNote
          case final String note)
        'Project Head review': note,
      if (c?.rejectionNote ?? s?.rejectionNote case final String note)
        'Rejection reason': note,
      if (c?.createdAt ?? s?.createdAt case final DateTime at)
        'Submitted at': DateFormat('dd MMM yyyy, hh:mm a').format(at.toLocal()),
      if (c?.reviewedAt ?? s?.reviewedAt case final DateTime at)
        'Reviewed at': DateFormat('dd MMM yyyy, hh:mm a').format(at.toLocal()),
      if (c?.approvedAt ?? s?.approvedAt case final DateTime at)
        'Approved at': DateFormat('dd MMM yyyy, hh:mm a').format(at.toLocal()),
      if (c?.id ?? s?.id case final String id) 'Entry ID': id,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VoucherEntryIdentity(cash: c, stock: s),
      const SizedBox(height: 10),
      Text(
          c?.displayExpenseTypeName ??
              '${s!.type == TransactionType.inbound ? 'Stock IN' : 'Stock OUT'}: ${s.displayProductName}',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (age >= 36 &&
          (status == TransactionStatus.pendingAccounts ||
              status == TransactionStatus.pendingAdmin))
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Pending for ${age}h',
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 600 ? 1 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(spacing: 16, runSpacing: 6, children: [
          for (final item in fields.entries)
            SizedBox(width: width, child: Text('${item.key}: ${item.value}'))
        ]);
      }),
      RejectedEntryActions(cash: cash, stock: stock),
      if (photos.isNotEmpty)
        PhotoThumbnailStrip(
            photoUrls: photos, title: 'Entry photos • Tap to zoom'),
      if (pending.isNotEmpty) ...[
        Text('${pending.length} photo(s) saved locally, waiting for upload'),
        SizedBox(
            height: 70,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Image.memory(pending[i].bytes,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined)))),
      ],
    ]);
  }
}
