/// Category types for admin-managed dropdown values
enum DropdownCategory {
  vendor,
  product,
  metricUnit,
  expenseType;

  String get displayName {
    switch (this) {
      case DropdownCategory.vendor:
        return 'Vendors';
      case DropdownCategory.product:
        return 'Products';
      case DropdownCategory.metricUnit:
        return 'Metric Units';
      case DropdownCategory.expenseType:
        return 'Expense Types';
    }
  }

  /// Maps to the database enum string value
  String get dbValue {
    switch (this) {
      case DropdownCategory.vendor:
        return 'vendor';
      case DropdownCategory.product:
        return 'product';
      case DropdownCategory.metricUnit:
        return 'metric_unit';
      case DropdownCategory.expenseType:
        return 'expense_type';
    }
  }

  static DropdownCategory fromString(String value) {
    switch (value) {
      case 'vendor':
        return DropdownCategory.vendor;
      case 'product':
        return DropdownCategory.product;
      case 'metric_unit':
        return DropdownCategory.metricUnit;
      case 'expense_type':
        return DropdownCategory.expenseType;
      default:
        return DropdownCategory.product;
    }
  }
}

/// Model for admin-managed dropdown items
class DropdownItemModel {
  final String id;
  final String? siteId;
  final DropdownCategory category;
  final String value;
  final Map<String, dynamic> metadata;
  final bool isActive;
  final int sortOrder;
  final DateTime? createdAt;

  const DropdownItemModel({
    required this.id,
    this.siteId,
    required this.category,
    required this.value,
    this.metadata = const {},
    this.isActive = true,
    this.sortOrder = 0,
    this.createdAt,
  });

  factory DropdownItemModel.fromJson(Map<String, dynamic> json) {
    return DropdownItemModel(
      id: json['id'] as String,
      siteId: json['site_id'] as String?,
      category: DropdownCategory.fromString(json['category'] as String),
      value: json['value'] as String,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'site_id': siteId,
      'category': category.dbValue,
      'value': value,
      'metadata': metadata,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  DropdownItemModel copyWith({
    String? id,
    String? siteId,
    DropdownCategory? category,
    String? value,
    Map<String, dynamic>? metadata,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return DropdownItemModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      category: category ?? this.category,
      value: value ?? this.value,
      metadata: metadata ?? this.metadata,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
