/// Role of a staff member at a construction site
enum SiteStaffRole {
  worker,
  supervisor;

  String get displayName {
    switch (this) {
      case SiteStaffRole.worker:
        return 'Worker';
      case SiteStaffRole.supervisor:
        return 'Supervisor';
    }
  }

  static SiteStaffRole fromString(String? value) {
    if (value == null) return SiteStaffRole.worker;
    final clean = value.toLowerCase().trim();
    if (clean == 'supervisor') return SiteStaffRole.supervisor;
    return SiteStaffRole.worker;
  }
}

/// Feature / module to which the staff member is assigned
enum StaffModule {
  stock,
  cashbook,
  report,
  attendance;

  String get displayName {
    switch (this) {
      case StaffModule.stock:
        return 'Stock';
      case StaffModule.cashbook:
        return 'Cashbook';
      case StaffModule.report:
        return 'Daily Site Report';
      case StaffModule.attendance:
        return 'Attendance';
    }
  }

  static StaffModule fromString(String? value) {
    if (value == null) return StaffModule.stock;
    final clean = value.toLowerCase().trim();
    if (clean == 'cashbook' || clean == 'cash' || clean == 'expense') return StaffModule.cashbook;
    if (clean == 'report' || clean == 'dsr' || clean == 'daily_report') return StaffModule.report;
    if (clean == 'attendance' || clean == 'att' || clean == 'office') return StaffModule.attendance;
    return StaffModule.stock;
  }
}

/// Model representing a staff member belonging to a specific site and authorized for multiple modules.
class SiteStaffModel {
  final String id;
  final String siteId;
  final String name;
  final SiteStaffRole role;
  final List<StaffModule> modules;
  final String pin; // Login password (can be words or numbers of arbitrary length set by admin)
  
  // Optional identifying details to differentiate duplicate names
  final String? phone; // Contact phone number
  final String? employeeCode; // e.g. "SK-01", "EMP-23"
  final String? designation; // e.g. "Senior Mason", "Civil Supervisor", "Store Incharge"
  final String? fatherName; // e.g. "S/o Rameshwar"
  final String? description; // General notes / remarks

  // Verification & KYC Documents
  final DateTime? dateOfBirth; // Staff birth date
  final String? aadharNumber; // 12-digit UIDAI Aadhar number
  final String? aadharCardUrl; // Cloud URL to Aadhar card photo/scan
  final String? panNumber; // 10-character PAN number
  final String? panCardUrl; // Cloud URL to PAN card photo/scan
  
  final bool isActive;
  final DateTime createdAt;

  const SiteStaffModel({
    required this.id,
    required this.siteId,
    required this.name,
    required this.role,
    this.modules = const [StaffModule.stock],
    required this.pin,
    this.phone,
    this.employeeCode,
    this.designation,
    this.fatherName,
    this.description,
    this.dateOfBirth,
    this.aadharNumber,
    this.aadharCardUrl,
    this.panNumber,
    this.panCardUrl,
    this.isActive = true,
    required this.createdAt,
  });

  /// Backward-compatibility getter for single-module access
  StaffModule get module => modules.isNotEmpty ? modules.first : StaffModule.stock;

