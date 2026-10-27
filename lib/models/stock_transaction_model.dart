/// Transaction approval status
enum TransactionStatus {
  pendingAccounts,
  pendingAdmin,
  approved,
  rejected;

  String get displayName {
    switch (this) {
      case TransactionStatus.pendingAccounts:
        return 'Pending Accounts';
      case TransactionStatus.pendingAdmin:
        return 'Pending Admin';
      case TransactionStatus.approved:
        return 'Approved';
      case TransactionStatus.rejected:
        return 'Rejected';
    }
  }

  /// Maps to the database enum string value
  String get dbValue {
    switch (this) {
      case TransactionStatus.pendingAccounts:
        return 'pending_accounts';
      case TransactionStatus.pendingAdmin:
        return 'pending_admin';
      case TransactionStatus.approved:
        return 'approved';
      case TransactionStatus.rejected:
        return 'rejected';
    }
  }

  static TransactionStatus fromString(String value) {
    switch (value) {
      case 'pending_accounts':
        return TransactionStatus.pendingAccounts;
      case 'pending_admin':
        return TransactionStatus.pendingAdmin;
      case 'approved':
        return TransactionStatus.approved;
      case 'rejected':
        return TransactionStatus.rejected;
      default:
        return TransactionStatus.pendingAccounts;
    }
  }
}

/// Stock transaction type
enum TransactionType {
  inbound,
  outbound;

  String get displayName {
    switch (this) {
      case TransactionType.inbound:
        return 'Add Product';
      case TransactionType.outbound:
        return 'Use Product';
    }
  }

  static TransactionType fromString(String value) {
    return value == 'outbound' ? TransactionType.outbound : TransactionType.inbound;
  }
}

/// Model for stock transactions (inbound/outbound)
class StockTransactionModel {
  final String? id;
  final String siteId;
  final String? submittedBy;
  final TransactionType type;
  final DateTime date;

  // Product & Vendor references
  final String? vendorId;
  final String productId;
  final String metricUnitId;

  // Quantities & amounts
  final double quantity;
  final double? rate;
  final double sgst;
  final double igst;
  final double? finalAmount;

  final String? remarks;
  final String? unregisteredVendor;
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

  // Joined fields (populated from views/queries)
  final String? vendorName;
  final String? productName;
  final String? metricUnitName;
  final String? siteName;

