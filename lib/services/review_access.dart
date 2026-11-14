import '../models/stock_transaction_model.dart';
import '../models/user_model.dart';
import '../models/role_permissions_model.dart';

bool canReviewTransaction(
    {required UserRole? role,
    required TransactionStatus status,
    required bool stock,
    required bool pendingProjectHead,
    required bool queued,
    required RolePermissionsModel permissions}) {
  if (queued) return false;
  if (role == UserRole.admin) return status == TransactionStatus.pendingAdmin;
  if (role != UserRole.accounts ||
      status != TransactionStatus.pendingAccounts) {
    return false;
  }
  final allowed = stock
      ? permissions.accountsCanApproveStock
      : permissions.accountsCanApproveCash;
  final headRequired = stock
      ? permissions.projectHeadCanApproveStock
      : permissions.projectHeadCanApproveCash;
  return allowed && !(headRequired && pendingProjectHead);
}
