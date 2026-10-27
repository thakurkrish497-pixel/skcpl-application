import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/site_staff_model.dart';

void main() {
  group('SiteStaffModel KYC & Identity Tests', () {
    test('Staff KYC fields initialization, age calculation, and masked Aadhar', () {
      final dob = DateTime(1995, 5, 20);
      final staff = SiteStaffModel(
        id: 'staff-kyc-1',
        siteId: 'site-hatpipliya',
        name: 'Daksh Sharma',
        phone: '9876543210',
        pin: '1234',
        role: SiteStaffRole.worker,
        createdAt: DateTime(2025, 1, 1),
        dateOfBirth: dob,
        aadharNumber: '123456789012',
        aadharCardUrl: 'https://supabase.co/storage/v1/object/public/transaction_photos/aadhar_daksh.jpg',
        panNumber: 'ABCDE1234F',
        panCardUrl: 'https://supabase.co/storage/v1/object/public/transaction_photos/pan_daksh.jpg',
      );

      // Verify basic fields
      expect(staff.dateOfBirth, equals(dob));
      expect(staff.age, isNotNull);
      expect(staff.age! >= 28, isTrue); // Age relative to today
      expect(staff.aadharNumber, equals('123456789012'));
      expect(staff.maskedAadhar, equals('•••• •••• 9012'));
      expect(staff.hasAadharCard, isTrue);
      expect(staff.aadharCardUrl, contains('aadhar_daksh.jpg'));
      expect(staff.panNumber, equals('ABCDE1234F'));
      expect(staff.hasPanCard, isTrue);
      expect(staff.panCardUrl, contains('pan_daksh.jpg'));
    });

    test('Staff KYC JSON serialization and deserialization roundtrip', () {
      final dob = DateTime(2000, 1, 15);
      final staff = SiteStaffModel(
        id: 'staff-kyc-2',
        siteId: 'site-indore',
        name: 'Amit Patel',
        phone: '9123456789',
        pin: '5678',
        role: SiteStaffRole.supervisor,
        createdAt: DateTime(2025, 2, 1),
        dateOfBirth: dob,
        aadharNumber: '987654321098',
        aadharCardUrl: 'https://supabase.co/storage/v1/object/public/transaction_photos/aadhar_amit.jpg',
        panNumber: 'FGHIJ5678K',
        panCardUrl: 'https://supabase.co/storage/v1/object/public/transaction_photos/pan_amit.jpg',
      );

      final json = staff.toJson();
      expect(json['date_of_birth'], equals(dob.toIso8601String()));
      expect(json['aadhar_number'], equals('987654321098'));
      expect(json['aadhar_card_url'], contains('aadhar_amit.jpg'));
      expect(json['pan_number'], equals('FGHIJ5678K'));
      expect(json['pan_card_url'], contains('pan_amit.jpg'));

      final restored = SiteStaffModel.fromJson(json);
      expect(restored.id, equals(staff.id));
      expect(restored.name, equals(staff.name));
      expect(restored.dateOfBirth?.year, equals(2000));
      expect(restored.dateOfBirth?.month, equals(1));
      expect(restored.dateOfBirth?.day, equals(15));
      expect(restored.aadharNumber, equals('987654321098'));
      expect(restored.maskedAadhar, equals('•••• •••• 1098'));
      expect(restored.aadharCardUrl, equals(staff.aadharCardUrl));
      expect(restored.panNumber, equals('FGHIJ5678K'));
      expect(restored.panCardUrl, equals(staff.panCardUrl));
      expect(restored.hasAadharCard, isTrue);
      expect(restored.hasPanCard, isTrue);
    });

    test('Staff KYC copyWith allows updating and clearing fields', () {
      final staff = SiteStaffModel(
        id: 'staff-kyc-3',
        siteId: 'site-bhopal',
        name: 'Rohan Verma',
        phone: '9988776655',
        pin: '9999',
        role: SiteStaffRole.worker,
        createdAt: DateTime(2025, 3, 1),
      );

      expect(staff.dateOfBirth, isNull);
      expect(staff.age, isNull);
      expect(staff.hasAadharCard, isFalse);
      expect(staff.hasPanCard, isFalse);

      final updated = staff.copyWith(
        dateOfBirth: DateTime(1992, 11, 10),
        aadharNumber: '555566667777',
        aadharCardUrl: 'https://example.com/aadhar.png',
        panNumber: 'ZYXWV9876U',
        panCardUrl: 'https://example.com/pan.png',
      );

      expect(updated.dateOfBirth, equals(DateTime(1992, 11, 10)));
      expect(updated.maskedAadhar, equals('•••• •••• 7777'));
      expect(updated.hasAadharCard, isTrue);
      expect(updated.panNumber, equals('ZYXWV9876U'));
      expect(updated.hasPanCard, isTrue);
    });
  });
}
