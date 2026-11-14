import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'widgets/role_gate.dart';
import 'screens/auth/role_login_screen.dart';
import 'screens/stock/stock_choice_screen.dart';
import 'screens/stock/add_product_screen.dart';
import 'screens/stock/use_product_screen.dart';
import 'screens/stock/stock_history_screen.dart';
import 'screens/cashbook/expense_form_screen.dart';
import 'screens/cashbook/cash_history_screen.dart';
import 'screens/accounts/accounts_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/manage_sites_screen.dart';
import 'screens/admin/admin_review_screen.dart';
import 'screens/admin/admin_cashflow_screen.dart';
import 'screens/admin/daily_site_reports_screen.dart';
import 'screens/site_reports/record_site_report_screen.dart';
import 'screens/tasks/task_list_screen.dart';
import 'screens/admin/admin_attendance_screen.dart';
import 'screens/attendance/punch_attendance_screen.dart';
import 'screens/admin/all_staff_management_screen.dart';
import 'screens/admin/role_access_management_screen.dart';
import 'screens/project_head/project_head_dashboard.dart';
import 'screens/admin/admin_backup_screen.dart';

Map<String, WidgetBuilder> buildAppRoutes() => {
      '/role-login': (context) => const RoleLoginScreen(),
      '/stock-choice': (context) => const StockChoiceScreen(),
      '/add-product': (context) => const AddProductScreen(),
      '/use-product': (context) => const UseProductScreen(),
      '/stock-history': (context) => const StockHistoryScreen(),
      '/expense-form': (context) => const ExpenseFormScreen(),
      '/cash-history': (context) => const CashHistoryScreen(),
      '/accounts-dashboard': (context) => const RoleGate(
          allowedRoles: [UserRole.accounts], child: AccountsDashboard()),
      '/admin-dashboard': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AdminDashboard()),
      '/manage-sites': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: ManageSitesScreen()),
      '/admin-review': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AdminReviewScreen()),
      '/admin-cashflow': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AdminCashflowScreen()),
      '/daily-site-reports': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: DailySiteReportsScreen()),
      '/site-report': (context) => const RecordSiteReportScreen(),
      '/tasks': (context) => const TaskListScreen(),
      '/admin-attendance': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AdminAttendanceScreen()),
      '/attendance-punch': (context) => const PunchAttendanceScreen(),
      '/admin-staff': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AllStaffManagementScreen()),
      '/project-head-dashboard': (context) => const RoleGate(
          allowedRoles: [UserRole.projectHead], child: ProjectHeadDashboard()),
      '/admin-role-access': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: RoleAccessManagementScreen()),
      '/admin-backup': (context) => const RoleGate(
          allowedRoles: [UserRole.admin], child: AdminBackupScreen()),
    };
