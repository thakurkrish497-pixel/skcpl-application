import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/supabase_constants.dart';
import 'file_saver_helper.dart';

/// Layer 2: Complete Disaster Recovery & In-App Master Backup Service
/// Exports 100% of SKCPL data into:
/// 1. Comprehensive JSON snapshot (full fidelity for instant DB restoration)
/// 2. Multi-Sheet Master Excel Workbook (accounting & audit ready)
/// 3. Media & Attachments Catalog (vouchers, bills, DSR photos, attendance selfies)
class BackupService {
  static final SupabaseClient _client = SupabaseClient(
    SupabaseConstants.supabaseUrl,
    SupabaseConstants.supabaseAnonKey,
  );

  /// Fetch all tables across the entire company
  static Future<Map<String, dynamic>> fetchFullOrganizationData() async {
    final timestamp = DateTime.now();

    // Parallel fetch from all Supabase tables
    final results = await Future.wait([
      _safeSelect('sites', 'name'),
      _safeSelect('site_staff', 'created_at'),
      _safeSelect('cash_transactions', 'date'),
      _safeSelect('stock_transactions', 'date'),
      _safeSelect('attendance', 'date'),
      _safeSelect('attendance_regularization', 'created_at'),
      _safeSelect('daily_site_reports', 'report_date'),
      _safeSelect('expense_types', 'name'),
      _safeSelect('vendors', 'name'),
      _safeSelect('products', 'name'),
    ]);

    final sites = results[0];
    final staff = results[1];
    final cash = results[2];
    final stock = results[3];
    final attendance = results[4];
    final regularization = results[5];
    final dsrs = results[6];
    final expenseTypes = results[7];
    final vendors = results[8];
    final products = results[9];

    return {
      'metadata': {
        'app': 'SKCPL Construction Management',
        'tagline': 'Connect to Waves',
        'version': '1.0.0',
        'exported_at': timestamp.toIso8601String(),
        'exported_at_formatted': DateFormat('dd MMM yyyy, hh:mm a').format(timestamp),
        'database_host': SupabaseConstants.supabaseUrl,
        'counts': {
          'sites': sites.length,
          'site_staff': staff.length,
          'cash_transactions': cash.length,
          'stock_transactions': stock.length,
          'attendance': attendance.length,
          'attendance_regularization': regularization.length,
          'daily_site_reports': dsrs.length,
          'expense_types': expenseTypes.length,
          'vendors': vendors.length,
          'products': products.length,
          'total_records': sites.length +
              staff.length +
              cash.length +
              stock.length +
              attendance.length +
              regularization.length +
              dsrs.length +
              expenseTypes.length +
              vendors.length +
              products.length,
        },
      },
      'sites': sites,
      'site_staff': staff,
      'cash_transactions': cash,
      'stock_transactions': stock,
      'attendance': attendance,
      'attendance_regularization': regularization,
      'daily_site_reports': dsrs,
      'expense_types': expenseTypes,
      'vendors': vendors,
      'products': products,
    };
  }

  static Future<List<Map<String, dynamic>>> _safeSelect(String table, String orderColumn) async {
    try {
      final data = await _client.from(table).select().order(orderColumn, ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      try {
        final data = await _client.from(table).select();
        return List<Map<String, dynamic>>.from(data);
      } catch (_) {
        return [];
      }
    }
  }

  /// 1. Export 100% full-fidelity JSON Backup
  static Future<void> exportFullJsonBackup() async {
    final fullData = await fetchFullOrganizationData();
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(fullData);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    final timeKey = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final fileName = 'SKCPL_DATABASE_BACKUP_$timeKey.json';

    await FileSaverHelper.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/json',
      shareTitle: 'SKCPL Full System Backup',
    );
  }

