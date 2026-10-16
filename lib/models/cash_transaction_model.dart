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

  factory CashTransactionModel.fromJson(Map<String, dynamic> json) {
    return CashTransactionModel(
      id: json['id'] as String?,
      siteId: json['site_id'] as String,
      submittedBy: json['submitted_by'] as String?,
      date: DateTime.parse(json['date'] as String),
      expenseTypeId: json['expense_type_id'] as String,
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
