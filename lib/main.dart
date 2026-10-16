import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_constants.dart';
import 'core/theme/app_theme.dart';

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
import 'screens/admin/manage_dropdowns_screen.dart';
import 'screens/admin/admin_review_screen.dart';
import 'screens/admin/admin_cashflow_screen.dart';
import 'screens/tasks/task_list_screen.dart';

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

class SKCPLApp extends StatelessWidget {
  const SKCPLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SKCPL Construction Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,

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
        '/manage-dropdowns': (context) => const ManageDropdownsScreen(),
        '/admin-review': (context) => const AdminReviewScreen(),
        '/admin-cashflow': (context) => const AdminCashflowScreen(),
        '/tasks': (context) => const TaskListScreen(),
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
