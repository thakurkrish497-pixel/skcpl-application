import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../services/cache_service.dart';

/// Modal dialog to inspect and clear app cache, image memory, and temporary data
class CacheManagerDialog extends StatefulWidget {
  const CacheManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CacheManagerDialog(),
    );
  }

  @override
  State<CacheManagerDialog> createState() => _CacheManagerDialogState();
}

class _CacheManagerDialogState extends State<CacheManagerDialog> {
  CacheStats? _stats;
  bool _isLoading = true;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final stats = await CacheService.getStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleClearImages() async {
    setState(() => _isClearing = true);
    CacheService.clearImageCache();
    await Future.delayed(const Duration(milliseconds: 300));
    await _loadStats();
    if (mounted) {
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image memory cache cleared! Device RAM freed.'),
          backgroundColor: AppColors.approved,
        ),
      );
    }
  }

  Future<void> _handleClearAll() async {
    setState(() => _isClearing = true);
    await CacheService.clearAllTemporaryData();
    await Future.delayed(const Duration(milliseconds: 300));
    await _loadStats();
    if (mounted) {
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All temporary caches cleared! App size reduced.'),
          backgroundColor: AppColors.approved,
        ),
      );
    }
  }

  Future<void> _handleClearOfflineQueues() async {
    setState(() => _isClearing = true);
    await CacheService.clearOfflineQueues();
    await Future.delayed(const Duration(milliseconds: 300));
    await _loadStats();
    if (mounted) {
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline pending queues cleared! Stuck requests removed.'),
          backgroundColor: AppColors.approved,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cleaning_services_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Storage & Cache Manager',
                      style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                    ),
                    Text(
                      'Decrease app memory footprint & clear loaded photos',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Stats cards
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.sd_card_rounded,
                    label: 'App Storage & RAM',
                    value: _stats!.formattedTotalSize,
                    subtext: '${_stats!.imageCount} in RAM • ${_stats!.formattedDiskSize} disk',
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    icon: Icons.cloud_sync_rounded,
                    label: 'Offline Queue',
                    value: '${_stats!.offlinePendingCount}',
                    subtext: _stats!.offlinePendingCount > 0 ? 'Pending sync' : 'All synced',
                    color: _stats!.offlinePendingCount > 0 ? AppColors.pending : AppColors.approved,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tip note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardDarkAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Photos are securely stored in the cloud. Clearing the cache purges local memory copies and decreases app footprint without losing any transaction records.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isClearing ? null : _handleClearImages,
                icon: const Icon(Icons.photo_filter_rounded, size: 20),
                label: Text(_isClearing ? 'Clearing...' : 'Clear Photo Memory Cache'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isClearing ? null : _handleClearAll,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                label: const Text('Clear All Temporary Cache & Menus'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isClearing ? null : _handleClearOfflineQueues,
                icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                label: const Text('Purge Stuck Offline Requests'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rejected,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtext, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Quick AppBar action button for cache management
class CacheActionButton extends StatelessWidget {
  const CacheActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.cleaning_services_outlined, size: 20),
      tooltip: 'Storage & Cache Manager',
      color: AppColors.textSecondary,
      onPressed: () => CacheManagerDialog.show(context),
    );
  }
}
