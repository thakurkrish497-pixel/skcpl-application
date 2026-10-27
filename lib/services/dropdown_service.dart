import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dropdown_item_model.dart';

/// Handles admin-managed dropdown values
class DropdownService {
  final SupabaseClient _client;

  DropdownService(this._client);

  static const Map<DropdownCategory, List<String>> defaultTemplates = {
    DropdownCategory.vendor: [
      'ABC Suppliers',
      'XYZ Traders',
      'Metro Building Materials',
      'Local Hardware Depot',
      'Brick Kiln Depot',
      'National Cement & Steel Agency',
    ],
    DropdownCategory.product: [
      'Cement (OPC 53)',
      'TMT Steel Bars (12mm)',
      'TMT Steel Bars (16mm)',
      'Sand (River Sand)',
      'Bricks (Red Clay)',
      'Aggregate (20mm)',
      'Aggregate (10mm)',
      'Stone Dust',
      'Binding Wire',
      'Exterior Paint',
    ],
    DropdownCategory.metricUnit: [
      'Bags',
      'Tonnes (MT)',
      'Kg',
      'Cubic Feet (cft)',
      'Pieces (Nos)',
      'Trips / Brass',
      'Litres',
    ],
    DropdownCategory.expenseType: [
      'Labour Wages',
      'Diesel & Fuel',
      'Food & Refreshments',
      'Transportation & Freight',
      'Hardware & Consumables',
      'Equipment Rental & Repair',
      'Site Maintenance',
      'Miscellaneous Expense',
    ],
  };

  // System placeholder IDs for manual/unregistered entries to satisfy DB foreign keys
  static const String otherProductPlaceholderId = 'f76c5ffc-b910-4886-aee2-ac25dc43b529';
  static const String otherUnitPlaceholderId = '4f5963cf-e4e6-44a4-92b5-5fe39ba1c145';
  static const String otherExpensePlaceholderId = 'e72d9d18-2a33-4748-a04f-ddfdc9504a3f';
  static const String otherVendorPlaceholderId = 'bb8598d0-1640-472d-8ff3-65a02b702cb1';

  /// Get active items for form dropdowns. If a site has items, return those.
  /// If the site has no items configured yet, fall back to global templates.
  Future<List<DropdownItemModel>> getByCategory(DropdownCategory category,
      {String? siteId}) async {
    List<DropdownItemModel> results = [];

    if (siteId != null) {
      final siteData = await _client
          .from('dropdowns')
          .select()
          .eq('category', category.dbValue)
          .eq('is_active', true)
          .eq('site_id', siteId)
          .order('sort_order');

      final siteItems = (siteData as List)
          .map((json) => DropdownItemModel.fromJson(json))
          .toList();

      if (siteItems.isNotEmpty) {
        results = siteItems;
      }
    }

    if (results.isEmpty) {
      // Fallback to global templates if site has no custom dropdowns yet
      final globalData = await _client
          .from('dropdowns')
          .select()
          .eq('category', category.dbValue)
          .eq('is_active', true)
          .isFilter('site_id', null)
          .order('sort_order');

      results = (globalData as List)
          .map((json) => DropdownItemModel.fromJson(json))
          .toList();
    }

    // Exclude system placeholder item from regular item lists
    return results
        .where((item) => !item.value.toLowerCase().startsWith('other (manual'))
        .toList();
  }

  /// Get all items (active and inactive) for admin management
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

    final items = (data as List)
        .map((json) => DropdownItemModel.fromJson(json))
        .toList();

