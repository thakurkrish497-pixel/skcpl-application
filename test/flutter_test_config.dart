import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/erp_test_backend.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError(
      'Real network access is disabled in the test suite. Inject a fake HTTP client.');
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => true);
  GoogleFonts.config.allowRuntimeFetching = false;
  for (final family in ['Outfit', 'Inter']) {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
    await loader.load();
  }
  for (final (family, asset) in [
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    (
      'packages/cupertino_icons/CupertinoIcons',
      'packages/cupertino_icons/assets/CupertinoIcons.ttf'
    )
  ]) {
    final loader = FontLoader(family)..addFont(rootBundle.load(asset));
    await loader.load();
  }
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = _NoNetwork();
  final backend = ErpTestBackend.instance;
  await Supabase.initialize(
      url: 'http://erp.test.invalid',
      publishableKey: 'fixture-public-key',
      httpClient: backend.client,
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage()));
  setUp(() async {
    backend.reset();
    SharedPreferences.setMockInitialValues({});
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'admin@skcpl.com', password: 'fixture-password');
  });
  await http.runWithClient(() async {
    await testMain();
  }, () => backend.client);
}
