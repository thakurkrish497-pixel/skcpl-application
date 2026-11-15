import 'dart:convert';

/// Granular management credentials and approval powers configured by Admin
class RolePermissionsModel {
  // Login labels are nonsecret; passwords are never persisted.
  final int revision;
  final String accountsLoginId;
  final String projectHeadLoginId;
  final int accountsCredentialRevision;
  final int projectHeadCredentialRevision;
  final bool accountsCanApproveAttendance;
  final bool accountsCanApproveDSR;

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
    this.revision = 0,
    this.accountsLoginId = 'accounts',
    this.projectHeadLoginId = 'project',
    this.accountsCredentialRevision = 0,
    this.projectHeadCredentialRevision = 0,
    this.accountsCanApproveAttendance = false,
    this.accountsCanApproveDSR = false,
    this.accountsEmail = 'accounts@skcpl.com',
    this.accountsPassword = '',
    this.projectHeadEmail = 'projecthead@skcpl.com',
    this.projectHeadPassword = '',
    this.accountsCanApproveCash = true,
    this.accountsCanApproveStock = true,
    this.projectHeadCanApproveCash = true,
    this.projectHeadCanApproveStock = true,
    this.projectHeadCanApproveAttendance = true,
    this.projectHeadCanApproveDSR = true,
  });

  RolePermissionsModel copyWith({
    int? revision,
    String? accountsLoginId,
    String? projectHeadLoginId,
    int? accountsCredentialRevision,
    int? projectHeadCredentialRevision,
    bool? accountsCanApproveAttendance,
    bool? accountsCanApproveDSR,
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
      revision: revision ?? this.revision,
      accountsLoginId: accountsLoginId ?? this.accountsLoginId,
      projectHeadLoginId: projectHeadLoginId ?? this.projectHeadLoginId,
      accountsCredentialRevision:
          accountsCredentialRevision ?? this.accountsCredentialRevision,
      projectHeadCredentialRevision:
          projectHeadCredentialRevision ?? this.projectHeadCredentialRevision,
      accountsCanApproveAttendance:
          accountsCanApproveAttendance ?? this.accountsCanApproveAttendance,
      accountsCanApproveDSR:
          accountsCanApproveDSR ?? this.accountsCanApproveDSR,
      accountsEmail: accountsEmail ?? this.accountsEmail,
      accountsPassword: accountsPassword ?? this.accountsPassword,
      projectHeadEmail: projectHeadEmail ?? this.projectHeadEmail,
      projectHeadPassword: projectHeadPassword ?? this.projectHeadPassword,
      accountsCanApproveCash:
          accountsCanApproveCash ?? this.accountsCanApproveCash,
      accountsCanApproveStock:
          accountsCanApproveStock ?? this.accountsCanApproveStock,
      projectHeadCanApproveCash:
          projectHeadCanApproveCash ?? this.projectHeadCanApproveCash,
      projectHeadCanApproveStock:
          projectHeadCanApproveStock ?? this.projectHeadCanApproveStock,
      projectHeadCanApproveAttendance: projectHeadCanApproveAttendance ??
          this.projectHeadCanApproveAttendance,
      projectHeadCanApproveDSR:
          projectHeadCanApproveDSR ?? this.projectHeadCanApproveDSR,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'revision': revision,
      'accounts_login_id': accountsLoginId,
      'project_head_login_id': projectHeadLoginId,
      'accounts_credential_revision': accountsCredentialRevision,
      'project_head_credential_revision': projectHeadCredentialRevision,
      'accounts_can_approve_attendance': accountsCanApproveAttendance,
      'accounts_can_approve_dsr': accountsCanApproveDSR,
      'accounts_email': accountsEmail,
      'project_head_email': projectHeadEmail,
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
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      accountsLoginId: json['accounts_login_id'] as String? ?? 'accounts',
      projectHeadLoginId: json['project_head_login_id'] as String? ?? 'project',
      accountsCredentialRevision:
          (json['accounts_credential_revision'] as num?)?.toInt() ?? 0,
      projectHeadCredentialRevision:
          (json['project_head_credential_revision'] as num?)?.toInt() ?? 0,
      accountsCanApproveAttendance:
          json['accounts_can_approve_attendance'] as bool? ?? false,
      accountsCanApproveDSR: json['accounts_can_approve_dsr'] as bool? ?? false,
      accountsEmail: json['accounts_email'] as String? ?? 'accounts@skcpl.com',
      accountsPassword: '',
      projectHeadEmail:
          json['project_head_email'] as String? ?? 'projecthead@skcpl.com',
      projectHeadPassword: '',
      accountsCanApproveCash:
          json['accounts_can_approve_cash'] as bool? ?? true,
      accountsCanApproveStock:
          json['accounts_can_approve_stock'] as bool? ?? true,
      projectHeadCanApproveCash:
          json['project_head_can_approve_cash'] as bool? ?? true,
      projectHeadCanApproveStock:
          json['project_head_can_approve_stock'] as bool? ?? true,
      projectHeadCanApproveAttendance:
          json['project_head_can_approve_attendance'] as bool? ?? true,
      projectHeadCanApproveDSR:
          json['project_head_can_approve_dsr'] as bool? ?? true,
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
