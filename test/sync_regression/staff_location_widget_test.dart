import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:skcpl_app/models/attendance_model.dart';
import 'package:skcpl_app/models/site_model.dart';
import 'package:skcpl_app/models/site_staff_model.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/providers/site_staff_provider.dart';
import 'package:skcpl_app/providers/attendance_provider.dart';
import 'package:skcpl_app/services/auth_service.dart';
import 'package:skcpl_app/services/attendance_service.dart';
import 'package:skcpl_app/services/location_service.dart';
import 'package:skcpl_app/widgets/staff_location_session.dart';
import 'attendance_location_test.dart' show fix;

final site = SiteModel(
    id: 's',
    name: 'Site',
    siteLoginId: 'site',
    createdAt: DateTime(2020),
    updatedAt: DateTime(2020));
final worker = SiteStaffModel(
    id: 'w',
    siteId: 's',
    name: 'Worker',
    role: SiteStaffRole.worker,
    pin: 'fixture',
    createdAt: DateTime(2020));

class FixedAuth extends AuthNotifier {
  FixedAuth(AuthState value) : super(AuthService()) {
    state = value;
  }
  @override
  Future<void> checkSession() async {}
}

class SelectedStaff extends ActiveStaffNotifier {
  SelectedStaff() : super() {
    state = worker;
  }
}

class GPS extends StaffLocationSource {
  final controller = StreamController<Position>.broadcast();
  int calls = 0;
  LocationFetchResult result;
  GPS(this.result);
  @override
  Future<LocationFetchResult> current() async {
    calls++;
    return result;
  }

  @override
  Stream<Position> get positions => controller.stream;
}

class LocationSink extends AttendanceService {
  final pings = <StaffLiveLocationModel>[];
  @override
  Future<SiteShiftPolicyModel> getShiftPolicy(String id) async =>
      SiteShiftPolicyModel(
          siteId: id, siteName: id, latitude: 22.7, longitude: 75.8);
  @override
  Future<void> updateLiveLocation(StaffLiveLocationModel p) async {
    pings.add(p);
  }
}

Future<void> mount(WidgetTester t, GPS gps, LocationSink sink,
    {UserRole? role, bool session = true}) async {
  final user = role == null
      ? null
      : UserModel(
          id: 'manager',
          email: 'fixture',
          role: role,
          createdAt: DateTime(2020),
          updatedAt: DateTime(2020));
  await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => FixedAuth(
            AuthState(user: user, activeSite: session ? site : null))),
        activeStaffProvider.overrideWith((ref) => SelectedStaff()),
        attendanceServiceProvider.overrideWithValue(sink),
        staffLocationSourceProvider.overrideWithValue(gps)
      ],
      child: MaterialApp(
          navigatorObservers: [staffLocationRoutes],
          home: StaffLocationSession(
              site: site,
              staff: worker,
              child:
                  const Scaffold(body: TextField(key: ValueKey('draft')))))));
  await t.pump();
  await t.pump();
  await t.pump();
}

Future<void> unmount(WidgetTester t, GPS gps) async {
  await t.pumpWidget(const SizedBox());
  await gps.controller.close();
  await t.pump();
}

void main() {
  for (final role in [
    UserRole.admin,
    UserRole.accounts,
    UserRole.projectHead
  ]) {
    testWidgets('$role cannot transmit own GPS under selected worker identity',
        (t) async {
      final gps = GPS(LocationFetchResult(position: fix(DateTime.now()))),
          sink = LocationSink();
      await mount(t, gps, sink, role: role);
      expect(gps.calls, 0);
      expect(sink.pings, isEmpty);
      await unmount(t, gps);
    });
  }
  testWidgets('Signed-out staff selection cannot publish locations', (t) async {
    final gps = GPS(LocationFetchResult(position: fix(DateTime.now()))),
        sink = LocationSink();
    await mount(t, gps, sink, session: false);
    expect(gps.calls, 0);
    await unmount(t, gps);
  });
  testWidgets(
      'Foreground fix preserves captured timestamp and stops in background/disposal',
      (t) async {
    final stamp = DateTime.now().subtract(const Duration(seconds: 5));
    final gps = GPS(LocationFetchResult(position: fix(stamp))),
        sink = LocationSink();
    await mount(t, gps, sink);
    expect(sink.pings.length, 1);
    expect(sink.pings.single.timestamp, stamp.toUtc());
    await t.enterText(find.byKey(const ValueKey('draft')), 'Unsaved progress');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    gps.controller.add(fix(DateTime.now()));
    await t.pump(const Duration(minutes: 2));
    expect(gps.calls, 1);
    expect(sink.pings.length, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(gps.calls, 2);
    expect(find.text('Unsaved progress'), findsOneWidget);
    await unmount(t, gps);
    await t.pump(const Duration(minutes: 2));
    expect(gps.calls, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'Permission refusal preserves report text and does not repeat prompts',
      (t) async {
    final gps = GPS(const LocationFetchResult(
            errorMessage: 'Location permission denied',
            isPermissionDenied: true)),
        sink = LocationSink();
    await mount(t, gps, sink);
    await t.enterText(find.byKey(const ValueKey('draft')), 'Draft not lost');
    await t.pump(const Duration(minutes: 5));
    expect(gps.calls, 1);
    expect(sink.pings, isEmpty);
    expect(find.text('Draft not lost'), findsOneWidget);
    expect(find.text('Location permission denied'), findsOneWidget);
    await unmount(t, gps);
  });
  testWidgets('Covering report route pauses GPS; returning resumes it',
      (t) async {
    final gps = GPS(LocationFetchResult(position: fix(DateTime.now()))),
        sink = LocationSink();
    await mount(t, gps, sink);
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await t.pumpAndSettle();
    await t.pump(const Duration(minutes: 2));
    expect(gps.calls, 1);
    nav.pop();
    await t.pumpAndSettle();
    expect(gps.calls, 2);
    await unmount(t, gps);
  });
}
