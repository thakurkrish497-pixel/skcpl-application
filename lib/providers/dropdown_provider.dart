import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dropdown_item_model.dart';
import '../services/dropdown_service.dart';
import 'auth_provider.dart';

/// Provides the DropdownService
final dropdownServiceProvider = Provider<DropdownService>((ref) {
  return DropdownService(ref.read(supabaseClientProvider));
});

/// Parameters for fetching dropdowns
typedef DropdownParams = ({DropdownCategory category, String? siteId});

/// Provider for dropdown items by category
/// Usage: ref.watch(dropdownProvider((category: DropdownCategory.vendor, siteId: '...')))
final dropdownProvider = FutureProvider.autoDispose.family<List<DropdownItemModel>,
    DropdownParams>((ref, params) async {
  final dropdownService = ref.read(dropdownServiceProvider);
  return dropdownService.getByCategory(params.category, siteId: params.siteId);
});

/// Provider for all dropdown items (admin management, includes inactive)
final allDropdownsProvider = FutureProvider.autoDispose.family<List<DropdownItemModel>,
    DropdownParams>((ref, params) async {
  final dropdownService = ref.read(dropdownServiceProvider);
  return dropdownService.getAllByCategory(params.category, siteId: params.siteId);
});
