import 'cashbook_form_test_support.dart';

void main() {
  testWidgets('Cash expense stages and submits without any receipt photo',
      (tester) async {
    final submitted = <CashTransactionModel>[];
    final service = FormCash()
      ..onSubmit = (tx) async {
        submitted.add(tx);
        return tx;
      };
    await showForm(tester, service);
    await fillExpense(tester);
    await tapAction(tester, '+ Add Item');
    expect(find.textContaining('Staged Batch (1 item)'), findsOneWidget);
    await tapAction(tester, 'Submit Batch (1)');
    expect(submitted, hasLength(1));
    expect(submitted.single.pendingPhotos, isEmpty);
    expect(submitted.single.photoUrls, isEmpty);
    expect(submitted.single.expenseAmount, 100);
    expect(find.textContaining('1 uploaded;'), findsOneWidget);
    expect(await OfflineService.getQueuedCashTransactions(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
