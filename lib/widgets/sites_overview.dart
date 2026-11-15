import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../providers/site_provider.dart';
import '../screens/admin/site_details_screen.dart';

/// Shared site overview for Accounts and Project Head. Server role guards still
/// determine the permitted actions inside each site's screens.
class SitesOverview extends ConsumerWidget {
  const SitesOverview({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(activeSitesProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Error: $error'),
              TextButton(
                  onPressed: () => ref.invalidate(activeSitesProvider),
                  child: const Text('Retry sites'))
            ])),
            data: (sites) => RefreshIndicator(
                onRefresh: () async {
                  try {
                    await ref
                        .refresh(activeSitesProvider.future)
                        .then<void>((_) {});
                  } catch (_) {
                    // The provider displays the site loading error and retry action.
                  }
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: sites.isEmpty ? 1 : sites.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (sites.isEmpty) return const Text('No Sites Found');
                    if (index == 0) {
                      return Text('Select Site for Details',
                          style: AppTextStyles.h4);
                    }
                    final site = sites[index - 1];
                    return ListTile(
                        tileColor: AppColors.cardDark,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(
                                color: AppColors.divider, width: 0.5)),
                        title: Text(site.name, style: AppTextStyles.labelLarge),
                        subtitle: Text(site.address ?? 'No address provided',
                            style: AppTextStyles.bodySmall),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SiteDetailsScreen(site: site))));
                  },
                )),
          );
}
