import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/site_staff_model.dart';

void main() {
  group('Site Staff Permissions & Module Access Verification', () {
    test('Staff without stock module has hasModule(StaffModule.stock) == false', () {
      final staff = SiteStaffModel(
        id: 'staff-daksh-1',
        siteId: 'site-hatpipliya',
        name: 'Daksh',
        role: SiteStaffRole.worker,
        modules: const [
          StaffModule.attendance,
          StaffModule.cashbook,
          StaffModule.report,
        ],
        pin: '123456',
        createdAt: DateTime.now(),
      );

      expect(staff.hasModule(StaffModule.stock), isFalse);
      expect(staff.hasModule(StaffModule.attendance), isTrue);
      expect(staff.hasModule(StaffModule.cashbook), isTrue);
      expect(staff.hasModule(StaffModule.report), isTrue);
    });

    test('Inactive staff has hasModule == false regardless of module list', () {
      final staff = SiteStaffModel(
        id: 'staff-inactive-1',
        siteId: 'site-hatpipliya',
        name: 'Inactive Worker',
        role: SiteStaffRole.worker,
        modules: const [StaffModule.stock],
        isActive: false,
        pin: '1234',
        createdAt: DateTime.now(),
      );

      expect(staff.hasModule(StaffModule.stock), isFalse);
    });

    test('SiteStaffModel.fromJson preserves empty modules without injecting stock', () {
      final json = {
        'id': 'staff-nomodules-1',
        'site_id': 'site-1',
        'name': 'No Modules Employee',
        'role': 'worker',
        'modules': <String>[],
        'pin': '1234',
        'is_active': true,
      };

      final staff = SiteStaffModel.fromJson(json);
      expect(staff.modules, isEmpty);
      expect(staff.hasModule(StaffModule.stock), isFalse);
      expect(staff.hasModule(StaffModule.attendance), isFalse);
    });

    test('SiteStaffModel.fromJson correctly parses multiple modules without stock', () {
      final json = {
        'id': 'd8116fc6-4b30-43c0-98d7-d9058c44abe9',
        'site_id': '25f0ef60-ddb2-43fd-b82f-ead3c17a8d5c',
        'name': 'daksh',
        'role': 'worker',
        'modules': ['attendance', 'cashbook', 'report'],
        'pin': '123456',
        'is_active': true,
      };

      final staff = SiteStaffModel.fromJson(json);
      expect(staff.name, 'daksh');
      expect(staff.hasModule(StaffModule.stock), isFalse);
      expect(staff.hasModule(StaffModule.cashbook), isTrue);
      expect(staff.hasModule(StaffModule.attendance), isTrue);
      expect(staff.hasModule(StaffModule.report), isTrue);
    });
  });
}
