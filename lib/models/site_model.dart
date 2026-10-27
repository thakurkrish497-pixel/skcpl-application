/// Model representing a construction site
class SiteModel {
  final String id;
  final String name;
  final String? address;
  final String siteLoginId;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double allocatedBudget;

  const SiteModel({
    required this.id,
    required this.name,
    this.address,
    required this.siteLoginId,
    this.isActive = true,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.allocatedBudget = 0.0,
  });

  /// True if this location is an office (e.g. Indore Head Office for Attendance)
  /// rather than an active on-ground construction site.
  bool get isHeadOffice =>
      name.toLowerCase().contains('head office') ||
      name.toLowerCase().contains('indore office') ||
      name.toLowerCase().trim() == 'indore';

  factory SiteModel.fromJson(Map<String, dynamic> json) {
    return SiteModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      siteLoginId: json['site_login_id'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      allocatedBudget: (json['allocated_budget'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'address': address,
      'site_login_id': siteLoginId,
      'is_active': isActive,
      'created_by': createdBy,
      'allocated_budget': allocatedBudget,
    };
  }

  SiteModel copyWith({
    String? id,
    String? name,
    String? address,
    String? siteLoginId,
    bool? isActive,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? allocatedBudget,
  }) {
    return SiteModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      siteLoginId: siteLoginId ?? this.siteLoginId,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      allocatedBudget: allocatedBudget ?? this.allocatedBudget,
    );
  }
}
