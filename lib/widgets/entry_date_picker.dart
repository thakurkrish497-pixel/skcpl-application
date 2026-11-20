import 'package:flutter/material.dart';
import '../services/entry_date_policy.dart';
export '../services/entry_date_policy.dart';

/// The same ceiling applies to calendar selection and Flutter's typed date input.
Future<DateTime?> showEntryDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  TransitionBuilder? builder,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
}) {
  final clock = DateTime.now();
  final today = EntryDatePolicy.today(now: clock);
  final initial = EntryDatePolicy.pickerInitial(initialDate, now: clock);
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: initial.isBefore(firstDate) ? initial : firstDate,
    lastDate: today,
    currentDate: today,
    initialDatePickerMode: initialDatePickerMode,
    builder: builder,
    errorInvalidText: EntryDatePolicy.message,
  );
}

Future<DateTimeRange?> showEntryDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  DateTimeRange? initialDateRange,
  TransitionBuilder? builder,
}) {
  final clock = DateTime.now();
  final today = EntryDatePolicy.today(now: clock);
  final range = initialDateRange == null
      ? null
      : DateTimeRange(
          start:
              EntryDatePolicy.pickerInitial(initialDateRange.start, now: clock),
          end: EntryDatePolicy.pickerInitial(initialDateRange.end, now: clock),
        );
  return showDateRangePicker(
    context: context,
    firstDate: range != null && range.start.isBefore(firstDate)
        ? range.start
        : firstDate,
    lastDate: today,
    currentDate: today,
    initialDateRange: range,
    builder: builder,
    errorInvalidText: EntryDatePolicy.message,
  );
}
