import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';

void main() {
  group('Project Head Multi-Tier Approval Workflow Tests', () {
    test('UserRole.projectHead parsing and UserModel getters', () {
      expect(UserRole.fromString('project_head'), UserRole.projectHead);
      expect(UserRole.fromString('projecthead'), UserRole.projectHead);
      expect(UserRole.fromString('supervisor'), UserRole.projectHead);
      expect(UserRole.projectHead.displayName, 'Project Head');

      final user = UserModel(
        id: 'ph-1',
        email: 'projecthead@skcpl.com',
        fullName: 'Vikram Singh',
        role: UserRole.projectHead,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(user.isProjectHead, isTrue);
      expect(user.isAdmin, isFalse);
      expect(user.isAccounts, isFalse);
      expect(user.isWorker, isFalse);

      final authState = AuthState(user: user);
      expect(authState.isProjectHead, isTrue);
      expect(authState.isAdmin, isFalse);
    });

    test('CashTransactionModel Project Head lifecycle: Pending -> Approved -> Accounts', () {
      // 1. Worker submits expense entry
      final workerTx = CashTransactionModel(
        id: 'c-1',
        siteId: 'site-nissarpur',
        date: DateTime.now(),
        expenseTypeId: 'exp-1',
        expenseAmount: 1850.0,
        cashInHand: 48150.0,
        remarks: '[By: Ramesh (Worker)] [Party: Sharma Store] [Bill: #104] [Project Head Review: Pending] Site cement bags unloading charges',
      );

      expect(workerTx.isPendingProjectHeadReview, isTrue);
      expect(workerTx.isPendingSupervisorReview, isTrue);
      expect(workerTx.isProjectHeadApproved, isFalse);
      expect(workerTx.partyName, 'Sharma Store');
      expect(workerTx.billNo, '#104');
      expect(workerTx.submitterName, 'Ramesh (Worker)');
      expect(workerTx.cleanRemarks, 'Site cement bags unloading charges');

      // 2. Project Head reviews & approves
      final cleanedRemarks = (workerTx.remarks ?? '')
          .replaceAll('[Project Head Review: Pending]', '')
          .replaceAll('[Supervisor Review: Pending]', '')
          .trim();
      final approvedRemarks = '$cleanedRemarks [Project Head: Approved by Vikram Singh]'.trim();

      final approvedTx = workerTx.copyWith(
        remarks: approvedRemarks,
        status: TransactionStatus.pendingAccounts,
      );

      expect(approvedTx.isPendingProjectHeadReview, isFalse);
      expect(approvedTx.isPendingSupervisorReview, isFalse);
      expect(approvedTx.isProjectHeadApproved, isTrue);
      expect(approvedTx.isSupervisorApproved, isTrue);
      expect(approvedTx.projectHeadReviewNote, 'Approved by Vikram Singh');
      expect(approvedTx.status, TransactionStatus.pendingAccounts);
      expect(approvedTx.cleanRemarks, 'Site cement bags unloading charges');
    });

    test('StockTransactionModel Project Head inward & outward approval', () {
      final stockInward = StockTransactionModel(
        id: 's-1',
        siteId: 'site-nissarpur',
        type: TransactionType.inbound,
        date: DateTime.now(),
        productId: 'prod-tmt',
        metricUnitId: 'unit-ton',
        quantity: 15.0,
        rate: 55000.0,
        remarks: '[By: Amit (Store Keeper)] [Bill: #CH-9081] [Project Head Review: Pending] TMT Steel Reinforcement Bars',
      );

      expect(stockInward.isPendingProjectHeadReview, isTrue);
      expect(stockInward.isProjectHeadApproved, isFalse);
      expect(stockInward.billNo, '#CH-9081');

      // Project Head approves
      final approvedStock = stockInward.copyWith(
        remarks: '${stockInward.cleanRemarks} [Project Head: Approved by Vikram Singh]',
        status: TransactionStatus.pendingAccounts,
      );

      expect(approvedStock.isPendingProjectHeadReview, isFalse);
      expect(approvedStock.isProjectHeadApproved, isTrue);
      expect(approvedStock.projectHeadReviewNote, 'Approved by Vikram Singh');
      expect(approvedStock.status, TransactionStatus.pendingAccounts);
    });

    test('DailySiteReportModel Project Head review and rejection reasons', () {
      final dsr = DailySiteReportModel(
        id: 'dsr-1',
        siteId: 'site-pipalrawa',
        date: DateTime.now(),
        submittedBy: 'Kailash (Site Engineer)',
        remarks: '[Project Head Review: Pending]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(dsr.isPendingProjectHeadReview, isTrue);
      expect(dsr.isProjectHeadApproved, isFalse);

      // Approved
      final approvedDsr = dsr.copyWith(
        remarks: '[Project Head: Approved by Vikram Singh]',
      );
      expect(approvedDsr.isProjectHeadApproved, isTrue);
      expect(approvedDsr.isProjectHeadReviewed, isTrue);

      // Rejected
      final rejectedDsr = dsr.copyWith(
        remarks: '[Project Head: Rejected - Missing compaction test photos by Vikram Singh]',
      );
      expect(rejectedDsr.isProjectHeadRejected, isTrue);
      expect(rejectedDsr.projectHeadRejectionReason, 'Missing compaction test photos');
    });

    test('Attendance Regularization: Project Head to Admin without Accounts', () {
      // 1. Worker arrives >40m late and requests regularization
      final req = AttendanceRecordModel(
        id: 'att-1',
        siteId: 'site-1',
        siteName: 'Nissarpur Site',
        staffId: 'staff-1',
        staffName: 'Ramesh Carpenter',
        staffRole: 'Worker',
        date: DateTime.now(),
        punchInTime: DateTime.now().subtract(const Duration(hours: 6)),
        status: AttendanceStatus.regularizationPending,
        lateMinutes: 55,
        isWithinSite: true,
        distanceMeters: 45.0,
        regularizationReason: 'State transport bus breakdown near Manawar',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(req.status, AttendanceStatus.regularizationPending);
      expect(req.isPendingAdminReview, isTrue);

      // 2. Project Head verifies & forwards directly to Admin (No accounts involved)
      final reviewedByProjectHead = req.copyWith(
        adminDecisionNote: '[Project Head: Verified & Recommended Present by Vikram Singh]',
        reviewedBy: 'Project Head: Vikram Singh',
      );

      expect(reviewedByProjectHead.adminDecisionNote, contains('Project Head: Verified'));
      expect(reviewedByProjectHead.reviewedBy, contains('Project Head'));

      // 3. Admin gives final approval (status moves to regularizedPresent)
      final adminApproved = reviewedByProjectHead.copyWith(
        status: AttendanceStatus.regularizedPresent,
        adminDecisionNote: '${reviewedByProjectHead.adminDecisionNote} • Final Admin Authorization Granted',
      );

      expect(adminApproved.status, AttendanceStatus.regularizedPresent);
      expect(adminApproved.isPresent, isTrue);
    });

    test('All approval queues sort descending with latest request on top', () {
      final earlierTime = DateTime(2026, 10, 26, 9, 30);
      final latestTime = DateTime(2026, 10, 26, 14, 45);

      // Stock
      final stockList = [
        StockTransactionModel(
          id: 's-early',
          siteId: 'site-1',
          productId: 'p-1',
          metricUnitId: 'unit-1',
          date: earlierTime,
          type: TransactionType.inbound,
          quantity: 10,
          createdAt: earlierTime,
          updatedAt: earlierTime,
        ),
        StockTransactionModel(
          id: 's-late',
          siteId: 'site-1',
          productId: 'p-1',
          metricUnitId: 'unit-1',
          date: latestTime,
          type: TransactionType.inbound,
          quantity: 20,
          createdAt: latestTime,
          updatedAt: latestTime,
        ),
      ]..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));

      expect(stockList.first.id, equals('s-late'));

      // Cash
      final cashList = [
        CashTransactionModel(
          id: 'c-early',
          siteId: 'site-1',
          date: earlierTime,
          expenseTypeId: 'exp-1',
          expenseAmount: 100,
          cashInHand: 900,
          createdAt: earlierTime,
          updatedAt: earlierTime,
        ),
        CashTransactionModel(
          id: 'c-late',
          siteId: 'site-1',
          date: latestTime,
          expenseTypeId: 'exp-1',
          expenseAmount: 200,
          cashInHand: 700,
          createdAt: latestTime,
          updatedAt: latestTime,
        ),
      ]..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));

      expect(cashList.first.id, equals('c-late'));

      // DSR
      final dsrList = [
        DailySiteReportModel(
          id: 'dsr-early',
          siteId: 'site-1',
          date: earlierTime,
          createdAt: earlierTime,
          updatedAt: earlierTime,
        ),
        DailySiteReportModel(
          id: 'dsr-late',
          siteId: 'site-1',
          date: latestTime,
          createdAt: latestTime,
          updatedAt: latestTime,
        ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      expect(dsrList.first.id, equals('dsr-late'));

      // Attendance
      final attList = [
        AttendanceRecordModel(
          id: 'att-early',
          siteId: 'site-1',
          siteName: 'Site 1',
          staffId: 'st-1',
          staffName: 'Dev',
          staffRole: 'Worker',
          date: earlierTime,
          status: AttendanceStatus.regularizationPending,
          createdAt: earlierTime,
          updatedAt: earlierTime,
        ),
        AttendanceRecordModel(
          id: 'att-late',
          siteId: 'site-1',
          siteName: 'Site 1',
          staffId: 'st-2',
          staffName: 'Raju',
          staffRole: 'Worker',
          date: latestTime,
          status: AttendanceStatus.regularizationPending,
          createdAt: latestTime,
          updatedAt: latestTime,
        ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      expect(attList.first.id, equals('att-late'));
    });
  });
}