  /// Calculated age helper based on birth date
  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int a = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month || (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      a--;
    }
    return a >= 0 ? a : null;
  }

  /// Masked Aadhar for safe UI display (e.g. '•••• •••• 1234')
  String? get maskedAadhar {
    if (aadharNumber == null || aadharNumber!.trim().isEmpty) return null;
    final clean = aadharNumber!.replaceAll(' ', '').trim();
    if (clean.length >= 4) {
      return '•••• •••• ${clean.substring(clean.length - 4)}';
    }
    return aadharNumber;
  }

  /// Check if this staff member has KYC documents attached
  bool get hasAadharCard => aadharCardUrl != null && aadharCardUrl!.trim().isNotEmpty;
  bool get hasPanCard => panCardUrl != null && panCardUrl!.trim().isNotEmpty;

  /// Check if this staff member is active and authorized for a specific module
  bool hasModule(StaffModule m) => isActive && modules.contains(m);

  bool get isSupervisor => role == SiteStaffRole.supervisor;
  bool get isWorker => role == SiteStaffRole.worker;

  /// Helper string to clearly differentiate employees with identical names
  String get identificationSubtitle {
    final parts = <String>[];
    if (employeeCode != null && employeeCode!.trim().isNotEmpty) {
      parts.add('ID: ${employeeCode!.trim()}');
    }
    if (designation != null && designation!.trim().isNotEmpty) {
      parts.add(designation!.trim());
    }
    if (fatherName != null && fatherName!.trim().isNotEmpty) {
      parts.add(fatherName!.trim());
    }
    if (phone != null && phone!.trim().isNotEmpty) {
      parts.add('📞 ${phone!.trim()}');
    }
    if (dateOfBirth != null && age != null) {
      parts.add('Age: $age yrs');
    }
    if (parts.isEmpty && description != null && description!.trim().isNotEmpty) {
      parts.add(description!.trim());
    }
    return parts.join(' • ');
  }

  factory SiteStaffModel.fromJson(Map<String, dynamic> json) {
    // Parse multi-module list or fallback to single module
    List<StaffModule> parsedModules = [];
    if (json['modules'] is List) {
      parsedModules = (json['modules'] as List)
          .map((m) => StaffModule.fromString(m.toString()))
          .toList();
    } else if (json['module'] != null) {
      parsedModules = [StaffModule.fromString(json['module'] as String?)];
    } else {
      // Legacy fallback only if neither 'modules' nor 'module' is present
      parsedModules = const [];
    }

    DateTime? dob;
    if (json['date_of_birth'] != null) {
      dob = DateTime.tryParse(json['date_of_birth'] as String);
    } else if (json['dob'] != null) {
      dob = DateTime.tryParse(json['dob'] as String);
    }

    return SiteStaffModel(
      id: json['id'] as String? ?? '',
      siteId: json['site_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Staff',
      role: SiteStaffRole.fromString(json['role'] as String?),
      modules: parsedModules,
      pin: json['pin']?.toString() ?? '1234',
      phone: json['phone'] as String?,
      employeeCode: (json['employee_code'] ?? json['employeeCode']) as String?,
      designation: json['designation'] as String?,
      fatherName: (json['father_name'] ?? json['fatherName']) as String?,
      description: json['description'] as String?,
      dateOfBirth: dob,
      aadharNumber: (json['aadhar_number'] ?? json['aadharNumber']) as String?,
      aadharCardUrl: (json['aadhar_card_url'] ?? json['aadharCardUrl']) as String?,
      panNumber: (json['pan_number'] ?? json['panNumber']) as String?,
      panCardUrl: (json['pan_card_url'] ?? json['panCardUrl']) as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'site_id': siteId,
      'name': name,
      'role': role.name,
      'module': module.name, // backward-compatible single value
      'modules': modules.map((m) => m.name).toList(), // modern multi-module list
      'pin': pin,
      'phone': phone,
      'employee_code': employeeCode,
      'designation': designation,
      'father_name': fatherName,
      'description': description,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'aadhar_number': aadharNumber,
      'aadhar_card_url': aadharCardUrl,
      'pan_number': panNumber,
      'pan_card_url': panCardUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  SiteStaffModel copyWith({
    String? id,
    String? siteId,
    String? name,
    SiteStaffRole? role,
    StaffModule? module,
    List<StaffModule>? modules,
    String? pin,
    String? phone,
    String? employeeCode,
    String? designation,
    String? fatherName,
    String? description,
    DateTime? dateOfBirth,
    String? aadharNumber,
    String? aadharCardUrl,
    String? panNumber,
    String? panCardUrl,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return SiteStaffModel(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      name: name ?? this.name,
      role: role ?? this.role,
      modules: modules ?? (module != null ? [module] : this.modules),
      pin: pin ?? this.pin,
      phone: phone ?? this.phone,
      employeeCode: employeeCode ?? this.employeeCode,
      designation: designation ?? this.designation,
      fatherName: fatherName ?? this.fatherName,
      description: description ?? this.description,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      aadharNumber: aadharNumber ?? this.aadharNumber,
      aadharCardUrl: aadharCardUrl ?? this.aadharCardUrl,
      panNumber: panNumber ?? this.panNumber,
      panCardUrl: panCardUrl ?? this.panCardUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
