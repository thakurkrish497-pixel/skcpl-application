import 'stock_transaction_model.dart';

/// Model for cash book transactions
class CashTransactionModel {
  final String? id;
  final String siteId;
  final String? submittedBy;
  final DateTime date;

  // Expense details
  final String expenseTypeId;
  final double expenseAmount;
  final double amountReceived;
  final double cashInHand;

  final String? remarks;
  final List<String> photoUrls;

  // Approval workflow
  final TransactionStatus status;
  final String? reviewedBy;
  final String? approvedBy;
  final DateTime? reviewedAt;
  final DateTime? approvedAt;
  final String? rejectionNote;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined fields
  final String? expenseTypeName;
  final String? siteName;

  const CashTransactionModel({
    this.id,
    required this.siteId,
    this.submittedBy,
    required this.date,
    required this.expenseTypeId,
    this.expenseAmount = 0,
    this.amountReceived = 0,
    required this.cashInHand,
    this.remarks,
    this.photoUrls = const [],
    this.status = TransactionStatus.pendingAccounts,
    this.reviewedBy,
    this.approvedBy,
    this.reviewedAt,
    this.approvedAt,
    this.rejectionNote,
    this.createdAt,
    this.updatedAt,
    this.expenseTypeName,
    this.siteName,
  });

  /// Whether a worker can still edit this record
  bool get isEditable => status == TransactionStatus.pendingAccounts;

  /// Whether accounts can still review this record
  bool get isReviewable => 
      status == TransactionStatus.pendingAccounts ||
      status == TransactionStatus.pendingAdmin;

  /// Whether admin can still approve this record
  bool get isApprovable => status == TransactionStatus.pendingAdmin;

  /// Whether the record is permanently locked
  bool get isLocked => status == TransactionStatus.approved;

  /// Extracts Bill / Voucher No from remarks if entered
  String? get billNo {
    final match = RegExp(r'\[Bill:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Extracts Party / Vendor Name from remarks if entered
  String? get partyName {
    final match = RegExp(r'\[Party:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Extracts manually typed expense category name if worker used the manual entry option
  String? get customExpenseType {
    final match = RegExp(r'\[Expense:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Display expense type name, prioritizing manual entry if available
  String get displayExpenseTypeName {
    final custom = customExpenseType;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    if (expenseTypeName != null &&
        expenseTypeName!.isNotEmpty &&
        expenseTypeName != 'Other (Manual Entry)') {
      return expenseTypeName!;
    }
    return 'General Expense';
  }

  /// Extracts the staff member name and role who submitted this transaction (e.g., "Ramesh (Worker)")
  String? get submitterName {
    final match = RegExp(r'\[By:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Extracts Project Head / Supervisor review note if any (e.g., "Approved by Vikas", "Edited & Approved by Vikas")
  String? get supervisorReviewNote {
    final match = RegExp(r'\[(?:Project Head|Supervisor):\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  String? get projectHeadReviewNote => supervisorReviewNote;

  /// Whether this cash transaction is currently waiting for Project Head / Supervisor review
  bool get isPendingSupervisorReview =>
      remarks?.contains('[Project Head Review: Pending]') == true ||
      remarks?.contains('[Project Head: Review Pending]') == true ||
      remarks?.contains('[Supervisor Review: Pending]') == true ||
      remarks?.contains('[Supervisor: Review Pending]') == true;

  bool get isPendingProjectHeadReview => isPendingSupervisorReview;

  /// Whether this cash transaction has been approved by the Project Head / Supervisor
  bool get isSupervisorApproved =>
      remarks?.contains('[Project Head: Approved') == true ||
      remarks?.contains('[Project Head: Edited & Approved') == true ||
      remarks?.contains('[Supervisor: Approved') == true ||
      remarks?.contains('[Supervisor: Edited & Approved') == true;

  bool get isProjectHeadApproved => isSupervisorApproved;

  /// User remarks with any system bracket tags stripped out
  String? get cleanRemarks {
    if (remarks == null) return null;
    final cleaned = remarks!
        .replaceAll(RegExp(r'\[Expense:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[Bill:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[Party:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[By:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[(?:Project Head|Supervisor)(?:\s+Review)?:\s*.+?\]\s*'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  factory CashTransactionModel.fromJson(Map<String, dynamic> json) {
    String? typeName = json['expense_type_name'] as String?;
    if (typeName == null && json['dropdown_items'] != null) {
      if (json['dropdown_items'] is Map) {
        typeName = json['dropdown_items']['value'] as String?;
      }
    }

    return CashTransactionModel(
      id: json['id'] as String?,
      siteId: json['site_id'] as String,
      submittedBy: json['submitted_by'] as String?,
      date: DateTime.parse(json['date'] as String),
      expenseTypeId: json['expense_type_id'] as String,
      expenseTypeName: typeName,
      expenseAmount: (json['expense_amount'] as num?)?.toDouble() ?? 0,
      amountReceived: (json['amount_received'] as num?)?.toDouble() ?? 0,
      cashInHand: (json['cash_in_hand'] as num).toDouble(),
      remarks: json['remarks'] as String?,
      photoUrls: List<String>.from(json['photo_urls'] ?? []),
      status: TransactionStatus.fromString(json['status'] as String),
      reviewedBy: json['reviewed_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      rejectionNote: json['rejection_note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'site_id': siteId,
      'submitted_by': submittedBy,
      'date': date.toIso8601String().split('T').first,
      'expense_type_id': expenseTypeId,
      'expense_amount': expenseAmount,
      'amount_received': amountReceived,
      'cash_in_hand': cashInHand,
      'remarks': remarks,
      'photo_urls': photoUrls,
      'status': status.dbValue,
    };
  }

  CashTransactionModel copyWith({
    String? id,
    String? siteId,
    String? submittedBy,
    DateTime? date,
    String? expenseTypeId,
    String? expenseTypeName,
    double? expenseAmount,
    double? amountReceived,
    double? cashInHand,
    String? remarks,
    List<String>? photoUrls,
    TransactionStatus? status,
    String? reviewedBy,
    String? approvedBy,
    DateTime? reviewedAt,
    DateTime? approvedAt,
    String? rejectionNote,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CashTransactionModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      submittedBy: submittedBy ?? this.submittedBy,
      date: date ?? this.date,
      expenseTypeId: expenseTypeId ?? this.expenseTypeId,
      expenseTypeName: expenseTypeName ?? this.expenseTypeName,
      expenseAmount: expenseAmount ?? this.expenseAmount,
      amountReceived: amountReceived ?? this.amountReceived,
      cashInHand: cashInHand ?? this.cashInHand,
      remarks: remarks ?? this.remarks,
      photoUrls: photoUrls ?? this.photoUrls,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectionNote: rejectionNote ?? this.rejectionNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
