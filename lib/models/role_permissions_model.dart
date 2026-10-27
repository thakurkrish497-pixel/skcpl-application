import 'dart:convert';

/// Granular management credentials and approval powers configured by Admin
class RolePermissionsModel {
  // Accounts credentials
  final String accountsEmail;
  final String accountsPassword;

  // Project Head credentials
  final String projectHeadEmail;
  final String projectHeadPassword;

  // Accounts feature approval powers
  final bool accountsCanApproveCash;
  final bool accountsCanApproveStock;

  // Project Head feature approval powers
  final bool projectHeadCanApproveCash;
  final bool projectHeadCanApproveStock;
  final bool projectHeadCanApproveAttendance;
  final bool projectHeadCanApproveDSR;

  const RolePermissionsModel({
    this.accountsEmail = 'accounts@skcpl.com',
    this.accountsPassword = 'accounts123',
    this.projectHeadEmail = 'projecthead@skcpl.com',
    this.projectHeadPassword = 'projecthead123',
    this.accountsCanApproveCash = true,
    this.accountsCanApproveStock = true,
    this.projectHeadCanApproveCash = true,
    this.projectHeadCanApproveStock = true,
    this.projectHeadCanApproveAttendance = true,
    this.projectHeadCanApproveDSR = true,
  });

  RolePermissionsModel copyWith({
    String? accountsEmail,
    String? accountsPassword,
    String? projectHeadEmail,
    String? projectHeadPassword,
    bool? accountsCanApproveCash,
    bool? accountsCanApproveStock,
    bool? projectHeadCanApproveCash,
    bool? projectHeadCanApproveStock,
    bool? projectHeadCanApproveAttendance,
    bool? projectHeadCanApproveDSR,
  }) {
    return RolePermissionsModel(
      accountsEmail: accountsEmail ?? this.accountsEmail,
      accountsPassword: accountsPassword ?? this.accountsPassword,
      projectHeadEmail: projectHeadEmail ?? this.projectHeadEmail,
      projectHeadPassword: projectHeadPassword ?? this.projectHeadPassword,
      accountsCanApproveCash: accountsCanApproveCash ?? this.accountsCanApproveCash,
      accountsCanApproveStock: accountsCanApproveStock ?? this.accountsCanApproveStock,
      projectHeadCanApproveCash: projectHeadCanApproveCash ?? this.projectHeadCanApproveCash,
      projectHeadCanApproveStock: projectHeadCanApproveStock ?? this.projectHeadCanApproveStock,
      projectHeadCanApproveAttendance: projectHeadCanApproveAttendance ?? this.projectHeadCanApproveAttendance,
      projectHeadCanApproveDSR: projectHeadCanApproveDSR ?? this.projectHeadCanApproveDSR,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accounts_email': accountsEmail,
      'accounts_password': accountsPassword,
      'project_head_email': projectHeadEmail,
      'project_head_password': projectHeadPassword,
      'accounts_can_approve_cash': accountsCanApproveCash,
      'accounts_can_approve_stock': accountsCanApproveStock,
      'project_head_can_approve_cash': projectHeadCanApproveCash,
      'project_head_can_approve_stock': projectHeadCanApproveStock,
      'project_head_can_approve_attendance': projectHeadCanApproveAttendance,
      'project_head_can_approve_dsr': projectHeadCanApproveDSR,
    };
  }

  factory RolePermissionsModel.fromJson(Map<String, dynamic> json) {
    return RolePermissionsModel(
      accountsEmail: json['accounts_email'] as String? ?? 'accounts@skcpl.com',
      accountsPassword: json['accounts_password'] as String? ?? 'accounts123',
      projectHeadEmail: json['project_head_email'] as String? ?? 'projecthead@skcpl.com',
      projectHeadPassword: json['project_head_password'] as String? ?? 'projecthead123',
      accountsCanApproveCash: json['accounts_can_approve_cash'] as bool? ?? true,
      accountsCanApproveStock: json['accounts_can_approve_stock'] as bool? ?? true,
      projectHeadCanApproveCash: json['project_head_can_approve_cash'] as bool? ?? true,
      projectHeadCanApproveStock: json['project_head_can_approve_stock'] as bool? ?? true,
      projectHeadCanApproveAttendance: json['project_head_can_approve_attendance'] as bool? ?? true,
      projectHeadCanApproveDSR: json['project_head_can_approve_dsr'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static RolePermissionsModel fromJsonString(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return RolePermissionsModel.fromJson(decoded);
      }
    } catch (_) {}
    return const RolePermissionsModel();
  }
}
