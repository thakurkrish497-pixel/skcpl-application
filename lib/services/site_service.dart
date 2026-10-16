import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/site_model.dart';

/// Handles construction site CRUD operations (admin-only)
class SiteService {
  final SupabaseClient _client;

  SiteService(this._client);

  /// Fetch all active sites
  Future<List<SiteModel>> getActiveSites() async {
    final data = await _client
        .from('sites')
        .select()
        .eq('is_active', true)
        .order('name');

    return (data as List).map((json) => SiteModel.fromJson(json)).toList();
  }

  /// Fetch all sites (including inactive, for admin)
  Future<List<SiteModel>> getAllSites() async {
    final data = await _client
        .from('sites')
        .select()
        .order('created_at', ascending: false);

    return (data as List).map((json) => SiteModel.fromJson(json)).toList();
  }

  /// Create a new construction site with login credentials
  Future<SiteModel> createSite({
    required String name,
    required String address,
    required String loginId,
    required String password,
    required String createdBy,
    double allocatedBudget = 0.0,
  }) async {
    final passwordHash = sha256.convert(utf8.encode(password)).toString();

    final data = await _client.from('sites').insert({
      'name': name,
      'address': address,
      'site_login_id': loginId,
      'site_password_hash': passwordHash,
      'created_by': createdBy,
      'allocated_budget': allocatedBudget,
    }).select().single();

    return SiteModel.fromJson(data);
  }

  /// Update a site's details
  Future<SiteModel> updateSite(String id, Map<String, dynamic> updates) async {
    // If updating password, hash it
    if (updates.containsKey('password')) {
      updates['site_password_hash'] =
          sha256.convert(utf8.encode(updates.remove('password'))).toString();
    }

    final data = await _client
        .from('sites')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return SiteModel.fromJson(data);
  }

  /// Soft-delete a site (set inactive)
  Future<void> deactivateSite(String id) async {
    await _client.from('sites').update({'is_active': false}).eq('id', id);
  }

  /// Reactivate a site
  Future<void> activateSite(String id) async {
    await _client.from('sites').update({'is_active': true}).eq('id', id);
  }

  /// Permanently delete a site (use with caution)
  Future<void> deleteSite(String id) async {
    await _client.from('sites').delete().eq('id', id);
  }
}
