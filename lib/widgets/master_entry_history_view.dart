import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../models/cash_transaction_model.dart';
import '../models/stock_transaction_model.dart';
import '../providers/cash_provider.dart';
import '../providers/stock_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/photo_thumbnail_strip.dart';
import '../screens/accounts/transaction_review_screen.dart';

enum HistoryFilterStatus { all, pending, approved, rejected }

enum HistoryEntryType { all, cash, stock, stockIn, stockOut }

/// Comprehensive Master Entry History View for Accounts & Project Head
class MasterEntryHistoryView extends ConsumerStatefulWidget {
  final String selectedSiteId;

  const MasterEntryHistoryView({
    super.key,
    required this.selectedSiteId,
  });

  @override
  ConsumerState<MasterEntryHistoryView> createState() =>
      _MasterEntryHistoryViewState();
}

class _MasterEntryHistoryViewState
    extends ConsumerState<MasterEntryHistoryView> {
  HistoryFilterStatus _statusFilter = HistoryFilterStatus.all;
  HistoryEntryType _typeFilter = HistoryEntryType.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashState = ref.watch(cashProvider);
    final stockState = ref.watch(stockProvider);
    final currencyFmt =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final query = _searchController.text.trim().toLowerCase();

    // 1. Filter Cash Transactions
    var cashList = cashState.transactions.where((c) {
      if (widget.selectedSiteId != 'all' && c.siteId != widget.selectedSiteId) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.pending &&
          c.status != TransactionStatus.pendingAccounts &&
          c.status != TransactionStatus.pendingAdmin) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.approved &&
          c.status != TransactionStatus.approved) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.rejected &&
          c.status != TransactionStatus.rejected) {
        return false;
      }
      if (query.isNotEmpty) {
        final remarks = (c.remarks ?? '').toLowerCase();
        final party = (c.partyName ?? '').toLowerCase();
        final bill = (c.billNo ?? '').toLowerCase();
        final head = c.displayExpenseTypeName.toLowerCase();
        if (!remarks.contains(query) &&
            !party.contains(query) &&
            !bill.contains(query) &&
            !head.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    // 2. Filter Stock Transactions
    var stockList = stockState.transactions.where((s) {
      if (widget.selectedSiteId != 'all' && s.siteId != widget.selectedSiteId) {
        return false;
      }
      if (_typeFilter == HistoryEntryType.stockIn &&
          s.type != TransactionType.inbound) {
        return false;
      }
      if (_typeFilter == HistoryEntryType.stockOut &&
          s.type != TransactionType.outbound) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.pending &&
          s.status != TransactionStatus.pendingAccounts &&
          s.status != TransactionStatus.pendingAdmin) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.approved &&
          s.status != TransactionStatus.approved) {
        return false;
      }
      if (_statusFilter == HistoryFilterStatus.rejected &&
          s.status != TransactionStatus.rejected) {
        return false;
      }
      if (query.isNotEmpty) {
        final remarks = (s.remarks ?? '').toLowerCase();
        final vendor = s.displayVendorName.toLowerCase();
        final bill = (s.billNo ?? '').toLowerCase();
        final prod = s.displayProductName.toLowerCase();
        if (!remarks.contains(query) &&
            !vendor.contains(query) &&
            !bill.contains(query) &&
            !prod.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        if (cashState.error != null || stockState.error != null)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                  'Refresh failed. Showing previously loaded entries; use Sync & Refresh.',
                  style: TextStyle(color: AppColors.pending))),
        if (cashState.isLoading || stockState.isLoading)
          const LinearProgressIndicator(),
        // ── Controls: Search Bar & Filters ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.surfaceDark,
          child: Column(
            children: [
              // Search Field
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search by bill, party, material, or remarks...',
                  hintStyle: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppColors.waveCyan),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              size: 16, color: AppColors.textTertiary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.cardDark,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Filter Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Status filters
                    _buildStatusChip('All Status', HistoryFilterStatus.all),
                    const SizedBox(width: 6),
                    _buildStatusChip('Pending', HistoryFilterStatus.pending,
                        color: AppColors.pending),
                    const SizedBox(width: 6),
                    _buildStatusChip('Approved', HistoryFilterStatus.approved,
                        color: AppColors.approved),
                    const SizedBox(width: 6),
                    _buildStatusChip('Rejected', HistoryFilterStatus.rejected,
                        color: AppColors.rejected),
                    const SizedBox(width: 14),
                    Container(height: 18, width: 1, color: AppColors.divider),
                    const SizedBox(width: 14),

                    // Type filters
                    _buildTypeChip('All Types', HistoryEntryType.all),
                    const SizedBox(width: 6),
                    _buildTypeChip('Cash Only', HistoryEntryType.cash,
                        icon: Icons.payments_outlined),
                    const SizedBox(width: 6),
                    _buildTypeChip('All Stock', HistoryEntryType.stock,
                        icon: Icons.inventory_2_outlined),
                    const SizedBox(width: 6),
                    _buildTypeChip(
                        'Stock IN (Inbound)', HistoryEntryType.stockIn,
                        icon: Icons.arrow_downward_rounded),
                    const SizedBox(width: 6),
                    _buildTypeChip(
                        'Stock OUT (Usage)', HistoryEntryType.stockOut,
                        icon: Icons.arrow_upward_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── List of Transactions ──
        Expanded(
          child: _typeFilter == HistoryEntryType.cash
              ? _buildCashListView(cashList, currencyFmt)
              : (_typeFilter == HistoryEntryType.stock ||
                      _typeFilter == HistoryEntryType.stockIn ||
                      _typeFilter == HistoryEntryType.stockOut)
                  ? _buildStockListView(stockList, currencyFmt)
                  : _buildCombinedListView(cashList, stockList, currencyFmt),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, HistoryFilterStatus status,
      {Color? color}) {
    final isSelected = _statusFilter == status;
    final activeColor = color ?? AppColors.waveCyan;

    return InkWell(
      onTap: () => setState(() => _statusFilter = status),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.2)
              : AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.divider,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeColor : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, HistoryEntryType type, {IconData? icon}) {
    final isSelected = _typeFilter == type;

    return InkWell(
      onTap: () => setState(() => _typeFilter = type),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.waveCyan.withValues(alpha: 0.2)
              : AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.waveCyan : AppColors.divider,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 12,
                  color:
                      isSelected ? AppColors.waveCyan : AppColors.textTertiary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? AppColors.waveCyan : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashListView(List<CashTransactionModel> list, NumberFormat fmt) {
    if (list.isEmpty) return _emptyState('No Cash Entries Found');

    final sorted = [
      ...list
    ]..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) => _buildCashTile(sorted[idx], fmt),
    );
  }

  Widget _buildStockListView(
      List<StockTransactionModel> list, NumberFormat fmt) {
    if (list.isEmpty) return _emptyState('No Stock Entries Found');

    final sorted = [
      ...list
    ]..sort((a, b) => (b.createdAt ?? b.date).compareTo(a.createdAt ?? a.date));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) => _buildStockTile(sorted[idx], fmt),
    );
  }

  Widget _buildCombinedListView(
    List<CashTransactionModel> cashList,
    List<StockTransactionModel> stockList,
    NumberFormat fmt,
  ) {
    final combined = <dynamic>[...cashList, ...stockList];
    if (combined.isEmpty) return _emptyState('No Transactions Found');

    combined.sort((a, b) {
      final dateA = a is CashTransactionModel
          ? (a.createdAt ?? a.date)
          : (a as StockTransactionModel).createdAt ?? a.date;
      final dateB = b is CashTransactionModel
          ? (b.createdAt ?? b.date)
          : (b as StockTransactionModel).createdAt ?? b.date;
      return dateB.compareTo(dateA);
    });

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: combined.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final item = combined[idx];
        if (item is CashTransactionModel) {
          return _buildCashTile(item, fmt);
        } else {
          return _buildStockTile(item as StockTransactionModel, fmt);
        }
      },
    );
  }

  Widget _buildCashTile(CashTransactionModel tx, NumberFormat fmt) {
    final isExpense = tx.expenseAmount > 0;
    final amount = isExpense ? tx.expenseAmount : tx.amountReceived;
    final dateStr = DateFormat('dd MMM yyyy').format(tx.date);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isExpense ? AppColors.pending : AppColors.approved)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isExpense
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: isExpense ? AppColors.pending : AppColors.approved,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    tx.displayExpenseTypeName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${isExpense ? '-' : '+'}${fmt.format(amount)}',
                  style: TextStyle(
                    color: isExpense ? AppColors.pending : AppColors.approved,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(dateStr,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 11)),
                    if (tx.partyName != null) ...[
                      const Text(' • ',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      Expanded(
                        child: Text(
                          tx.partyName!,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    StatusBadge(status: tx.status, compact: true),
                  ],
                ),
                if (tx.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  PhotoThumbnailStrip(photoUrls: tx.photoUrls, size: 44),
                ],
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionReviewScreen(cashTransaction: tx),
                ),
              );
            },
          )),
    );
  }

  Widget _buildStockTile(StockTransactionModel tx, NumberFormat fmt) {
    final isInbound = tx.type == TransactionType.inbound;
    final dateStr = DateFormat('dd MMM yyyy').format(tx.date);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isInbound ? AppColors.waveCyan : AppColors.goldAccent)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isInbound ? Icons.inventory_2_rounded : Icons.outbox_rounded,
                size: 16,
                color: isInbound ? AppColors.waveCyan : AppColors.goldAccent,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${tx.type.displayName}: ${tx.displayProductName}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${tx.quantity} ${tx.displayMetricUnitName}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(dateStr,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 11)),
                    if (tx.displayVendorName != 'None') ...[
                      const Text(' • ',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      Expanded(
                        child: Text(
                          tx.displayVendorName,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    StatusBadge(status: tx.status, compact: true),
                  ],
                ),
                if (tx.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  PhotoThumbnailStrip(photoUrls: tx.photoUrls, size: 44),
                ],
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionReviewScreen(stockTransaction: tx),
                ),
              );
            },
          )),
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(text,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
