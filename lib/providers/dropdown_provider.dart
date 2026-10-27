import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dropdown_item_model.dart';
import '../services/dropdown_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';

/// Provides the DropdownService
final dropdownServiceProvider = Provider<DropdownService>((ref) {
  return DropdownService(ref.read(supabaseServiceClientProvider));
});

/// Parameters for fetching dropdowns
typedef DropdownParams = ({DropdownCategory category, String? siteId});

/// Provider for dropdown items by category (with offline caching)
/// Usage: ref.watch(dropdownProvider((category: DropdownCategory.vendor, siteId: '...')))
final dropdownProvider = FutureProvider.autoDispose.family<List<DropdownItemModel>,
    DropdownParams>((ref, params) async {
  final dropdownService = ref.read(dropdownServiceProvider);
  try {
    final items = await dropdownService.getByCategory(params.category, siteId: params.siteId);
    if (items.isNotEmpty) {
      await OfflineService.cacheDropdowns(params.category, params.siteId, items);
    }
    return items;
  } catch (e) {
    final cached = await OfflineService.getCachedDropdowns(params.category, params.siteId);
    if (cached.isNotEmpty) {
      return cached;
    }
    rethrow;
  }
});

/// Provider for all dropdown items (admin management, includes inactive)
final allDropdownsProvider = FutureProvider.autoDispose.family<List<DropdownItemModel>,
    DropdownParams>((ref, params) async {
  final dropdownService = ref.read(dropdownServiceProvider);
  return dropdownService.getAllByCategory(params.category, siteId: params.siteId);
});
