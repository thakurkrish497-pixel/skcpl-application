import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'management_support.dart';
import '../models/user_model.dart';

/// Handles authentication for all three user roles
class AuthService {
  final SupabaseClient _client;

  AuthService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// Get the current Supabase auth user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign in Admin, Accounts, or Project Head via email/password
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    var cleanEmail = email.trim().toLowerCase();
    if (cleanEmail == 'admin') {
      cleanEmail = 'admin@skcpl.com';
    } else if (!cleanEmail.contains('@')) {
      try {
        final email = await _client.rpc('skcpl_resolve_management_login',
            params: {'p_login': cleanEmail});
        if (email is! String || email.isEmpty) {
          throw const AuthException('Invalid Login ID or password.');
        }
        cleanEmail = email;
      } catch (error) {
        if (!isMissingManagementBackend(error)) rethrow;
        // Compatibility while the new local backend has not been deployed.
        if (['project', 'projecthead', 'head'].contains(cleanEmail)) {
          cleanEmail = 'projecthead@skcpl.com';
        } else if (['accounts', 'account'].contains(cleanEmail)) {
          cleanEmail = 'accounts@skcpl.com';
        } else {
          throw const AuthException('Invalid Login ID or password.');
        }
      }
    }

    if (_client.auth.currentUser != null) await _client.auth.signOut();
    final response = await _client.auth
        .signInWithPassword(email: cleanEmail, password: password);
    if (response.user == null) throw StateError('Company sign-in failed.');
    final profile = await _client
        .from('users')
        .select()
        .eq('id', response.user!.id)
        .maybeSingle();
    if (profile == null || profile['is_active'] == false) {
      await _client.auth.signOut();
      throw StateError(
          'An active company role profile is required. Contact Admin.');
    }
    if (!['admin', 'accounts', 'project_head', 'worker']
        .contains(profile['role'])) {
      await _client.auth.signOut();
      throw StateError('Your company role is not recognized. Contact Admin.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _sessionVersionKey(response.user!.id),
        (response.user!.appMetadata['skcpl_credential_revision'] as num?)
                ?.toInt() ??
            0);
    return UserModel.fromJson(profile);
  }

  String _sessionVersionKey(String id) =>
      'skcpl_management_session_revision_v1_$id';
  Future<bool> acceptsCredentialRevision(
      String id, int requiredRevision) async {
    final prefs = await SharedPreferences.getInstance();
    return requiredRevision <= (prefs.getInt(_sessionVersionKey(id)) ?? 0);
  }

  Future<void> signOutForCredentialChange() =>
      _client.auth.signOut(scope: SignOutScope.local);

  /// Sign in a site worker using site-specific credentials
  /// Uses a custom verification against the sites table
  Future<Map<String, dynamic>> signInToSite({
    required String siteLoginId,
    required String password,
  }) async {
    // Hash the password for comparison
    final passwordHash = sha256.convert(utf8.encode(password)).toString();

    // Query the site by login ID
    final siteData = await _client
        .from('sites')
        .select()
        .eq('site_login_id', siteLoginId)
        .eq('is_active', true)
        .maybeSingle();

    if (siteData == null) {
      throw Exception('Site not found or inactive.');
    }

    if (siteData['site_password_hash'] != passwordHash) {
      throw Exception('Invalid site credentials.');
    }

    return siteData;
  }

  /// Register a new Admin or Accounts user (admin-only operation)
  Future<UserModel> registerUser({
    required String email,
    required String password,
    required UserRole role,
    String? fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw Exception('Registration failed.');
    }

    // Create user profile
    final profileData = {
      'id': response.user!.id,
      'email': email,
      'full_name': fullName,
      'role': role.name,
    };

    await _client.from('users').insert(profileData);

    return UserModel(
      id: response.user!.id,
      email: email,
      fullName: fullName,
      role: role,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Sign out the current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Get the current user's profile from the users table
  Future<UserModel?> getCurrentUserProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;

    final data =
        await _client.from('users').select().eq('id', userId).maybeSingle();

    if (data == null || data['is_active'] == false) return null;
    return UserModel.fromJson(data);
  }
}
