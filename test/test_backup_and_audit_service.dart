import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skcpl_app/services/audit_service.dart';
import 'package:skcpl_app/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Layer 2 & 4: BackupService & AuditService Data Protection Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AuditService captures deleted record into Emergency Vault', () async {
      final sampleRecord = {
        'id': 'test-cash-123',
        'remarks': 'Cement transport',
        'expense_amount': 7500.0,
        'site_id': 'site-nissarpur',
      };

      await AuditService.captureDeletedRecord(
        entity: 'cash',
        entityId: 'test-cash-123',
        recordData: sampleRecord,
        userRole: 'Admin',
        userName: 'Director',
        reason: 'Duplicate voucher cleanup',
      );

      final vaulted = await AuditService.getArchivedVaultRecords();
      expect(vaulted.length, 1);
      expect(vaulted.first['entity'], 'cash');
      expect(vaulted.first['entity_id'], 'test-cash-123');
      expect(vaulted.first['user_role'], 'Admin');
      expect(vaulted.first['user_name'], 'Director');
      expect(vaulted.first['data']['remarks'], 'Cement transport');
    });

    test('AuditService purges single vault entry and clears vault cleanly', () async {
      await AuditService.captureDeletedRecord(
        entity: 'stock',
        entityId: 'stock-1',
        recordData: {'remarks': 'Steel TMT bars'},
      );
      await AuditService.captureDeletedRecord(
        entity: 'stock',
        entityId: 'stock-2',
        recordData: {'remarks': 'Binding wire'},
      );

      var vaulted = await AuditService.getArchivedVaultRecords();
      expect(vaulted.length, 2);

      final firstVaultId = vaulted.first['vault_id'] as String;
      await AuditService.purgeVaultEntry(firstVaultId);

      vaulted = await AuditService.getArchivedVaultRecords();
      expect(vaulted.length, 1);

      await AuditService.clearVault();
      vaulted = await AuditService.getArchivedVaultRecords();
      expect(vaulted, isEmpty);
    });

    test('BackupService validates JSON backup payload correctly', () {
      final backupPayload = {
        'metadata': {
          'app': 'SKCPL Construction Management',
          'exported_at': '2026-10-26T12:00:00Z',
          'counts': {
            'sites': 3,
            'site_staff': 15,
            'cash_transactions': 120,
            'stock_transactions': 85,
            'attendance': 340,
            'daily_site_reports': 42,
          },
        },
        'sites': [
          {'id': '1', 'name': 'Nissarpur'},
          {'id': '2', 'name': 'Hatpipliya'},
          {'id': '3', 'name': 'Pipalrawa'},
        ],
        'site_staff': List.generate(15, (i) => {'id': 'staff-$i', 'name': 'Worker $i'}),
        'cash_transactions': List.generate(120, (i) => {'id': 'cash-$i', 'amount': 1000}),
        'stock_transactions': List.generate(85, (i) => {'id': 'stock-$i', 'qty': 50}),
        'attendance': List.generate(340, (i) => {'id': 'att-$i'}),
        'daily_site_reports': List.generate(42, (i) => {'id': 'dsr-$i'}),
      };

      final jsonStr = jsonEncode(backupPayload);
      final validation = BackupService.validateBackup(jsonStr);

      expect(validation['isValid'], isTrue);
      expect(validation['sitesCount'], 3);
      expect(validation['staffCount'], 15);
      expect(validation['cashCount'], 120);
      expect(validation['stockCount'], 85);
      expect(validation['attendanceCount'], 340);
      expect(validation['dsrCount'], 42);
    });

    test('BackupService rejects invalid JSON content gracefully', () {
      final validation = BackupService.validateBackup('invalid corrupt json string');
      expect(validation['isValid'], isFalse);
      expect(validation['error'], isNotNull);
    });
  });
}
