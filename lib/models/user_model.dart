/// User roles in the system
enum UserRole {
  admin,
  accounts,
  projectHead,
  worker;

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.accounts:
        return 'Accounts';
      case UserRole.projectHead:
        return 'Project Head';
      case UserRole.worker:
        return 'Site Worker';
    }
  }

  static UserRole fromString(String value) {
    final clean = value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_').trim();
    if (clean == 'projecthead' || clean == 'project_head' || clean == 'supervisor') {
      return UserRole.projectHead;
    }
    return UserRole.values.firstWhere(
      (e) => e.name.toLowerCase() == clean,
      orElse: () => UserRole.worker,
    );
  }
}

/// User model representing a system user
class UserModel {
  final String id;
  final String email;
  final String? fullName;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      role: UserRole.fromString(json['role'] as String),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role.name,
      'is_active': isActive,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isAdmin => role == UserRole.admin;
  bool get isAccounts => role == UserRole.accounts;
  bool get isProjectHead => role == UserRole.projectHead;
  bool get isWorker => role == UserRole.worker;
}