  const StockTransactionModel({
    this.id,
    required this.siteId,
    this.submittedBy,
    required this.type,
    required this.date,
    this.vendorId,
    required this.productId,
    required this.metricUnitId,
    required this.quantity,
    this.rate,
    this.sgst = 0,
    this.igst = 0,
    this.finalAmount,
    this.remarks,
    this.unregisteredVendor,
    this.photoUrls = const [],
    this.status = TransactionStatus.pendingAccounts,
    this.reviewedBy,
    this.approvedBy,
    this.reviewedAt,
    this.approvedAt,
    this.rejectionNote,
    this.createdAt,
    this.updatedAt,
    this.vendorName,
    this.productName,
    this.metricUnitName,
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

  /// Calculate final amount from quantity, rate, and taxes
  double get calculatedFinalAmount {
    if (type == TransactionType.outbound) return 0;
    final baseAmount = quantity * (rate ?? 0);
    final taxAmount = baseAmount * ((sgst + igst) / 100);
    return baseAmount + taxAmount;
  }

  /// Extracts manually typed product name if worker used the manual entry option
  String? get customProduct {
    final match = RegExp(r'\[Material:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Extracts manually typed metric unit name if worker used the manual entry option
  String? get customMetricUnit {
    final match = RegExp(r'\[Unit:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Display product name, prioritizing manual entry if available
  String get displayProductName {
    final custom = customProduct;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return productName ?? 'Material';
  }

  /// Display metric unit, prioritizing manual entry if available
  String get displayMetricUnitName {
    final custom = customMetricUnit;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return metricUnitName ?? 'units';
  }

  /// Extracts Bill / Challan / Invoice No from remarks if entered
  String? get billNo {
    final match = RegExp(r'\[Bill:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Extracts Party Name from remarks if worker entered a manual party
  String? get customPartyName {
    final match = RegExp(r'\[Party:\s*(.+?)\]').firstMatch(remarks ?? '');
    return match?.group(1)?.trim();
  }

  /// Display vendor name, prioritizing manual unregistered vendor or party name if available
  String get displayVendorName {
    final customParty = customPartyName;
    if (customParty != null && customParty.isNotEmpty) {
      return customParty;
    }
    if (unregisteredVendor != null && unregisteredVendor!.trim().isNotEmpty) {
      return unregisteredVendor!.trim();
    }
    return vendorName ?? 'None';
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

  /// Whether this transaction is currently waiting for Project Head / Supervisor review
  bool get isPendingSupervisorReview =>
      remarks?.contains('[Project Head Review: Pending]') == true ||
      remarks?.contains('[Project Head: Review Pending]') == true ||
      remarks?.contains('[Supervisor Review: Pending]') == true ||
      remarks?.contains('[Supervisor: Review Pending]') == true;

  bool get isPendingProjectHeadReview => isPendingSupervisorReview;

  /// Whether this transaction has been approved by the Project Head / Supervisor
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
        .replaceAll(RegExp(r'\[Material:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[Unit:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[Bill:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[Party:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[By:\s*.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[(?:Project Head|Supervisor)(?:\s+Review)?:\s*.+?\]\s*'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  factory StockTransactionModel.fromJson(Map<String, dynamic> json) {
    String? prodName = json['product_name'] as String?;
    if (prodName == null && json['product'] != null && json['product'] is Map) {
      prodName = json['product']['value'] as String?;
    } else if (prodName == null && json['dropdowns'] != null && json['dropdowns'] is Map) {
      prodName = json['dropdowns']['value'] as String?;
    }

    String? unitName = json['metric_unit_name'] as String?;
    if (unitName == null && json['unit'] != null && json['unit'] is Map) {
      unitName = json['unit']['value'] as String?;
    }

    String? vName = json['vendor_name'] as String?;
    if (vName == null && json['vendor'] != null && json['vendor'] is Map) {
      vName = json['vendor']['value'] as String?;
    }

    String? sName = json['site_name'] as String?;
    if (sName == null && json['sites'] != null && json['sites'] is Map) {
      sName = json['sites']['name'] as String?;
    }

    return StockTransactionModel(
      id: json['id'] as String?,
      siteId: json['site_id'] as String,
      submittedBy: json['submitted_by'] as String?,
      type: TransactionType.fromString(json['type'] as String),
      date: DateTime.parse(json['date'] as String),
      vendorId: json['vendor_id'] as String?,
      productId: json['product_id'] as String,
      metricUnitId: json['metric_unit_id'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      rate: (json['rate'] as num?)?.toDouble(),
      sgst: (json['sgst'] as num?)?.toDouble() ?? 0,
      igst: (json['igst'] as num?)?.toDouble() ?? 0,
      finalAmount: (json['final_amount'] as num?)?.toDouble(),
      remarks: json['remarks'] as String?,
      unregisteredVendor: json['unregistered_vendor'] as String?,
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
      vendorName: vName,
      productName: prodName,
      metricUnitName: unitName,
      siteName: sName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'site_id': siteId,
      'submitted_by': submittedBy,
      'type': type.name,
      'date': date.toIso8601String().split('T').first,
      'vendor_id': vendorId,
      'product_id': productId,
      'metric_unit_id': metricUnitId,
      'quantity': quantity,
      'rate': rate,
      'sgst': sgst,
      'igst': igst,
      'final_amount': calculatedFinalAmount,
      'remarks': remarks,
      'unregistered_vendor': unregisteredVendor,
      'photo_urls': photoUrls,
      'status': status.dbValue,
    };
  }

  StockTransactionModel copyWith({
    String? id,
    String? siteId,
    String? submittedBy,
    TransactionType? type,
    DateTime? date,
    String? vendorId,
    String? productId,
    String? metricUnitId,
    double? quantity,
    double? rate,
    double? sgst,
    double? igst,
    double? finalAmount,
    String? remarks,
    String? unregisteredVendor,
    List<String>? photoUrls,
    TransactionStatus? status,
    String? reviewedBy,
    String? approvedBy,
    DateTime? reviewedAt,
    DateTime? approvedAt,
    String? rejectionNote,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? vendorName,
    String? productName,
    String? metricUnitName,
    String? siteName,
  }) {
    return StockTransactionModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      submittedBy: submittedBy ?? this.submittedBy,
      type: type ?? this.type,
      date: date ?? this.date,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      metricUnitId: metricUnitId ?? this.metricUnitId,
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      sgst: sgst ?? this.sgst,
      igst: igst ?? this.igst,
      finalAmount: finalAmount ?? this.finalAmount,
      remarks: remarks ?? this.remarks,
      unregisteredVendor: unregisteredVendor ?? this.unregisteredVendor,
      photoUrls: photoUrls ?? this.photoUrls,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectionNote: rejectionNote ?? this.rejectionNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      vendorName: vendorName ?? this.vendorName,
      productName: productName ?? this.productName,
      metricUnitName: metricUnitName ?? this.metricUnitName,
      siteName: siteName ?? this.siteName,
    );
  }
}
