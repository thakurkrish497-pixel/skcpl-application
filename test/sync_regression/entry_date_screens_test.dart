import 'cashbook_form_test_support.dart';
import 'package:skcpl_app/widgets/entry_date_picker.dart';

void main() {
  for (final role in UserRole.values) {
    testWidgets('Cashbook ${role.name} date picker stops at today',
        (tester) async {
      final service = FormCash();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => FixedAuth(role)),
            cashServiceProvider.overrideWithValue(service)
          ],
          child: MaterialApp(
              theme: AppTheme.darkTheme, home: const ExpenseFormScreen())));
      await settleForm(tester);
      final date = find.text('Date (As per Cashbook)');
      await tester.ensureVisible(date);
      await tester.tap(date);
      await settleForm(tester);
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate, EntryDatePolicy.today());
      expect(picker.initialDate, EntryDatePolicy.today());
      expect(tester.takeException(), isNull);
    });
  }
}
