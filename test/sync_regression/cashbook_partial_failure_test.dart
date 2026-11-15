import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'cashbook_form_test_support.dart';

void main() {
  testWidgets(
      'Partial cash batch retains first failure despite a later successful upload',
      (tester) async {
    final auth = FixedAuth(UserRole.worker);
    final siteId = auth.state.activeSite!.id;
    auth.dispose();
    final entries = [
      for (var i = 0; i < 2; i++)
        CashEntryDraft(
            id: submissionId(null),
            mode: CashEntryMode.expense,
            expenseTypeId: 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f',
            expenseTypeName: 'General',
            amount: 100,
            remarks: 'Entry $i',
            date: DateTime.now())
    ];
    final key = 'staged_CashEntryDraft_v1_${siteId}_site-session';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({'entries': entries.map((e) => e.toLocalJson()).toList()})
    });
    final service = FormCash()
      ..onSubmit = (tx) async {
        if (submissionId(tx.id) == entries.first.id) {
          throw const PostgrestException(
              message: 'first voucher denied', code: '42501');
        }
        return tx;
      };
    await showForm(tester, service);
    await tapAction(tester, 'Submit Batch (2)');
    expect(find.textContaining('1 uploaded;'), findsOneWidget);
    expect(find.textContaining('first voucher denied'), findsOneWidget);
    expect(find.textContaining('Staged Batch (1 item)'), findsOneWidget);
    final saved = await DraftStore.load(key);
    expect((saved!['entries'] as List).single['id'], entries.first.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
