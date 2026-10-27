import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site_model.dart';
import '../services/site_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';

/// Provides the SiteService
final siteServiceProvider = Provider<SiteService>((ref) {
  return SiteService(ref.read(supabaseServiceClientProvider));
});

/// Provider for the list of active sites (with offline caching)
final activeSitesProvider = FutureProvider<List<SiteModel>>((ref) async {
  final siteService = ref.read(siteServiceProvider);
  try {
    final sites = await siteService.getActiveSites();
    if (sites.isNotEmpty) {
      await OfflineService.cacheSites(sites);
    }
    return sites;
  } catch (e) {
    final cached = await OfflineService.getCachedSites();
    if (cached.isNotEmpty) {
      return cached;
    }
    rethrow;
  }
});

/// Provider for all sites (admin view, includes inactive)
final allSitesProvider = FutureProvider<List<SiteModel>>((ref) async {
  final siteService = ref.read(siteServiceProvider);
  return siteService.getAllSites();
});
