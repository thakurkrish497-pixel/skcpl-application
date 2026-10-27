import 'package:flutter_test/flutter_test.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/stock_transaction_model.dart';
import 'package:skcpl_app/models/cash_transaction_model.dart';
import 'package:skcpl_app/models/daily_site_report_model.dart';

void main() {
  group('Site Staff Model & Role Tests with Module Separation', () {
    test('Worker staff model properties, module & serialization', () {
      final worker = SiteStaffModel(
        id: 'worker-1',
        siteId: 'site-123',
        name: 'Ramesh Kumar',
        role: SiteStaffRole.worker,
        modules: const [StaffModule.stock],
        pin: '1234',
        description: 'Shift Store Incharge',
        createdAt: DateTime(2026, 10, 20),
      );

      expect(worker.isWorker, isTrue);
      expect(worker.isSupervisor, isFalse);
      expect(worker.module, StaffModule.stock);
      expect(worker.module.displayName, 'Stock');
      expect(worker.role.displayName, 'Worker');

      final json = worker.toJson();
      expect(json['name'], 'Ramesh Kumar');
      expect(json['role'], 'worker');
      expect(json['module'], 'stock');
      expect(json['pin'], '1234');

      final fromJson = SiteStaffModel.fromJson(json);
      expect(fromJson.name, 'Ramesh Kumar');
      expect(fromJson.role, SiteStaffRole.worker);
      expect(fromJson.module, StaffModule.stock);
      expect(fromJson.pin, '1234');
    });

    test('StaffModule parsing from string aliases', () {
      expect(StaffModule.fromString('stock'), StaffModule.stock);
      expect(StaffModule.fromString('cashbook'), StaffModule.cashbook);
      expect(StaffModule.fromString('cash'), StaffModule.cashbook);
      expect(StaffModule.fromString('expense'), StaffModule.cashbook);
      expect(StaffModule.fromString('report'), StaffModule.report);
      expect(StaffModule.fromString('dsr'), StaffModule.report);
      expect(StaffModule.fromString('daily_report'), StaffModule.report);
      expect(StaffModule.fromString(null), StaffModule.stock);
    });

    test('Independent workers across three modules', () {
      final stockWorker = SiteStaffModel(
        id: 'w-stock',
        siteId: 'site-1',
        name: 'Amit (Stock Incharge)',
        role: SiteStaffRole.worker,
        modules: const [StaffModule.stock],
        pin: '1111',
        createdAt: DateTime.now(),
      );

      final cashWorker = SiteStaffModel(
        id: 'w-cash',
        siteId: 'site-1',
        name: 'Pooja (Cashier)',
        role: SiteStaffRole.worker,
        modules: const [StaffModule.cashbook],
        pin: '2222',
        createdAt: DateTime.now(),
      );

      final dsrWorker = SiteStaffModel(
        id: 'w-dsr',
        siteId: 'site-1',
        name: 'Rohit (Site Engineer)',
        role: SiteStaffRole.worker,
        modules: const [StaffModule.report],
        pin: '3333',
        createdAt: DateTime.now(),
      );

      final allStaff = [stockWorker, cashWorker, dsrWorker];

      final stockOnly = allStaff.where((s) => s.module == StaffModule.stock).toList();
      final cashOnly = allStaff.where((s) => s.module == StaffModule.cashbook).toList();
      final reportOnly = allStaff.where((s) => s.module == StaffModule.report).toList();

      expect(stockOnly.length, 1);
      expect(stockOnly.first.name, 'Amit (Stock Incharge)');

      expect(cashOnly.length, 1);
      expect(cashOnly.first.name, 'Pooja (Cashier)');

      expect(reportOnly.length, 1);
      expect(reportOnly.first.name, 'Rohit (Site Engineer)');
    });
  });

  group('Hierarchy Flow & Supervisor Allotment Tests', () {
    test('Stock: When supervisor is allotted -> pending supervisor review', () {
      final tx = StockTransactionModel(
        id: 'stock-1',
        siteId: 'site-123',
        productId: 'prod-1',
        metricUnitId: 'unit-1',
        type: TransactionType.inbound,
        date: DateTime(2026, 10, 20),
        quantity: 50,
        remarks: '[By: Ramesh Kumar (Worker)] [Supervisor Review: Pending] Cement arrival',
      );

      expect(tx.isPendingSupervisorReview, isTrue);
      expect(tx.isSupervisorApproved, isFalse);
      expect(tx.cleanRemarks, 'Cement arrival');
    });

    test('Stock: When supervisor approves -> isSupervisorApproved is true', () {
      final tx = StockTransactionModel(
        id: 'stock-1',
        siteId: 'site-123',
        productId: 'prod-1',
        metricUnitId: 'unit-1',
        type: TransactionType.inbound,
        date: DateTime(2026, 10, 20),
        quantity: 50,
        remarks: '[By: Ramesh Kumar (Worker)] [Supervisor: Approved by Vikas] Cement arrival',
      );

      expect(tx.isPendingSupervisorReview, isFalse);
      expect(tx.isSupervisorApproved, isTrue);
      expect(tx.cleanRemarks, 'Cement arrival');
    });

    test('Stock: Direct flow when NO supervisor allotted -> no pending supervisor tag', () {
      final tx = StockTransactionModel(
        id: 'stock-direct',
        siteId: 'site-direct',
        productId: 'prod-1',
        metricUnitId: 'unit-1',
        type: TransactionType.inbound,
        date: DateTime(2026, 10, 20),
        quantity: 50,
        remarks: '[By: Suresh (Worker)] Direct submission to Accounts',
      );

      // Direct entry is NOT held by supervisor review!
      expect(tx.isPendingSupervisorReview, isFalse);
      expect(tx.cleanRemarks, 'Direct submission to Accounts');
    });

    test('Cashbook: When supervisor is allotted vs direct flow', () {
      final pendingCash = CashTransactionModel(
        id: 'cash-1',
        siteId: 'site-123',
        expenseTypeId: 'exp-1',
        date: DateTime(2026, 10, 20),
        expenseAmount: 1200,
        amountReceived: 0,
        cashInHand: 45000,
        remarks: '[Party: HPCL] [By: Suresh Patel (Worker)] [Supervisor Review: Pending] Diesel',
      );
      expect(pendingCash.isPendingSupervisorReview, isTrue);
      expect(pendingCash.cleanRemarks, 'Diesel');

      final directCash = CashTransactionModel(
        id: 'cash-2',
        siteId: 'site-nodir',
        expenseTypeId: 'exp-1',
        date: DateTime(2026, 10, 20),
        expenseAmount: 800,
        amountReceived: 0,
        cashInHand: 45000,
        remarks: '[Party: Hardware Store] [By: Suresh Patel (Worker)] Nails & Wire',
      );
      expect(directCash.isPendingSupervisorReview, isFalse);
      expect(directCash.cleanRemarks, 'Nails & Wire');
    });

    test('Daily Site Report: Supervisor Approval and Rejection Options', () {
      // 1. Pending
      final pendingReport = DailySiteReportModel(
        id: 'dsr-1',
        siteId: 'site-123',
        date: DateTime(2026, 10, 20),
        submittedBy: 'Ramesh (Worker)',
        remarks: 'Excavation completed [Supervisor Review: Pending]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(pendingReport.isPendingSupervisorReview, isTrue);
      expect(pendingReport.isSupervisorApproved, isFalse);
      expect(pendingReport.isSupervisorRejected, isFalse);

      // 2. Approved
      final approvedReport = DailySiteReportModel(
        id: 'dsr-2',
        siteId: 'site-123',
        date: DateTime(2026, 10, 20),
        submittedBy: 'Ramesh (Worker)',
        remarks: 'Excavation completed [Supervisor: Approved by Vikas]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(approvedReport.isSupervisorApproved, isTrue);
      expect(approvedReport.isSupervisorRejected, isFalse);
      expect(approvedReport.isSupervisorReviewed, isTrue);

      // 3. Rejected with Reason
      final rejectedReport = DailySiteReportModel(
        id: 'dsr-3',
        siteId: 'site-123',
        date: DateTime(2026, 10, 20),
        submittedBy: 'Ramesh (Worker)',
        remarks: 'Excavation completed [Supervisor: Rejected - Missing compaction test photo by Vikas]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(rejectedReport.isSupervisorApproved, isFalse);
      expect(rejectedReport.isSupervisorRejected, isTrue);
      expect(rejectedReport.isSupervisorReviewed, isTrue);
      expect(rejectedReport.supervisorRejectionReason, 'Missing compaction test photo');
    });
  });
}
