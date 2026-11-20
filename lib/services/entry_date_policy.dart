/// Calendar dates are stored as entered; the business-day ceiling uses India time.
/// Reading old records and drafts never invokes validation or rewrites their dates.
class EntryDatePolicy {
  static const message =
      'Future dates are not allowed. Choose today or an earlier date (India time).';

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime today({DateTime? now}) {
    final india = (now ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    return DateTime(india.year, india.month, india.day);
  }

  static bool isFuture(DateTime value, {DateTime? now}) =>
      day(value).isAfter(today(now: now));

  static DateTime pickerInitial(DateTime value, {DateTime? now}) =>
      isFuture(value, now: now) ? today(now: now) : day(value);

  static void requireNotFuture(DateTime value, {DateTime? now}) {
    if (isFuture(value, now: now)) throw ArgumentError(message);
  }

  /// Use for timestamp fields, which represent instants rather than date labels.
  static void requireNotFutureInstant(DateTime value, {DateTime? now}) {
    final india = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    requireNotFuture(DateTime(india.year, india.month, india.day), now: now);
  }

  static void requireDateValue(dynamic value, {DateTime? now}) {
    if (value is DateTime) {
      requireNotFuture(value, now: now);
      return;
    }
    final text = value?.toString() ?? '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T)').firstMatch(text);
    if (match == null || DateTime.tryParse(text) == null) {
      throw ArgumentError('Enter a valid date.');
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final dayOfMonth = int.parse(match[3]!);
    final date = DateTime(year, month, dayOfMonth);
    if (date.year != year || date.month != month || date.day != dayOfMonth) {
      throw ArgumentError('Enter a valid date.');
    }
    requireNotFuture(date, now: now);
  }
}
