/// Old Site-PIN attendance stored local India wall time without an offset.
/// Interpret it consistently on every host; never rewrite the source row.
DateTime parseAttendanceInstant(dynamic value) {
  if (value is DateTime) return value.toLocal();
  final text = value.toString();
  final explicitZone =
      RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text);
  return DateTime.parse(explicitZone ? text : '$text+05:30').toLocal();
}