    // Filter out system placeholder rows so Admin only manages actual items
    return items
        .where((item) => !item.value.toLowerCase().startsWith('other (manual'))
        .toList();
  }

  /// Add a new dropdown item
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

  /// Delete a dropdown item with foreign key safety
  Future<void> deleteDropdown(String id) async {
    try {
      await _client.from('dropdowns').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw 'This item is already referenced in past transactions and cannot be deleted. You can deactivate it instead.';
      }
      rethrow;
    }
  }

  /// Seed all standard construction dropdowns for a newly created or unconfigured site
  Future<void> seedDefaultDropdownsForSite(
    String siteId, {
    List<String>? initialVendors,
    List<String>? initialProducts,
    List<String>? initialExpenseTypes,
  }) async {
    // Collect all existing values for this site to prevent duplicate errors
    final existingData = await _client
        .from('dropdowns')
        .select('category, value')
        .eq('site_id', siteId);

    final existingSet = <String>{};
    for (final row in (existingData as List)) {
      existingSet.add('${row['category']}:${row['value'].toString().toLowerCase().trim()}');
    }

    final rowsToInsert = <Map<String, dynamic>>[];

    // 1. Vendors
    final vendors = [
      ...defaultTemplates[DropdownCategory.vendor]!,
      if (initialVendors != null) ...initialVendors,
    ];
    int vOrder = 1;
    for (final v in vendors) {
      final trimmed = v.trim();
      final key = '${DropdownCategory.vendor.dbValue}:${trimmed.toLowerCase()}';
      if (trimmed.isNotEmpty && !existingSet.contains(key)) {
        existingSet.add(key);
        rowsToInsert.add({
          'site_id': siteId,
          'category': DropdownCategory.vendor.dbValue,
          'value': trimmed,
          'sort_order': vOrder++,
          'is_active': true,
        });
      }
    }

    // 2. Products
    final products = [
      ...defaultTemplates[DropdownCategory.product]!,
      if (initialProducts != null) ...initialProducts,
    ];
    int pOrder = 1;
    for (final p in products) {
      final trimmed = p.trim();
      final key = '${DropdownCategory.product.dbValue}:${trimmed.toLowerCase()}';
      if (trimmed.isNotEmpty && !existingSet.contains(key)) {
        existingSet.add(key);
        rowsToInsert.add({
          'site_id': siteId,
          'category': DropdownCategory.product.dbValue,
          'value': trimmed,
          'sort_order': pOrder++,
          'is_active': true,
        });
      }
    }

    // 3. Metric Units
    int uOrder = 1;
    for (final u in defaultTemplates[DropdownCategory.metricUnit]!) {
      final trimmed = u.trim();
      final key = '${DropdownCategory.metricUnit.dbValue}:${trimmed.toLowerCase()}';
      if (trimmed.isNotEmpty && !existingSet.contains(key)) {
        existingSet.add(key);
        rowsToInsert.add({
          'site_id': siteId,
          'category': DropdownCategory.metricUnit.dbValue,
          'value': trimmed,
          'sort_order': uOrder++,
          'is_active': true,
        });
      }
    }

    // 4. Expense Types
    final expenseTypes = [
      ...defaultTemplates[DropdownCategory.expenseType]!,
      if (initialExpenseTypes != null) ...initialExpenseTypes,
    ];
    int eOrder = 1;
    for (final e in expenseTypes) {
      final trimmed = e.trim();
      final key = '${DropdownCategory.expenseType.dbValue}:${trimmed.toLowerCase()}';
      if (trimmed.isNotEmpty && !existingSet.contains(key)) {
        existingSet.add(key);
        rowsToInsert.add({
          'site_id': siteId,
          'category': DropdownCategory.expenseType.dbValue,
          'value': trimmed,
          'sort_order': eOrder++,
          'is_active': true,
        });
      }
    }

    if (rowsToInsert.isNotEmpty) {
      await _client.from('dropdowns').insert(rowsToInsert);
    }
  }

  /// Seed defaults for a specific category into a site (e.g., if user taps "Import Standard Vendors")
  Future<int> seedCategoryDefaultsForSite(
      String siteId, DropdownCategory category) async {
    final existingData = await _client
        .from('dropdowns')
        .select('value')
        .eq('site_id', siteId)
        .eq('category', category.dbValue);

    final existingValues = (existingData as List)
        .map((r) => r['value'].toString().toLowerCase().trim())
        .toSet();

    final defaults = defaultTemplates[category] ?? [];
    final toInsert = <Map<String, dynamic>>[];

    int order = existingValues.length + 1;
    for (final def in defaults) {
      final trimmed = def.trim();
      if (!existingValues.contains(trimmed.toLowerCase())) {
        toInsert.add({
          'site_id': siteId,
          'category': category.dbValue,
          'value': trimmed,
          'sort_order': order++,
          'is_active': true,
        });
      }
    }

    if (toInsert.isNotEmpty) {
      await _client.from('dropdowns').insert(toInsert);
    }

    return toInsert.length;
  }
}
