import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dropdown_item_model.dart';

/// Handles admin-managed dropdown values
class DropdownService {
  final SupabaseClient _client;

  DropdownService(this._client);

  Future<List<DropdownItemModel>> getByCategory(DropdownCategory category, {String? siteId}) async {
    var query = _client
        .from('dropdowns')
        .select()
        .eq('category', category.dbValue)
        .eq('is_active', true);
        
    if (siteId != null) {
      query = query.eq('site_id', siteId);
    } else {
      query = query.isFilter('site_id', null);
    }
    
    final data = await query.order('sort_order');

    return (data as List)
        .map((json) => DropdownItemModel.fromJson(json))
        .toList();
  }

  Future<List<DropdownItemModel>> getAllByCategory(
      DropdownCategory category, {String? siteId}) async {
    var query = _client
        .from('dropdowns')
        .select()
        .eq('category', category.dbValue);
        
    if (siteId != null) {
      query = query.eq('site_id', siteId);
    } else {
      query = query.isFilter('site_id', null);
    }

    final data = await query.order('sort_order');

    return (data as List)
        .map((json) => DropdownItemModel.fromJson(json))
        .toList();
  }

  Future<DropdownItemModel> addDropdown({
    required DropdownCategory category,
    required String value,
    String? siteId,
    Map<String, dynamic> metadata = const {},
    int sortOrder = 0,
  }) async {
    final data = await _client.from('dropdowns').insert({
      'site_id': siteId,
      'category': category.dbValue,
      'value': value,
      'metadata': metadata,
      'sort_order': sortOrder,
    }).select().single();

    return DropdownItemModel.fromJson(data);
  }

  /// Update a dropdown item
  Future<DropdownItemModel> updateDropdown(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final data = await _client
        .from('dropdowns')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return DropdownItemModel.fromJson(data);
  }

  /// Toggle active status of a dropdown item
  Future<void> toggleActive(String id, bool isActive) async {
    await _client
        .from('dropdowns')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Delete a dropdown item
  Future<void> deleteDropdown(String id) async {
    await _client.from('dropdowns').delete().eq('id', id);
  }
}
