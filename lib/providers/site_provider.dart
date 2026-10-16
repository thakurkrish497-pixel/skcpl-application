import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site_model.dart';
import '../services/site_service.dart';
import 'auth_provider.dart';

/// Provides the SiteService
final siteServiceProvider = Provider<SiteService>((ref) {
  return SiteService(ref.read(supabaseClientProvider));
});

/// Provider for the list of active sites
final activeSitesProvider = FutureProvider<List<SiteModel>>((ref) async {
  final siteService = ref.read(siteServiceProvider);
  return siteService.getActiveSites();
});

/// Provider for all sites (admin view, includes inactive)
final allSitesProvider = FutureProvider<List<SiteModel>>((ref) async {
  final siteService = ref.read(siteServiceProvider);
  return siteService.getAllSites();
});
