import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/stock_transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/offline_indicator.dart';
import '../../widgets/photo_thumbnail_strip.dart';
import '../../widgets/cache_manager_dialog.dart';
import '../../providers/cash_provider.dart';
import '../../services/excel_service.dart';
import 'add_product_screen.dart';
import 'use_product_screen.dart';

/// History of stock submissions for the active site
class StockHistoryScreen extends ConsumerStatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  ConsumerState<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends ConsumerState<StockHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Load transactions for active site
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final siteId = ref.read(authProvider).activeSite?.id;
      if (siteId != null) {
        ref.read(stockProvider.notifier).loadTransactions(siteId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Stock History'),
        actions: [
          if (ref.watch(authProvider).isAdmin || ref.watch(authProvider).isAccounts)
            IconButton(
              icon: const Icon(Icons.table_view_rounded, color: Color(0xFF107C41)),
              tooltip: 'Export Excel Workbook (.xlsx)',
              onPressed: () async {
                final activeSite = ref.read(authProvider).activeSite;
                if (activeSite == null) return;
                try {
                  var cashList = ref.read(cashProvider).transactions;
                  if (cashList.isEmpty) {
                    await ref.read(cashProvider.notifier).loadTransactions(activeSite.id);
                    cashList = ref.read(cashProvider).transactions;
                  }
                  await ExcelService.exportAndShareComprehensiveExcel(
                    siteName: activeSite.name,
                    siteId: activeSite.id,
                    cashTransactions: cashList,
                    stockTransactions: stockState.transactions,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Comprehensive Excel (Cash & Stock) exported!'),
                        backgroundColor: Color(0xFF107C41),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Export failed: $e'),
                        backgroundColor: AppColors.rejected,
                      ),
                    );
                  }
                }
              },
            ),
          const CacheActionButton(),
          const OfflineSyncButton(),
        ],
      ),
      body: stockState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : stockState.transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: AppColors.textTertiary, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'No Submissions Yet',
                        style: AppTextStyles.h3
                            .copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your stock entries will appear here',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: stockState.transactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final tx = stockState.transactions[index];
                    return InkWell(
                      onTap: () {
                        if (tx.isEditable || ref.read(authProvider).isAdmin) {
                          if (tx.type == TransactionType.inbound) {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AddProductScreen(existingTransaction: tx),
                            )).then((didUpdate) {
                              if (didUpdate == true) {
                                ref.read(stockProvider.notifier).loadTransactions(ref.read(authProvider).activeSite!.id);
                              }
                            });
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => UseProductScreen(existingTransaction: tx),
                            )).then((didUpdate) {
                              if (didUpdate == true) {
                                ref.read(stockProvider.notifier).loadTransactions(ref.read(authProvider).activeSite!.id);
                              }
                            });
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('This submission has been reviewed and is locked.')),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: _TransactionTile(transaction: tx),
                    );
                  },
                ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final StockTransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isInbound = transaction.type == TransactionType.inbound;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isInbound
                      ? AppColors.approvedSurface
                      : AppColors.pendingSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isInbound ? '↓ IN' : '↑ OUT',
                  style: AppTextStyles.caption.copyWith(
                    color: isInbound ? AppColors.approved : AppColors.pending,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('dd MMM yyyy').format(transaction.date),
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              if (transaction.status == TransactionStatus.approved && transaction.approvedAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Approved ${DateFormat('dd MMM hh:mm a').format(transaction.approvedAt!)}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.approved),
                  ),
                ),
              StatusBadge(
                status: transaction.status,
                compact: true,
                isOffline: transaction.id?.startsWith('offline_') ?? false,
              ),
              if (transaction.isEditable) ...[
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${transaction.displayProductName}: ${transaction.quantity} ${transaction.displayMetricUnitName}',
            style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
          ),
          if (transaction.billNo != null || (isInbound && transaction.displayVendorName != 'None'))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (isInbound && transaction.displayVendorName != 'None')
                    Text(
                      'Party / Vendor: ${transaction.displayVendorName}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  if (transaction.billNo != null && transaction.billNo!.isNotEmpty)
                    Text(
                      'Bill: #${transaction.billNo!}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          if (isInbound && transaction.finalAmount != null)
            Text(
              '₹ ${NumberFormat('#,##,###.##').format(transaction.finalAmount)}',
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.primary),
            ),
          if (transaction.submitterName != null || transaction.supervisorReviewNote != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (transaction.submitterName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 11, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'By: ${transaction.submitterName}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (transaction.supervisorReviewNote != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_outlined, size: 11, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          transaction.supervisorReviewNote!,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (transaction.cleanRemarks != null &&
              transaction.cleanRemarks!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              transaction.cleanRemarks!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (transaction.status == TransactionStatus.rejected && 
              transaction.rejectionNote != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rejectedSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.rejected),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejected: ${transaction.rejectionNote!}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.rejected),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (transaction.photoUrls.isNotEmpty)
            PhotoThumbnailStrip(photoUrls: transaction.photoUrls),
        ],
      ),
    );
  }
}
