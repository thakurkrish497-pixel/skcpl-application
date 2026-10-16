import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/user_model.dart';

/// Handles authentication for all three user roles
class AuthService {
  final SupabaseClient _client;

  AuthService(this._client);

  /// Get the current Supabase auth user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign in Admin or Accounts user via email/password (Supabase Auth)
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw Exception('Login failed. Please check your credentials.');
    }

    // Fetch user profile with role
    final profileData = await _client
        .from('users')
        .select()
        .eq('id', response.user!.id)
        .single();

    return UserModel.fromJson(profileData);
  }

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

    final data = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserModel.fromJson(data);
  }
}
