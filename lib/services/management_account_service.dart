import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/role_permissions_model.dart';
import '../providers/auth_provider.dart';

class ManagementAccount {
  final String userId;
  final String loginId;
  final String email;
  final int credentialRevision;
  const ManagementAccount(
      {required this.userId,
      required this.loginId,
      required this.email,
      required this.credentialRevision});
  factory ManagementAccount.fromJson(Map<String, dynamic> json) =>
      ManagementAccount(
          userId: json['user_id'] as String,
          loginId: json['login_id'] as String,
          email: json['email'] as String,
          credentialRevision: (json['credential_revision'] as num).toInt());
}

class ManagementSnapshot {
  final RolePermissionsModel policy;
  final ManagementAccount accounts;
  final ManagementAccount projectHead;
  const ManagementSnapshot(
      {required this.policy,
      required this.accounts,
      required this.projectHead});
  factory ManagementSnapshot.fromJson(Map<String, dynamic> json) {
    final roles = Map<String, dynamic>.from(json['roles'] as Map);
    return ManagementSnapshot(
        policy: RolePermissionsModel.fromJson(
            Map<String, dynamic>.from(json['policy'] as Map)),
        accounts: ManagementAccount.fromJson(
            Map<String, dynamic>.from(roles['accounts'] as Map)),
        projectHead: ManagementAccount.fromJson(
            Map<String, dynamic>.from(roles['project_head'] as Map)));
  }
}

class ManagementSaveResult {
  final ManagementSnapshot? snapshot;
  final String? error;
  final bool partial;
  const ManagementSaveResult({this.snapshot, this.error, this.partial = false});
  bool get saved => snapshot != null;
}

class ManagementAccountService {
  final SupabaseClient client;
  ManagementAccountService([SupabaseClient? client])
      : client = client ?? Supabase.instance.client;
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response =
          await client.functions.invoke('skcpl-management-control', body: body);
      if (response.data is! Map) {
        throw StateError('Invalid management server response.');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (error) {
      final data = error.details;
      if (data is Map && data['error'] is String) {
        throw StateError(data['error'] as String);
      }
      if (error.status == 404) {
        throw StateError(
            'Secure Admin controls require the local backend migration and function to be deployed first.');
      }
      throw StateError(
          'The management server is unavailable. Your changes were not confirmed saved.');
    }
  }

  Future<ManagementSnapshot> load() async {
    final response = await _invoke({'action': 'snapshot'});
    return ManagementSnapshot.fromJson(
        Map<String, dynamic>.from(response['snapshot'] as Map));
  }

  Future<ManagementSaveResult> save(
      {required String operationId,
      required ManagementSnapshot current,
      required RolePermissionsModel policy,
      required String accountsLogin,
      required String accountsEmail,
      String accountsPassword = '',
      required String projectHeadLogin,
      required String projectHeadEmail,
      String projectHeadPassword = ''}) async {
    final powers = Map<String, dynamic>.fromEntries(
        policy.toJson().entries.where((e) => e.key.contains('_can_approve_')));
    final response = await _invoke({
      'action': 'save',
      'operation_id': operationId,
      'expected_revision': current.policy.revision,
      'permissions': powers,
      'roles': {
        'accounts': {
          'user_id': current.accounts.userId,
          'login_id': accountsLogin.trim().toLowerCase(),
          'email': accountsEmail.trim().toLowerCase(),
          if (accountsPassword.isNotEmpty) 'new_password': accountsPassword
        },
        'project_head': {
          'user_id': current.projectHead.userId,
          'login_id': projectHeadLogin.trim().toLowerCase(),
          'email': projectHeadEmail.trim().toLowerCase(),
          if (projectHeadPassword.isNotEmpty)
            'new_password': projectHeadPassword
        },
      }
    });
    if (response['state'] != 'saved') {
      return ManagementSaveResult(
          error: response['error']?.toString() ??
              'Settings were not confirmed saved.',
          partial: response['state'] == 'partial');
    }
    return ManagementSaveResult(
        snapshot: ManagementSnapshot.fromJson(
            Map<String, dynamic>.from(response['snapshot'] as Map)));
  }

  static String? validateLogin(String? text) {
    final value = text?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(value) ||
        ['admin', 'administrator'].contains(value)) {
      return 'Use 3–64 letters, digits, dots, dashes or underscores. Admin is reserved.';
    }
    return null;
  }

  static String? validateEmail(String? text) {
    final value = text?.trim() ?? '';
    return value.length <= 254 &&
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)
        ? null
        : 'Enter a valid email address.';
  }

  static String? validatePassword(String? text) {
    final value = text ?? '';
    if (value.isEmpty) return null;
    return value.trim().isNotEmpty &&
            value.runes.length >= 8 &&
            utf8.encode(value).length <= 72
        ? null
        : 'Use at least 8 characters (up to 72 UTF-8 bytes), or leave blank.';
  }
}

final managementAccountServiceProvider = Provider<ManagementAccountService>(
    (ref) => ManagementAccountService(ref.read(supabaseClientProvider)));
