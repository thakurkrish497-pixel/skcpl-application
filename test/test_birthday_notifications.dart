import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/providers/birthday_provider.dart';

void main() {
  group('Employee Birthday Detection & Announcement Bar Tests', () {
    test('getBirthdayBarTitle formats message correctly for 0, 1, 2, and multiple birthdays', () {
      // 0 birthdays
      expect(getBirthdayBarTitle([]), equals('SKCPL GROUP'));

      // 1 birthday
      final staff1 = SiteStaffModel(
        id: 'staff-1',
        siteId: 'site-1',
        name: 'Daksh Sharma',
        role: SiteStaffRole.worker,
        pin: '1234',
        createdAt: DateTime(2025, 1, 1),
      );
      expect(
        getBirthdayBarTitle([staff1]),
        equals('🎉 Happy Birthday Daksh Sharma! 🎂'),
      );

      // 2 birthdays
      final staff2 = SiteStaffModel(
        id: 'staff-2',
        siteId: 'site-2',
        name: 'Amit Patel',
        role: SiteStaffRole.worker,
        pin: '5678',
        createdAt: DateTime(2025, 1, 1),
      );
      expect(
        getBirthdayBarTitle([staff1, staff2]),
        equals('🎉 Happy Birthday Daksh Sharma & Amit Patel! 🎂'),
      );

      // 3 birthdays
      final staff3 = SiteStaffModel(
        id: 'staff-3',
        siteId: 'site-1',
        name: 'Rohan Verma',
        role: SiteStaffRole.worker,
        pin: '9999',
        createdAt: DateTime(2025, 1, 1),
      );
      expect(
        getBirthdayBarTitle([staff1, staff2, staff3]),
        equals('🎉 Happy Birthday Daksh Sharma, Amit Patel & 1 more! 🎂'),
      );
    });

    test('Identifies birthdays matching today and ignores inactive or non-birthday staff', () {
      final now = DateTime.now();

      final birthdayToday1 = SiteStaffModel(
        id: 'bday-1',
        siteId: 'site-hatpipliya',
        name: 'Daksh Sharma',
        role: SiteStaffRole.worker,
        pin: '1111',
        createdAt: DateTime(2024, 1, 1),
        dateOfBirth: DateTime(1995, now.month, now.day),
        isActive: true,
      );

      final birthdayToday2 = SiteStaffModel(
        id: 'bday-2',
        siteId: 'site-indore',
        name: 'Priya Joshi',
        role: SiteStaffRole.worker,
        pin: '2222',
        createdAt: DateTime(2024, 1, 1),
        dateOfBirth: DateTime(1998, now.month, now.day),
        isActive: true,
      );

      final birthdayOtherDay = SiteStaffModel(
        id: 'bday-3',
        siteId: 'site-bhopal',
        name: 'Vikram Singh',
        role: SiteStaffRole.worker,
        pin: '3333',
        createdAt: DateTime(2024, 1, 1),
        dateOfBirth: DateTime(1990, now.month == 12 ? 1 : now.month + 1, now.day == 28 ? 1 : now.day + 1),
        isActive: true,
      );

      final inactiveToday = SiteStaffModel(
        id: 'bday-4',
        siteId: 'site-hatpipliya',
        name: 'Inactive Ex-Employee',
        role: SiteStaffRole.worker,
        pin: '4444',
        createdAt: DateTime(2024, 1, 1),
        dateOfBirth: DateTime(1992, now.month, now.day),
        isActive: false, // inactive
      );

      final noDob = SiteStaffModel(
        id: 'bday-5',
        siteId: 'site-indore',
        name: 'No DOB Employee',
        role: SiteStaffRole.worker,
        pin: '5555',
        createdAt: DateTime(2024, 1, 1),
        dateOfBirth: null,
        isActive: true,
      );

      final List<SiteStaffModel> allStaff = [
        birthdayToday1,
        birthdayToday2,
        birthdayOtherDay,
        inactiveToday,
        noDob,
      ];

      // Simulate filter logic from provider
      final todayBirthdays = allStaff.where((staff) {
        if (!staff.isActive) return false;
        final dob = staff.dateOfBirth;
        if (dob == null) return false;
        return dob.month == now.month && dob.day == now.day;
      }).toList();

      expect(todayBirthdays.length, equals(2));
      expect(todayBirthdays.map((s) => s.id), containsAll(['bday-1', 'bday-2']));
      expect(todayBirthdays.map((s) => s.id), isNot(contains('bday-3')));
      expect(todayBirthdays.map((s) => s.id), isNot(contains('bday-4')));
      expect(todayBirthdays.map((s) => s.id), isNot(contains('bday-5')));

      // Verify title shows both people
      expect(
        getBirthdayBarTitle(todayBirthdays),
        equals('🎉 Happy Birthday Daksh Sharma & Priya Joshi! 🎂'),
      );
    });
  });
}