  /// 2. Export Master Multi-Sheet Excel Workbook
  static Future<void> exportMasterExcelBackup() async {
    final fullData = await fetchFullOrganizationData();
    final excel = Excel.createExcel();

    // Map sites by ID for quick lookup
    final sitesList = (fullData['sites'] as List? ?? []);
    final siteMap = <String, String>{};
    for (final s in sitesList) {
      if (s is Map && s['id'] != null) {
        siteMap[s['id'].toString()] = s['name']?.toString() ?? 'Site';
      }
    }

    // Map staff by ID
    final staffList = (fullData['site_staff'] as List? ?? []);
    final staffMap = <String, String>{};
    for (final st in staffList) {
      if (st is Map && st['id'] != null) {
        staffMap[st['id'].toString()] = st['name']?.toString() ?? 'Staff';
      }
    }

    // ── SHEET 1: SYSTEM OVERVIEW & SITES ──
    final s1 = excel['01_SITES_AND_SUMMARY'];
    _writeRow(s1, [
      'SKCPL CONSTRUCTION MANAGEMENT - MASTER DATABASE BACKUP',
      '',
      '',
      '',
      '',
    ]);
    _writeRow(s1, [
      'Generated At:',
      DateFormat('dd-MMM-yyyy HH:mm:ss').format(DateTime.now()),
      'Brand Tagline:',
      'Connect to Waves',
      '',
    ]);
    _writeRow(s1, []);
    _writeRow(s1, ['SITE ID', 'SITE NAME', 'LOCATION', 'LATITUDE', 'LONGITUDE', 'STATUS', 'RADIUS (M)']);
    for (final site in sitesList) {
      if (site is Map) {
        _writeRow(s1, [
          site['id']?.toString() ?? '',
          site['name']?.toString() ?? '',
          site['location']?.toString() ?? '',
          site['latitude']?.toString() ?? '',
          site['longitude']?.toString() ?? '',
          (site['is_active'] == true || site['status'] == 'active') ? 'ACTIVE' : 'INACTIVE',
          site['geofence_radius_meters']?.toString() ?? '100',
        ]);
      }
    }

    // ── SHEET 2: CASHBOOK MASTER ──
    final s2 = excel['02_CASHBOOK_MASTER'];
    _writeRow(s2, [
      'TRANSACTION ID',
      'DATE',
      'SITE',
      'TYPE',
      'AMOUNT (INR)',
      'CATEGORY / REMARKS',
      'SUBMITTED BY',
      'PAYMENT MODE',
      'STATUS',
      'BILL / RECEIPT URL',
      'CREATED AT',
    ]);
    final cashList = (fullData['cash_transactions'] as List? ?? []);
    for (final c in cashList) {
      if (c is Map) {
        final siteName = siteMap[c['site_id']?.toString()] ?? c['site_id']?.toString() ?? '';
        final staffName = staffMap[c['submitted_by']?.toString()] ?? c['submitted_by']?.toString() ?? '';
        final amt = (c['expense_amount'] ?? c['amount'] ?? 0).toString();
        _writeRow(s2, [
          c['id']?.toString() ?? '',
          c['date']?.toString() ?? '',
          siteName,
          c['type']?.toString().toUpperCase() ?? 'EXPENSE',
          amt,
          c['remarks']?.toString() ?? '',
          staffName,
          c['payment_mode']?.toString() ?? 'Cash',
          c['status']?.toString().toUpperCase() ?? 'APPROVED',
          c['bill_image_url']?.toString() ?? c['receipt_url']?.toString() ?? '',
          c['created_at']?.toString() ?? '',
        ]);
      }
    }

    // ── SHEET 3: STOCK REGISTER ──
    final s3 = excel['03_STOCK_REGISTER'];
    _writeRow(s3, [
      'TRANSACTION ID',
      'DATE',
      'SITE',
      'PRODUCT / MATERIAL',
      'TYPE',
      'QUANTITY',
      'UNIT',
      'VENDOR',
      'VEHICLE / CHALLAN NO',
      'REMARKS',
      'STATUS',
      'CHALLAN URL',
      'CREATED AT',
    ]);
    final stockList = (fullData['stock_transactions'] as List? ?? []);
    for (final st in stockList) {
      if (st is Map) {
        final siteName = siteMap[st['site_id']?.toString()] ?? st['site_id']?.toString() ?? '';
        _writeRow(s3, [
          st['id']?.toString() ?? '',
          st['date']?.toString() ?? '',
          siteName,
          st['product_name']?.toString() ?? st['item_name']?.toString() ?? '',
          st['type']?.toString().toUpperCase() ?? 'INWARD',
          st['quantity']?.toString() ?? '0',
          st['unit']?.toString() ?? 'Nos',
          st['vendor_name']?.toString() ?? '',
          st['challan_no']?.toString() ?? st['vehicle_no']?.toString() ?? '',
          st['remarks']?.toString() ?? '',
          st['status']?.toString().toUpperCase() ?? 'APPROVED',
          st['challan_image_url']?.toString() ?? '',
          st['created_at']?.toString() ?? '',
        ]);
      }
    }

    // ── SHEET 4: ATTENDANCE REGISTER ──
    final s4 = excel['04_ATTENDANCE_LOGS'];
    _writeRow(s4, [
      'ATTENDANCE ID',
      'DATE',
      'SITE',
      'STAFF NAME',
      'ROLE',
      'PUNCH IN TIME',
      'PUNCH OUT TIME',
      'TOTAL HOURS',
      'GPS LAT',
      'GPS LNG',
      'STATUS',
      'SELFIE / PHOTO URL',
    ]);
    final attList = (fullData['attendance'] as List? ?? []);
    for (final a in attList) {
      if (a is Map) {
        final siteName = siteMap[a['site_id']?.toString()] ?? a['site_id']?.toString() ?? '';
        final staffName = staffMap[a['staff_id']?.toString()] ?? a['staff_name']?.toString() ?? '';
        _writeRow(s4, [
          a['id']?.toString() ?? '',
          a['date']?.toString() ?? '',
          siteName,
          staffName,
          a['role']?.toString().toUpperCase() ?? 'WORKER',
          a['punch_in']?.toString() ?? '',
          a['punch_out']?.toString() ?? '',
          a['total_hours']?.toString() ?? '',
          a['latitude']?.toString() ?? '',
          a['longitude']?.toString() ?? '',
          a['status']?.toString().toUpperCase() ?? 'PRESENT',
          a['photo_url']?.toString() ?? '',
        ]);
      }
    }

    // ── SHEET 5: DAILY SITE REPORTS (DSR) ──
    final s5 = excel['05_DAILY_REPORTS_DSR'];
    _writeRow(s5, [
      'REPORT ID',
      'DATE',
      'SITE',
      'SUBMITTED BY',
      'WORK PROGRESS & ACTIVITIES',
      'MANPOWER COUNT',
      'MACHINERY & EQUIPMENT',
      'WEATHER',
      'REMARKS / ISSUES',
      'STATUS',
      'PHOTO 1 URL',
      'PHOTO 2 URL',
      'CREATED AT',
    ]);
    final dsrList = (fullData['daily_site_reports'] as List? ?? []);
    for (final d in dsrList) {
      if (d is Map) {
        final siteName = siteMap[d['site_id']?.toString()] ?? d['site_id']?.toString() ?? '';
        final staffName = staffMap[d['submitted_by']?.toString()] ?? d['submitted_by']?.toString() ?? '';
        final photos = (d['photos'] as List?) ?? [];
        _writeRow(s5, [
          d['id']?.toString() ?? '',
          d['report_date']?.toString() ?? '',
          siteName,
          staffName,
          d['work_progress']?.toString() ?? d['activities']?.toString() ?? '',
          d['manpower_count']?.toString() ?? '',
          d['machinery_used']?.toString() ?? '',
          d['weather']?.toString() ?? 'Clear',
          d['remarks']?.toString() ?? '',
          d['status']?.toString().toUpperCase() ?? 'APPROVED',
          photos.isNotEmpty ? photos[0].toString() : '',
          photos.length > 1 ? photos[1].toString() : '',
          d['created_at']?.toString() ?? '',
        ]);
      }
    }

    // ── SHEET 6: SITE STAFF DIRECTORY ──
    final s6 = excel['06_STAFF_DIRECTORY'];
    _writeRow(s6, [
      'STAFF ID',
      'NAME',
      'PHONE',
      'ASSIGNED SITE',
      'ROLE',
      'DATE OF BIRTH',
      'AADHAR NUMBER',
      'AADHAR CARD URL',
      'PAN NUMBER',
      'PAN CARD URL',
      'ALLOWED MODULES',
      'IS ACTIVE',
      'CREATED AT',
    ]);
    for (final st in staffList) {
      if (st is Map) {
        final siteName = siteMap[st['site_id']?.toString()] ?? st['site_id']?.toString() ?? '';
        final modules = (st['modules'] as List?)?.join(', ') ?? 'All';
        _writeRow(s6, [
          st['id']?.toString() ?? '',
          st['name']?.toString() ?? '',
          st['phone']?.toString() ?? '',
          siteName,
          st['role']?.toString().toUpperCase() ?? 'WORKER',
          st['date_of_birth']?.toString() ?? '',
          st['aadhar_number']?.toString() ?? '',
          st['aadhar_card_url']?.toString() ?? '',
          st['pan_number']?.toString() ?? '',
          st['pan_card_url']?.toString() ?? '',
          modules,
          st['is_active'] == true ? 'YES' : 'NO',
          st['created_at']?.toString() ?? '',
        ]);
      }
    }

    // Remove default Sheet1 if exists
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode()!;
    final timeKey = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final fileName = 'SKCPL_MASTER_DATA_$timeKey.xlsx';

    await FileSaverHelper.saveAndOpen(
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      mimeType: FileSaverHelper.excelMimeType,
      shareTitle: 'SKCPL Master Excel Backup',
    );
  }

