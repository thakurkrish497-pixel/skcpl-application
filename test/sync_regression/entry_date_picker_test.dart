import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/widgets/entry_date_picker.dart';

void main() {
  testWidgets(
      'Calendar caps at India today and clamps restored future selection without modifying original',
      (tester) async {
    final restored = EntryDatePolicy.today().add(const Duration(days: 3));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showEntryDatePicker(
                        context: context,
                        initialDate: restored,
                        firstDate: DateTime(2020)),
                    child: const Text('Date'))))));
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(dialog.lastDate, EntryDatePolicy.today());
    expect(dialog.initialDate, EntryDatePolicy.today());
    expect(restored, EntryDatePolicy.today().add(const Duration(days: 3)));
  });
  testWidgets('Typed future date cannot be confirmed', (tester) async {
    DateTime? selected;
    String input = '';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      input = MaterialLocalizations.of(context)
                          .formatCompactDate(EntryDatePolicy.today()
                              .add(const Duration(days: 1)));
                      selected = await showEntryDatePicker(
                          context: context,
                          initialDate: EntryDatePolicy.today(),
                          firstDate: DateTime(2020));
                    },
                    child: const Text('Date'))))));
    await tester.tap(find.text('Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), input);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text(EntryDatePolicy.message), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
  testWidgets('Range picker caps end date at today even for old future filters',
      (tester) async {
    final today = EntryDatePolicy.today();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showEntryDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        initialDateRange: DateTimeRange(
                            start: today,
                            end: today.add(const Duration(days: 5)))),
                    child: const Text('Dates'))))));
    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();
    final dialog = tester
        .widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
    expect(dialog.lastDate, today);
    expect(dialog.initialDateRange!.end, today);
  });
}
