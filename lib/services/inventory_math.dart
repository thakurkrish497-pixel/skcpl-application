import '../models/stock_transaction_model.dart';

String inventoryKey(StockTransactionModel tx) =>
    '${tx.siteId}|${tx.productId}|${tx.metricUnitId}|${tx.customProduct?.trim().toLowerCase() ?? ''}|${tx.customMetricUnit?.trim().toLowerCase() ?? ''}';

void requireFiniteAmount(num value, String field, {bool positive = false}) {
  if (!value.isFinite || (positive ? value <= 0 : value < 0)) {
    throw ArgumentError(
        '$field must be a finite ${positive ? "positive" : "non-negative"} number.');
  }
}

/// Preserve material AND unit identities, including the legacy manual-entry tags.
List<Map<String, dynamic>> calculateStockBalances(
    Iterable<StockTransactionModel> transactions) {
  final groups = <String, Map<String, dynamic>>{};
  for (final tx in transactions) {
    if (tx.status != TransactionStatus.approved) continue;
    requireFiniteAmount(tx.quantity, 'Stored stock quantity');
    final row = groups.putIfAbsent(
        inventoryKey(tx),
        () => {
              'site_id': tx.siteId,
              'site_name': tx.siteName ?? '',
              'product_id': tx.productId,
              'metric_unit_id': tx.metricUnitId,
              'inventory_key': inventoryKey(tx),
              'product_name': tx.displayProductName,
              'metric_unit': tx.displayMetricUnitName,
              'total_inbound': 0.0,
              'total_outbound': 0.0,
              'current_stock': 0.0,
            });
    final field =
        tx.type == TransactionType.inbound ? 'total_inbound' : 'total_outbound';
    row[field] = (row[field] as double) + tx.quantity;
    requireFiniteAmount(row[field] as double, 'Total stock quantity');
    row['current_stock'] =
        (row['total_inbound'] as double) - (row['total_outbound'] as double);
    row['is_negative'] = (row['current_stock'] as double) < 0;
  }
  return groups.values.toList();
}

double? parseFiniteNumber(String text) {
  final number = double.tryParse(text);
  return number != null && number.isFinite ? number : null;
}