  /// 3. Export Media & Attachments Manifest
  static Future<void> exportMediaManifest() async {
    final fullData = await fetchFullOrganizationData();
    final manifest = <Map<String, dynamic>>[];

    // Cash receipts
    final cashList = (fullData['cash_transactions'] as List? ?? []);
    for (final c in cashList) {
      if (c is Map) {
        final url = c['bill_image_url'] ?? c['receipt_url'];
        if (url != null && url.toString().isNotEmpty) {
          manifest.add({
            'module': 'cash',
            'record_id': c['id'],
            'date': c['date'],
            'title': 'Voucher Receipt - ${c['remarks']}',
            'media_url': url.toString(),
          });
        }
      }
    }

    // Stock challans
    final stockList = (fullData['stock_transactions'] as List? ?? []);
    for (final s in stockList) {
      if (s is Map) {
        final url = s['challan_image_url'];
        if (url != null && url.toString().isNotEmpty) {
          manifest.add({
            'module': 'stock',
            'record_id': s['id'],
            'date': s['date'],
            'title': 'Delivery Challan - ${s['product_name']}',
            'media_url': url.toString(),
          });
        }
      }
    }

    // Attendance selfies
    final attList = (fullData['attendance'] as List? ?? []);
    for (final a in attList) {
      if (a is Map) {
        final url = a['photo_url'];
        if (url != null && url.toString().isNotEmpty) {
          manifest.add({
            'module': 'attendance',
            'record_id': a['id'],
            'date': a['date'],
            'title': 'Attendance Photo - ${a['staff_name']}',
            'media_url': url.toString(),
          });
        }
      }
    }

    // DSR site photos
    final dsrList = (fullData['daily_site_reports'] as List? ?? []);
    for (final d in dsrList) {
      if (d is Map) {
        final photos = (d['photos'] as List?) ?? [];
        for (var i = 0; i < photos.length; i++) {
          final url = photos[i];
          if (url != null && url.toString().isNotEmpty) {
            manifest.add({
              'module': 'dsr',
              'record_id': d['id'],
              'date': d['report_date'],
              'title': 'DSR Site Photo #${i + 1}',
              'media_url': url.toString(),
            });
          }
        }
      }
    }

    // Staff KYC (Aadhar & PAN cards)
    final staffList = (fullData['site_staff'] as List? ?? []);
    for (final st in staffList) {
      if (st is Map) {
        final aadharUrl = st['aadhar_card_url'];
        if (aadharUrl != null && aadharUrl.toString().isNotEmpty) {
          manifest.add({
            'module': 'staff_kyc',
            'record_id': st['id'],
            'date': st['created_at'],
            'title': 'Aadhar Card - ${st['name']}',
            'media_url': aadharUrl.toString(),
          });
        }
        final panUrl = st['pan_card_url'];
        if (panUrl != null && panUrl.toString().isNotEmpty) {
          manifest.add({
            'module': 'staff_kyc',
            'record_id': st['id'],
            'date': st['created_at'],
            'title': 'PAN Card - ${st['name']}',
            'media_url': panUrl.toString(),
          });
        }
      }
    }

    final catalog = {
      'metadata': {
        'total_media_attachments': manifest.length,
        'generated_at': DateTime.now().toIso8601String(),
        'app': 'SKCPL Construction Management',
        'tagline': 'Connect to Waves',
      },
      'media_catalog': manifest,
    };

    const encoder = JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert(catalog);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    final timeKey = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final fileName = 'SKCPL_MEDIA_MANIFEST_$timeKey.json';

    await FileSaverHelper.saveAndOpen(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/json',
      shareTitle: 'SKCPL Media Manifest',
    );
  }

