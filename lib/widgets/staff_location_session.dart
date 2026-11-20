import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site_model.dart';
import '../models/site_staff_model.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../providers/auth_provider.dart';
import '../providers/site_staff_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/location_service.dart';
import '../services/staff_location_tracking.dart';
import '../services/shift_policy_resolver.dart';

final staffLocationRoutes = RouteObserver<ModalRoute<dynamic>>();

class StaffLocationSource {
  Future<LocationFetchResult> current() =>
      LocationService.getCurrentLocationDetailed();
  Stream<Position> get positions => LocationService.positionStream();
}

final staffLocationSourceProvider =
    Provider<StaffLocationSource>((ref) => StaffLocationSource());

class StaffLocationSession extends ConsumerStatefulWidget {
  final SiteModel? site;
  final SiteStaffModel? staff;
  final Widget child;
  final void Function(Position)? onPosition;
  const StaffLocationSession(
      {super.key, this.site, this.staff, required this.child, this.onPosition});
  @override
  ConsumerState<StaffLocationSession> createState() =>
      _StaffLocationSessionState();
}

class _StaffLocationSessionState extends ConsumerState<StaffLocationSession>
    with WidgetsBindingObserver, RouteAware {
  StreamSubscription<Position>? _positions;
  Timer? _heartbeat;
  StaffLocationTracking? _tracking;
  ModalRoute<dynamic>? _route;
  bool _visible = true, _foreground = true;
  int _generation = 0;
  String _status =
      'GPS is only shared while this attendance/report screen is in use.';
  String? _identity;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) staffLocationRoutes.unsubscribe(this);
      _route = route;
      if (route != null) staffLocationRoutes.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _visible = false;
    _stop();
  }

  @override
  void didPopNext() {
    _visible = true;
    _restart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _restart();
    } else {
      _stop();
    }
  }

  void _stop() {
    _generation++;
    _positions?.cancel();
    _positions = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _tracking?.dispose();
    _tracking = null;
  }

  void _restart() {
    if (!mounted) return;
    _stop();
    if (_identity == null || !_visible || !_foreground) return;
    final generation = _generation;
    final site = widget.site!, staff = widget.staff!;
    _tracking = StaffLocationTracking(publish: (fix) async {
      if (!mounted || generation != _generation) return;
      final service = ref.read(attendanceServiceProvider);
      final policy =
          await ref.read(shiftPolicyForSiteProvider(staff.siteId).future);
      if (!mounted || generation != _generation) return;
      final configured = policy.latitude != null && policy.longitude != null;
      final distance = configured
          ? LocationService.calculateDistanceMeters(
              userLat: fix.latitude,
              userLng: fix.longitude,
              siteLat: policy.latitude!,
              siteLng: policy.longitude!)
          : 0.0;
      await service.updateLiveLocation(StaffLiveLocationModel(
          staffId: staff.id,
          staffName: staff.name,
          staffRole: staff.role.displayName,
          siteId: staff.siteId,
          siteName: site.name,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMeters: fix.accuracy,
          isWithinSite: configured &&
              distance + fix.accuracy <= policy.allowedRadiusMeters,
          distanceMeters: distance,
          timestamp: fix.timestamp.toUtc()));
    });
    void sample(Position fix) {
      if (!mounted || generation != _generation) return;
      if (_tracking?.accept(fix) == true) {
        widget.onPosition?.call(fix);
        setState(() => _status =
            'GPS tracking active • accuracy ±${fix.accuracy.toStringAsFixed(0)}m');
      }
    }

    Future<void> current() async {
      try {
        final result = await ref.read(staffLocationSourceProvider).current();
        if (!mounted || generation != _generation) return;
        if (result.position != null) {
          sample(result.position!);
        } else {
          setState(() => _status = result.errorMessage ??
              'GPS is unavailable. Reports remain saved normally.');
          if (result.isPermissionDenied || result.isDeniedForever) {
            _heartbeat?.cancel();
            _heartbeat = null;
          }
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(
              () => _status = 'GPS is unavailable. Your report is unaffected.');
        }
      }
    }

    unawaited(current());
    try {
      _positions = ref
          .read(staffLocationSourceProvider)
          .positions
          .listen(sample, onError: (_) {
        if (mounted && generation == _generation) {
          setState(() =>
              _status = 'GPS updates paused; showing the last verified fix.');
        }
      });
    } catch (_) {/* Some desktops support current fixes only. */}
    _heartbeat =
        Timer.periodic(const Duration(minutes: 1), (_) => unawaited(current()));
  }

  @override
  void didUpdateWidget(covariant StaffLocationSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.staff?.id != widget.staff?.id ||
        oldWidget.staff?.siteId != widget.staff?.siteId ||
        oldWidget.site?.id != widget.site?.id) {
      _identity = null;
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    staffLocationRoutes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final selected = ref.watch(activeStaffProvider);
    final staff = widget.staff, site = widget.site;
    final workerSession = auth.user?.role == UserRole.worker ||
        (auth.user == null &&
            auth.activeSite != null &&
            shiftLocationKey(auth.activeSite!.id) ==
                shiftLocationKey(site?.id ?? ''));
    final allowed = workerSession &&
        staff != null &&
        site != null &&
        staff.isActive &&
        selected?.id == staff.id &&
        shiftLocationKey(staff.siteId) == shiftLocationKey(site.id);
    if (allowed) ref.watch(shiftPolicyForSiteProvider(staff.siteId));
    final identity = allowed ? '${staff.siteId}:${staff.id}' : null;
    if (identity != _identity) {
      _identity = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restart();
      });
    }
    return Column(children: [
      if (allowed)
        SafeArea(
            bottom: false,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(_status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall))),
      Expanded(
          key: const ValueKey('location-session-content'), child: widget.child)
    ]);
  }
}
