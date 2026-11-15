import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';

/// An isolated HTTP contract fixture, not an emulator of PostgreSQL/RLS.
/// Every request is captured; no request is forwarded to a remote service.
class ErpTestBackend {
  static final instance = ErpTestBackend();
  final tables = <String, List<Map<String, dynamic>>>{};
  final requests = <http.Request>[];
  int sequence = 0;
  late final http.Client client = MockClient(handle);
  static const adminId = '84b7c957-e145-446a-9a31-051f2cb9b3af';
  static const accountsId = '3f6ae45e-67ba-4513-93f6-a8e691c01907';
  static const headId = 'b194578e-67ba-4513-93f6-a8e691c01908';
  ErpTestBackend() {
    reset();
  }
  void reset() {
    tables.clear();
    requests.clear();
    final now = DateTime.now().toIso8601String();
    tables['users'] = [
      for (final (id, role, email) in [
        (adminId, 'admin', 'admin@skcpl.com'),
        (accountsId, 'accounts', 'accounts@skcpl.com'),
        (headId, 'project_head', 'projecthead@skcpl.com')
      ])
        {
          'id': id,
          'role': role,
          'email': email,
          'is_active': true,
          'created_at': now,
          'updated_at': now
        },
    ];
    tables['sites'] = [
      for (final (id, name, login) in [
        ('4c9e1f3a-6903-441a-a2aa-37362a13bafe', 'Nissarpur', '123456'),
        (
          'bdb1478e-4fa9-4873-9804-864b0952fa4d',
          'Indore Head Office',
          'office'
        ),
        ('89e1477d-7f66-4b6d-99ca-6270183143e0', 'HEAD-OFFICE INDORE', 'HO001'),
        (
          '4e8efe20-c680-4438-bc48-d46f5c35df09',
          'PIU-HATPIPALIYA HOSPITAL',
          'HAT001'
        )
      ])
        {
          'id': id,
          'name': name,
          'site_login_id': login,
          'site_password_hash':
              sha256.convert(utf8.encode('fixture-pin')).toString(),
          'is_active': true,
          'created_at': now,
          'updated_at': now,
          'address': name
        },
    ];
    tables['site_staff'] = [
      for (final site in tables['sites']!)
        {
          'id': 'staff-${site['id']}',
          'site_id': site['id'],
          'name': 'Fixture Engineer',
          'role': 'supervisor',
          'modules': ['stock', 'cashbook', 'report', 'attendance'],
          'pin': 'fixture-pin',
          'is_active': true,
          'created_at': now
        }
    ];
    tables['dropdowns'] = [
      for (final (id, cat, value) in [
        ('e72d9d18-2a33-4748-a04f-ddfdc9504a3f', 'expense_type', 'General'),
        ('441097fa-eef6-4df4-a4f6-7b003b302c0b', 'product', 'Cement'),
        ('00000000-0000-0000-0000-000000000002', 'metric_unit', 'Bags')
      ])
        {
          'id': id,
          'category': cat,
          'value': value,
          'is_active': true,
          'sort_order': 0,
          'created_at': now
        }
    ];
  }