  /// Validate any backup JSON file content and summarize contents
  static Map<String, dynamic> validateBackup(String jsonContent) {
    try {
      final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
      final metadata = decoded['metadata'] as Map<String, dynamic>? ?? {};
      final counts = metadata['counts'] as Map<String, dynamic>? ?? {};

      return {
        'isValid': true,
        'app': metadata['app'] ?? 'SKCPL',
        'exportedAt': metadata['exported_at_formatted'] ?? metadata['exported_at'] ?? 'Unknown',
        'sitesCount': (decoded['sites'] as List?)?.length ?? counts['sites'] ?? 0,
        'staffCount': (decoded['site_staff'] as List?)?.length ?? counts['site_staff'] ?? 0,
        'cashCount': (decoded['cash_transactions'] as List?)?.length ?? counts['cash_transactions'] ?? 0,
        'stockCount': (decoded['stock_transactions'] as List?)?.length ?? counts['stock_transactions'] ?? 0,
        'attendanceCount': (decoded['attendance'] as List?)?.length ?? counts['attendance'] ?? 0,
        'dsrCount': (decoded['daily_site_reports'] as List?)?.length ?? counts['daily_site_reports'] ?? 0,
      };
    } catch (e) {
      return {
        'isValid': false,
        'error': e.toString(),
      };
    }
  }

  static void _writeRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }
}
