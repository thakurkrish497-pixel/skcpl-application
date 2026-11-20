import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:skcpl_app/providers/dsr_history_provider.dart';
import 'package:skcpl_app/providers/auth_provider.dart';
import 'package:skcpl_app/models/user_model.dart';
import 'dashboard_widget_test.dart' show FixedAuth;

Map<String, dynamic> report(String id,
        {String site = 'site-a',
        String date = '2026-11-16',
        String? remarks}) =>
    {
      'id': id,
      'site_id': site,
      'date': date,
      'notes': 'Slab casting complete',
      'photo_urls': ['https://fixture.invalid/progress.jpg'],
      'work_done': ['RCC slab'],
      'manpower_details': 'Masons: 3; Helpers: 7',
      'labour_count': 10,
      'remarks': remarks,
      'created_at': '2026-11-16T08:00:00Z',
      'updated_at': '2026-11-16T10:00:00Z'
    };
Map<String, dynamic> audit(String id) => {
      'module': 'dsr',
      'entry_id': id,
      'state': {
        'project_head': {
          'decision': 'approved',
          'reviewed_by': 'project-user',
          'reviewed_at': '2026-11-16T09:00:00Z',
          'note': 'Measurements checked'
        },
        'admin': {
          'decision': 'approved',
          'reviewed_by': 'admin-user',
          'reviewed_at': '2026-11-16T10:00:00Z'
        },
        'final': {
          'decision': 'approved',
          'reviewed_by': 'admin-user',
          'reviewed_at': '2026-11-16T10:00:00Z'
        }
      }
    };
