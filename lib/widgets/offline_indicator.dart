import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../providers/stock_provider.dart';
import '../providers/cash_provider.dart';
import '../services/offline_service.dart';

/// App Bar action or banner indicating offline queue status and offering 1-tap sync
class OfflineSyncButton extends ConsumerStatefulWidget {
  const OfflineSyncButton({super.key});

  @override
  ConsumerState<OfflineSyncButton> createState() => _OfflineSyncButtonState();
}

class _OfflineSyncButtonState extends ConsumerState<OfflineSyncButton> {
  int _pendingCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkPending();
  }

  Future<void> _checkPending() async {
    final count = await OfflineService.getPendingSyncCount();
    if (mounted) {
      setState(() => _pendingCount = count);
    }
  }

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final stockService = ref.read(stockServiceProvider);
    final cashService = ref.read(cashServiceProvider);

    final result = await OfflineService.syncAllQueued(
      stockService: stockService,
      cashService: cashService,
    );

    await _checkPending();
    if (mounted) {
      setState(() => _isSyncing = false);
      if (result.syncedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced ${result.syncedCount} offline record(s) to Supabase!'),
            backgroundColor: AppColors.approved,
          ),
        );
      } else if (result.hasRemaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.remainingCount} record(s) could not sync. Still offline?'),
            backgroundColor: AppColors.pending,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingCount == 0 && !_isSyncing) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: InkWell(
          onTap: _isSyncing ? null : _syncNow,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.pending.withOpacity(0.15),
              border: Border.all(color: AppColors.pending.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSyncing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.pending,
                    ),
                  )
                else
                  const Icon(Icons.cloud_upload_rounded, color: AppColors.pending, size: 16),
                const SizedBox(width: 6),
                Text(
                  _isSyncing ? 'Syncing...' : '$_pendingCount Offline',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.pending,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
