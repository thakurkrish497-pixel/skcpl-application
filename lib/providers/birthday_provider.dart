import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site_staff_model.dart';
import '../services/notification_service.dart';
import 'site_staff_provider.dart';

/// Provider that computes which active staff members are celebrating a birthday today.
/// When birthdays are detected, automatically fires desktop & phone notifications
/// for each celebrating staff member (so everyone in the app gets notified for each person).
final todayBirthdayStaffProvider = Provider<List<SiteStaffModel>>((ref) {
  final allStaffAsync = ref.watch(allStaffProvider);

  return allStaffAsync.when(
    data: (staffList) {
      final now = DateTime.now();
      final birthdays = staffList.where((staff) {
        if (!staff.isActive) return false;
        final dob = staff.dateOfBirth;
        if (dob == null) return false;
        return dob.month == now.month && dob.day == now.day;
      }).toList();

      // Trigger notification for each birthday person (rate-limited to 1/day/person)
      if (birthdays.isNotEmpty) {
        for (final staff in birthdays) {
          NotificationService.showBirthdayNotification(
            staffId: staff.id,
            staffName: staff.name,
          );
        }
      }

      return birthdays;
    },
    loading: () => const [],
    error: (_, __) => const [],
  );
});

/// Formats the announcement bar message per user requirements:
/// - If no birthdays today: "SKCPL GROUP"
/// - If 1 birthday: "🎉 Happy Birthday {name}! 🎂"
/// - If 2 birthdays: "🎉 Happy Birthday {name1} & {name2}! 🎂"
/// - If 3+ birthdays: "🎉 Happy Birthday {name1}, {name2} & {n} more! 🎂"
String getBirthdayBarTitle(List<SiteStaffModel> birthdays) {
  if (birthdays.isEmpty) {
    return 'SKCPL GROUP';
  } else if (birthdays.length == 1) {
    return '🎉 Happy Birthday ${birthdays[0].name}! 🎂';
  } else if (birthdays.length == 2) {
    return '🎉 Happy Birthday ${birthdays[0].name} & ${birthdays[1].name}! 🎂';
  } else {
    final remaining = birthdays.length - 2;
    return '🎉 Happy Birthday ${birthdays[0].name}, ${birthdays[1].name} & $remaining more! 🎂';
  }
}
