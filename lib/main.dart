import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/app_background_watermark.dart';

// Screens
import 'screens/home/home_screen.dart';
import 'screens/auth/role_login_screen.dart';
import 'screens/sites/site_list_screen.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: SKCPLApp(),
    ),
  );
}

class SKCPLApp extends ConsumerWidget {
  const SKCPLApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'SKCPL Construction Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: currentLocale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('hi', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Background company logo watermark across all screens & routes
      builder: (context, child) => AppBackgroundWatermark(
        child: child ?? const SizedBox(),
      ),

      // Entry point
      home: const HomeScreen(),

      // Named routes
      routes: {
        '/role-login': (context) => const RoleLoginScreen(),
        '/stock-choice': (context) => const StockChoiceScreen(),
        '/add-product': (context) => const AddProductScreen(),
        '/use-product': (context) => const UseProductScreen(),
        '/stock-history': (context) => const StockHistoryScreen(),
        '/expense-form': (context) => const ExpenseFormScreen(),
        '/cash-history': (context) => const CashHistoryScreen(),
        '/accounts-dashboard': (context) => const AccountsDashboard(),
        '/admin-dashboard': (context) => const AdminDashboard(),
        '/manage-sites': (context) => const ManageSitesScreen(),
        '/admin-review': (context) => const AdminReviewScreen(),
        '/admin-cashflow': (context) => const AdminCashflowScreen(),
        '/daily-site-reports': (context) => const DailySiteReportsScreen(),
        '/site-report': (context) => const RecordSiteReportScreen(),
        '/tasks': (context) => const TaskListScreen(),
        '/admin-attendance': (context) => const AdminAttendanceScreen(),
        '/attendance-punch': (context) => const PunchAttendanceScreen(),
        '/admin-staff': (context) => const AllStaffManagementScreen(),
        '/project-head-dashboard': (context) => const ProjectHeadDashboard(),
        '/admin-role-access': (context) => const RoleAccessManagementScreen(),
        '/admin-backup': (context) => const AdminBackupScreen(),
      },

      // Dynamic routes (for passing arguments)
      onGenerateRoute: (settings) {
        // Site list with module argument
        if (settings.name == '/sites') {
          final module = settings.arguments as String? ?? 'stock';
          return MaterialPageRoute(
            builder: (_) => SiteListScreen(module: module),
          );
        }
        return null;
      },
    );
  }
}
