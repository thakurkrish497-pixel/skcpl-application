import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../services/auto_sync_engine.dart';
import '../providers/site_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/auth_provider.dart';

/// Universal Cloud Sync & Refresh button designed for AppBars across all screens
class UniversalSyncButton extends ConsumerWidget {
  final String? siteId;

  const UniversalSyncButton({super.key, this.siteId});

  Future<void> _handleRefresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    
    // 1. Flush any queued offline transactions to Supabase
    final syncResult = await ref.read(autoSyncProvider.notifier).syncNow();

    // 2. Invalidate and re-fetch fresh server data
    ref.invalidate(activeSitesProvider);
    ref.invalidate(allSitesProvider);

    final activeSiteId = siteId ?? ref.read(authProvider).activeSite?.id;
    if (activeSiteId != null) {
      await Future.wait([
        ref.read(cashProvider.notifier).loadTransactions(activeSiteId),
        ref.read(stockProvider.notifier).loadTransactions(activeSiteId),
      ]);
    } else {
      await Future.wait([
        ref.read(cashProvider.notifier).loadAllTransactions(),
        ref.read(stockProvider.notifier).loadAllTransactions(),
      ]);
    }

    if (context.mounted) {
      if (syncResult.syncedCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('✅ Synced ${syncResult.syncedCount} offline record(s) to Cloud & refreshed!'),
            backgroundColor: AppColors.approved,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (syncResult.remainingCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('⚠️ ${syncResult.remainingCount} record(s) pending sync. Checking connection...'),
            backgroundColor: AppColors.pending,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('☁️ Cloud Synced & Up to Date!'),
            backgroundColor: AppColors.waveCyan,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(autoSyncProvider);

    if (syncState.isSyncing) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.pending.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.pending.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pending),
            ),
            SizedBox(width: 6),
            Text('Syncing...', style: TextStyle(color: AppColors.pending, fontSize: 12)),
          ],
        ),
      );
    }

    if (syncState.pendingCount > 0) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          backgroundColor: AppColors.pending.withValues(alpha: 0.2),
          side: const BorderSide(color: AppColors.pending, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          avatar: const Icon(Icons.cloud_upload_rounded, color: AppColors.pending, size: 16),
          label: Text(
            'Sync (${syncState.pendingCount})',
            style: const TextStyle(color: AppColors.pending, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          onPressed: () => _handleRefresh(context, ref),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.sync_rounded, color: AppColors.waveCyan),
      tooltip: 'Sync & Refresh Cloud Data',
      onPressed: () => _handleRefresh(context, ref),
    );
  }
}
