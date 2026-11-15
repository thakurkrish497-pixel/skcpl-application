import 'cashbook_form_test_support.dart';

void main() {
  testWidgets('Cash failure keeps original server reason and durable entry',
      (tester) async {
    final service = FormCash()
      ..onSubmit = (tx) async {
        throw const PostgrestException(
            message: 'cash insert denied by site policy', code: '42501');
      };
    await showForm(tester, service);
    await fillExpense(tester);
    await tapAction(tester, 'Submit Entry');
    expect(find.textContaining('cash insert denied by site policy'),
        findsOneWidget);
    expect(find.text('Submission failed'), findsNothing);
    expect(find.textContaining('Staged Batch (1 item)'), findsOneWidget);
    expect(await OfflineService.getQueuedCashTransactions(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