  String nextId() =>
      '10000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}';
  http.Response response(http.Request request, Object? body,
          {int status = 200, Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode(body), status,
          request: request,
          headers: {'content-type': 'application/json', ...headers});
  bool matches(Map<String, dynamic> row, String key, String filter) {
    if (key == 'or') {
      final expression = filter
          .replaceFirst(RegExp(r'^\('), '')
          .replaceFirst(RegExp(r'\)$'), '');
      return expression.split(',').any((part) {
        final i = part.indexOf('.');
        return i < 0
            ? false
            : matches(row, part.substring(0, i), part.substring(i + 1));
      });
    }
    if (key == 'and') return true;
    final i = filter.indexOf('.');
    if (i < 0) return true;
    final op = filter.substring(0, i);
    final val = filter.substring(i + 1);
    final actual = row[key];
    switch (op) {
      case 'eq':
        return '$actual' == val;
      case 'neq':
        return '$actual' != val;
      case 'is':
        return val == 'null' ? actual == null : '$actual' == val;
      case 'in':
        return val
            .replaceAll(RegExp(r'[()"]'), '')
            .split(',')
            .contains('$actual');
      case 'gte':
        return '$actual'.compareTo(val) >= 0;
      case 'lte':
        return '$actual'.compareTo(val) <= 0;
      case 'gt':
        return '$actual'.compareTo(val) > 0;
      case 'lt':
        return '$actual'.compareTo(val) < 0;
      case 'like':
      case 'ilike':
        final pattern =
            RegExp.escape(val).replaceAll('%', '.*').replaceAll('*', '.*');
        return RegExp('^$pattern\$', caseSensitive: op == 'like')
            .hasMatch('$actual');
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> view(String table) {
    if (table == 'site_current_stock') {
      final groups = <String, Map<String, dynamic>>{};
      for (final tx
          in tables['stock_transactions'] ?? <Map<String, dynamic>>[]) {
        if (tx['status'] != 'approved') continue;
        final key =
            '${tx['site_id']}/${tx['product_id']}/${tx['metric_unit_id']}';
        final row = groups.putIfAbsent(
            key,
            () => {
                  'site_id': tx['site_id'],
                  'product_id': tx['product_id'],
                  'product_name': tx['product_id'],
                  'metric_unit': tx['metric_unit_id'],
                  'total_inbound': 0.0,
                  'total_outbound': 0.0,
                  'current_stock': 0.0
                });
        final field =
            tx['type'] == 'inbound' ? 'total_inbound' : 'total_outbound';
        row[field] = (row[field] as num) + (tx['quantity'] as num);
        row['current_stock'] =
            (row['total_inbound'] as num) - (row['total_outbound'] as num);
      }
      return groups.values.toList();
    }
    return tables.putIfAbsent(table, () => []);
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.contains('/auth/v1/')) {
      if (path.endsWith('/logout')) return response(request, {});
      if (path.endsWith('/token')) {
        final data = Map<String, dynamic>.from(jsonDecode(request.body));
        final email = data['email'];
        if (data['password'] == 'wrongPassword' ||
            data['password'] == 'wrong') {
          return response(request, {'msg': 'Invalid credentials'}, status: 400);
        }
        final user = (tables['users'] ?? [])
            .where((u) => u['email'] == email)
            .firstOrNull;
        if (user == null) {
          return response(request, {'msg': 'Invalid credentials'}, status: 400);
        }
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': user['id'],
              'exp': 4102444800,
              'role': 'authenticated'
            })))
            .replaceAll('=', '');
        return response(request, {
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': user['id'],
            'email': user['email'],
            'aud': 'authenticated',
            'role': 'authenticated',
            'created_at': user['created_at'],
            'app_metadata': {},
            'user_metadata': {}
          }
        });
      }
      return response(request, {});
    }
    if (path.contains('/storage/v1/')) {
      return response(request, {'Key': path.split('/object/').last});
    }
    if (!path.contains('/rest/v1/')) {
      throw StateError(
          'Unexpected external request blocked: ${request.url.host}');
    }
    final table = path.split('/rest/v1/').last;
    if (table.startsWith('rpc/')) {
      return response(
          request,
          {
            'code': 'PGRST202',
            'message': 'RPC unavailable in isolated fixture'
          },
          status: 404);
    }
    final source = view(table);
    var rows = source
        .where((row) => request.url.queryParameters.entries.every((e) =>
            ['select', 'order', 'limit', 'offset', 'on_conflict']
                .contains(e.key) ||
            matches(row, e.key, e.value)))
        .toList();
    if (request.method == 'POST') {
      final body = jsonDecode(request.body);
      final inputs = body is List ? body : [body];
      rows = [];
      for (final input in inputs) {
        final data = Map<String, dynamic>.from(input as Map);
        data.putIfAbsent('id', nextId);
        final existing = source.where((r) => r['id'] == data['id']).firstOrNull;
        if (existing != null) {
          if (!(request.headers['prefer'] ?? '')
              .contains('resolution=merge-duplicates')) {
            return response(
                request, {'code': '23505', 'message': 'duplicate key'},
                status: 409);
          }
          existing.addAll(data);
          rows.add(existing);
        } else {
          data.putIfAbsent(
              'created_at', () => DateTime.now().toIso8601String());
          data.putIfAbsent(
              'updated_at', () => DateTime.now().toIso8601String());
          data.putIfAbsent('status', () => 'pending_accounts');
          source.add(data);
          rows.add(data);
        }
      }
    } else if (request.method == 'PATCH') {
      final updates = Map<String, dynamic>.from(jsonDecode(request.body));
      for (final row in rows) {
        row.addAll(updates);
        row['updated_at'] = DateTime.now().toIso8601String();
      }
    } else if (request.method == 'DELETE') {
      for (final row in rows) {
        source.remove(row);
      }
    }
    final order = request.url.queryParameters['order'];
    if (order != null) {
      for (final term in order.split(',').reversed) {
        final f = term.split('.');
        rows.sort((a, b) {
          final c = '${a[f.first]}'.compareTo('${b[f.first]}');
          return f.contains('desc') ? -c : c;
        });
      }
    }
    final count = rows.length;
    final offset =
        int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '$count') ?? count;
    rows = rows
        .skip(offset)
        .take(limit)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    for (final row in rows) {
      if (table == 'cash_transactions') {
        row['dropdown_items'] = {'value': 'General'};
      }
      if (table == 'stock_transactions') {
        row['product'] = {'value': 'Cement'};
        row['unit'] = {'value': 'Bags'};
        row['sites'] = {'name': 'Fixture Site'};
      }
    }
    final single = (request.headers['accept'] ?? '')
        .contains('application/vnd.pgrst.object+json');
    if (single && rows.length != 1) {
      return response(
          request,
          {
            'code': 'PGRST116',
            'message': 'Expected one row',
            'details': 'The result contains ${rows.length} rows'
          },
          status: 406);
    }
    return response(request, single ? rows.single : rows,
        headers: {'content-range': '0-${rows.length}/$count'});
  }
}
