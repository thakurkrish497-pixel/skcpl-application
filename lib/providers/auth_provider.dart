import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/site_model.dart';
import '../models/role_permissions_model.dart';
import '../services/auth_service.dart';

/// Provides the standard Supabase client instance (for Auth)
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Shared authenticated client. Database access must be enforced by server policies.
final supabaseServiceClientProvider = Provider<SupabaseClient>((ref) {
  return ref.read(supabaseClientProvider);
});

/// Provides the AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(supabaseClientProvider));
});

/// Auth state holding current user and active site session
class AuthState {
  final UserModel? user;
  final SiteModel? activeSite;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.activeSite,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    UserModel? user,
    SiteModel? activeSite,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearSite = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      activeSite: clearSite ? null : (activeSite ?? this.activeSite),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get isAuthenticated => user != null;
  bool get hasSiteSession => activeSite != null;
  bool get isAdmin => user?.isAdmin ?? false;
  bool get isAccounts => user?.isAccounts ?? false;
  bool get isProjectHead => user?.isProjectHead ?? false;
  bool get isWorker => user?.isWorker ?? false;
}

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  int _sessionRevision = 0;
  Future<void>? _credentialLogout;

  AuthNotifier(this._authService) : super(const AuthState()) {
    checkSession();
  }

  /// Sign in as Admin or Accounts via email
  Future<void> signInWithEmail(String email, String password) async {
    final revision = ++_sessionRevision;
    state = const AuthState(isLoading: true);
    try {
      await _credentialLogout;
      final user = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
      if (!mounted || revision != _sessionRevision) return;
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      if (!mounted || revision != _sessionRevision) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Sign in to a specific site as a worker
  Future<void> signInToSite(String siteLoginId, String password) async {
    final revision = ++_sessionRevision;
    state = const AuthState(isLoading: true);
    try {
      await _authService.signOut();
      final siteData = await _authService.signInToSite(
        siteLoginId: siteLoginId,
        password: password,
      );
      if (!mounted || revision != _sessionRevision) return;
      final site = SiteModel.fromJson(siteData);
      state = state.copyWith(activeSite: site, isLoading: false);
    } catch (e) {
      if (!mounted || revision != _sessionRevision) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> enforceCredentialRevision(RolePermissionsModel policy) async {
    final user = state.user;
    if (user == null || user.isAdmin) return;
    final requiredRevision = user.isAccounts
        ? policy.accountsCredentialRevision
        : user.isProjectHead
            ? policy.projectHeadCredentialRevision
            : 0;
    final revision = _sessionRevision;
    if (await _authService.acceptsCredentialRevision(
        user.id, requiredRevision)) {
      return;
    }
    if (!mounted || revision != _sessionRevision || state.user?.id != user.id) {
      return;
    }
    ++_sessionRevision;
    state = const AuthState(
        error:
            'Your login details were changed by Admin. Sign in again. Your saved entries remain on this device.');
    _credentialLogout = _authService.signOutForCredentialChange();
    try {
      await _credentialLogout;
    } catch (_) {/* Keep UI signed out and preserve drafts. */} finally {
      _credentialLogout = null;
    }
  }

  /// Set the active site (for navigating to a specific site)
  void setActiveSite(SiteModel site) {
    state = state.copyWith(activeSite: site);
  }

  /// Clear the active site session
  void clearSiteSession() {
    state = state.copyWith(clearSite: true);
  }

  /// Sign out completely
  Future<void> signOut() async {
    ++_sessionRevision;
    state = const AuthState();
    await _authService.signOut();
  }

  /// Clear any error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Check and restore existing session
  Future<void> checkSession() async {
    final revision = ++_sessionRevision;
    state = state.copyWith(isLoading: true);
    try {
      final user = await _authService.getCurrentUserProfile();
      if (!mounted || revision != _sessionRevision) return;
      state = state.copyWith(user: user, isLoading: false);
    } catch (_) {
      if (!mounted || revision != _sessionRevision) return;
      state = state.copyWith(isLoading: false);
    }
  }
}

/// Provider for auth state
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});
