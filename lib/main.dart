import 'providers/attendance_session_refresh_provider.dart';
import 'widgets/attendance_day_host.dart';
import 'providers/live_location_feed_provider.dart';
import 'widgets/staff_location_session.dart';
import 'providers/shift_policy_sync_provider.dart';
import 'widgets/workflow_monitor_host.dart';
import 'services/workflow_navigation.dart';
import 'widgets/staff_reminder_host.dart';
import 'providers/notification_clock_provider.dart';
import 'providers/site_announcement_provider.dart';
import 'providers/role_access_provider.dart';
import 'app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/app_background_watermark.dart';
import 'services/auto_sync_engine.dart';
import 'services/realtime_sync_service.dart';

// Screens
import 'screens/home/home_screen.dart';
import 'screens/sites/site_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    publishableKey: SupabaseConstants.supabaseAnonKey,
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

    // Continuous 30s background auto-sync & live Realtime WebSockets across all devices
    ref.watch(autoSyncProvider);
    ref.watch(realtimeSyncProvider);
    ref.watch(managementSessionGuardProvider);
    ref.watch(noticeRealtimeProvider);
    ref.watch(notificationStartupProvider);
    ref.watch(shiftPolicySyncProvider);
    ref.watch(liveLocationFeedProvider);
    ref.watch(attendanceSessionRefreshProvider);

    return MaterialApp(
      navigatorKey: workflowNavigatorKey,
      navigatorObservers: [staffLocationRoutes],
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
        child: WorkflowMonitorHost(
            child: AttendanceDayHost(
                child: StaffReminderHost(child: child ?? const SizedBox()))),
      ),

      // Entry point
      home: const HomeScreen(),

      // Named routes
      routes: buildAppRoutes(),

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
