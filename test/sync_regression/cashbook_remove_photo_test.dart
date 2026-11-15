import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/widgets/photo_picker.dart';
import 'cashbook_form_test_support.dart';

void main() {
  testWidgets(
      'A saved cash entry can drop a refused receipt and retry the same UUID',
      (tester) async {
    final auth = FixedAuth(UserRole.worker);
    final site = auth.state.activeSite!.id;
    auth.dispose();
    final id = submissionId(null);
    final draft = CashEntryDraft(
        id: id,
        mode: CashEntryMode.expense,
        expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
        expenseTypeName: 'General',
        amount: 150,
        remarks: 'Transport',
        date: DateTime.now(),
        photos: [
          PickedPhoto(bytes: Uint8List.fromList([1, 2, 3]), name: 'receipt.jpg')
        ]);
    final tx = CashTransactionModel(
        id: 'offline_cash_$id',
        siteId: site,
        date: draft.date,
        expenseTypeId: draft.expenseTypeId!,
        expenseAmount: 150,
        cashInHand: -150,
        pendingPhotos: [
          PendingPhoto(bytes: draft.photos.single.bytes, name: 'receipt.jpg')
        ]);
    final draftKey = 'staged_CashEntryDraft_v1_${site}_site-session';
    SharedPreferences.setMockInitialValues({
      draftKey: jsonEncode({
        'entries': [draft.toLocalJson()]
      }),
      'offline_cash_queue_v1': [
        jsonEncode({
          ...tx.toJson(),
          'sync_version': 2,
          'sync_paused': true,
          'sync_error': 'Storage upload refused (403)'
        })
      ],
    });
    final submitted = <CashTransactionModel>[];
    final service = FormCash()
      ..onSubmit = (entry) async {
        expect(entry.pendingPhotos, isEmpty);
        submitted.add(entry);
        return entry;
      };
    await showForm(tester, service);
    final remove = find.byTooltip('Remove attached photos; keep entry');
    await tester.scrollUntilVisible(remove, 250,
        scrollable: find.byType(Scrollable).first);
    await settleForm(tester);
    await Scrollable.ensureVisible(tester.element(remove), alignment: 0.5);
    await tester.tap(remove);
    await settleForm(tester);
    final saved = await DraftStore.load(draftKey);
    expect((saved!['entries'] as List).single['id'], id);
    expect((saved['entries'] as List).single['photos'], isEmpty);
    expect((saved['entries'] as List).single['amount'], 150);
    await tapAction(tester, 'Submit Batch (1)');
    expect(submitted, hasLength(1));
    expect(submissionId(submitted.single.id), id);
    expect(submitted.single.expenseAmount, 150);
    expect(submitted.single.cashInHand, -150);
    expect(await OfflineService.getQueuedCashTransactions(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