SupabaseClient clientWith(
        Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient('http://dsr.fixture.invalid', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(handler));
http.Response response(http.Request r, Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        request: r, headers: {'content-type': 'application/json'});
void main() {
  test(
      'Full archive merges primary and legacy reports, preserves all details and performs GETs only',
      () async {
    final original = report('same', remarks: '[Admin: Approved by admin-user]');
    final legacy = report('legacy', site: 'inactive-site', date: '2020-01-02');
    final before = jsonEncode([original, legacy]);
    final requests = <http.Request>[];
    final c = clientWith((r) async {
      requests.add(r);
      return response(
          r,
          r.url.path.endsWith('/tasks')
              ? [
                  {
                    'id': 'task1',
                    'description':
                        jsonEncode(report('same')..['notes'] = 'old copy')
                  },
                  {'id': 'task2', 'description': jsonEncode(legacy)}
                ]
              : r.url.path.endsWith('/daily_site_reports')
                  ? [original]
                  : [audit('same')]);
    });
    addTearDown(c.dispose);
    final loaded = await DsrHistoryService(c).load();
    expect(loaded.entries.map((e) => e.report.id).toSet(), {'same', 'legacy'});
    final entry = loaded.entries.firstWhere((e) => e.report.id == 'same');
    expect(entry.report.notes, 'Slab casting complete');
    expect(entry.report.photoUrls, original['photo_urls']);
    expect(entry.submittedData['labour_count'], 10);
    expect(entry.reviewState['admin']['reviewed_at'], '2026-11-16T10:00:00Z');
    expect(entry.approved, isTrue);
    expect(jsonEncode([original, legacy]), before);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });
  test(
      'Site history scopes both storage formats without reading management-only review audits',
      () async {
    final requests = <http.Request>[];
    final original = report('own', site: 'site-a');
    final before = jsonEncode(original);
    final c = clientWith((r) async {
      requests.add(r);
      if (r.url.path.endsWith('/tasks')) {
        expect(r.url.queryParameters['site_id'], 'eq.site-a');
        return response(r, [
          {
            'id': 'legacy',
            'description': jsonEncode(report('legacy', site: 'site-a'))
          },
          {
            'id': 'malformed-owner',
            'description': jsonEncode(report('other', site: 'site-b'))
          },
        ]);
      }
      if (r.url.path.endsWith('/daily_site_reports')) {
        expect(r.url.queryParameters['site_id'], 'eq.site-a');
        return response(r, [original]);
      }
      fail('Site history must never query the management review audit');
    });
    addTearDown(c.dispose);
    final result = await DsrHistoryService(c).loadForSite('site-a');
    expect(result.entries.map((e) => e.report.id).toSet(), {'own', 'legacy'});
    expect(result.entries.first.reviewAuditAvailable, isFalse);
    expect(jsonEncode(original), before);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(() => DsrHistoryService(c).loadForSite('all'), throwsArgumentError);
  });
  test('An empty site archive never fetches unrelated review audits', () async {
    final c = clientWith((r) async {
      expect(r.url.path.endsWith('/skcpl_entry_reviews'), isFalse);
      return response(r, []);
    });
    addTearDown(c.dispose);
    expect((await DsrHistoryService(c).loadForSite('empty')).entries, isEmpty);
  });
  test(
      'Keyset pagination loads more than the usual 1000-row limit, with no duplicate reports',
      () async {
    final rows =
        List.generate(1205, (i) => report(i.toString().padLeft(5, '0')));
    var pages = 0;
    final c = clientWith((r) async {
      if (!r.url.path.endsWith('/daily_site_reports')) return response(r, []);
      pages++;
      final cursor = r.url.queryParameters['id']?.replaceFirst('gt.', '');
      return response(
          r,
          rows
              .where((d) =>
                  cursor == null || (d['id'] as String).compareTo(cursor) > 0)
              .take(200)
              .toList());
    });
    addTearDown(c.dispose);
    final s = await DsrHistoryService(c).load();
    expect(s.entries.length, 1205);
    expect(s.entries.map((e) => e.report.id).toSet().length, 1205);
    expect(pages, 7);
  });
  test(
      'Missing primary/audit schemas still expose legacy records without fabricating timestamps',
      () async {
    final c = clientWith((r) async => r.url.path.endsWith('/tasks')
        ? response(r, [
            {
              'id': 'task',
              'description': jsonEncode(report('legacy',
                  remarks: '[Project Head: Approved by Vikas]'))
            }
          ])
        : response(r, {'code': '42P01', 'message': 'missing table'},
            status: 404));
    addTearDown(c.dispose);
    final s = await DsrHistoryService(c).load();
    expect(s.entries.single.reviewed, isTrue);
    expect(s.entries.single.approved, isFalse);
    expect(s.entries.single.reviewState, isEmpty);
    expect(s.warnings.single, contains('no review times are inferred'));
  });
  test(
      'Permission failures are surfaced and never trigger a write or empty-success fallback',
      () async {
    final methods = <String>[];
    final c = clientWith((r) async {
      methods.add(r.method);
      return response(r, {'code': '42501', 'message': 'permission denied'},
          status: 403);
    });
    addTearDown(c.dispose);
    await expectLater(
        DsrHistoryService(c).load(), throwsA(isA<PostgrestException>()));
    expect(methods, ['GET']);
  });
  test(
      'Malformed legacy rows are reported, not silently treated as valid or modified',
      () async {
    final c = clientWith((r) async => response(
        r,
        r.url.path.endsWith('/tasks')
            ? [
                {'description': 'broken json'},
                {'description': jsonEncode(report('valid'))}
              ]
            : []));
    addTearDown(c.dispose);
    final s = await DsrHistoryService(c).load();
    expect(s.entries.single.report.id, 'valid');
    expect(s.warnings.single, contains('1 historical record'));
  });
  test(
      'Current audit wins over stale legacy approval labels and review state is not changed',
      () {
    final state = {
      'final': {'decision': 'rejected', 'reviewed_at': '2026-11-16T10:00:00Z'}
    };
    final before = jsonEncode(state);
    final e = DsrHistoryEntry(
        report('x', remarks: '[Admin: Approved by Old]'), state);
    expect(e.rejected, isTrue);
    expect(e.approved, isFalse);
    expect(e.status, 'Rejected');
    expect(jsonEncode(state), before);
  });
  for (final role in [
    UserRole.admin,
    UserRole.projectHead,
    UserRole.accounts
  ]) {
    test('$role can read history without approval powers', () async {
      final service = _FakeHistory();
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => FixedAuth(role)),
        dsrHistoryServiceProvider.overrideWithValue(service)
      ]);
      addTearDown(c.dispose);
      expect((await c.read(dsrHistoryProvider.future)).entries, isEmpty);
      expect(service.loads, 1);
    });
  }
  test('Site sessions load only their site, never the management archive',
      () async {
    final service = _FakeHistory();
    final c = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => FixedAuth(UserRole.worker)),
      dsrHistoryServiceProvider.overrideWithValue(service)
    ]);
    addTearDown(c.dispose);
    expect((await c.read(dsrHistoryProvider.future)).entries, isEmpty);
    expect(service.loads, 0);
    expect(service.siteLoads, 1);
    expect(service.lastSite, isNotEmpty);
  });
}

class _FakeHistory extends DsrHistoryService {
  int loads = 0;
  int siteLoads = 0;
  String? lastSite;
  @override
  Future<DsrHistorySnapshot> loadForSite(String siteId) async {
    siteLoads++;
    lastSite = siteId;
    return const DsrHistorySnapshot([]);
  }

  _FakeHistory() : super(Supabase.instance.client);
  @override
  Future<DsrHistorySnapshot> load() async {
    loads++;
    return const DsrHistorySnapshot([]);
  }
}
