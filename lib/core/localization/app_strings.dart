import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/locale_provider.dart';

/// Comprehensive Localization Dictionary for SKCPL Construction Management App
/// Providing accurate, natural Hindi translations for construction site workflows,
/// while keeping technical terms and brand names ('SKCPL') appropriate.
class AppStrings {
  static const Map<String, Map<String, String>> _translations = {
    // ─── Header & App ───
    'app_title': {
      'en': 'SKCPL Construction Management',
      'hi': 'SKCPL निर्माण प्रबंधन',
    },
    'company_name': {
      'en': 'SKCPL',
      'hi': 'SKCPL',
    },
    'construction_management': {
      'en': 'Construction Management',
      'hi': 'निर्माण प्रबंधन',
    },
    'welcome_msg': {
      'en': 'Welcome back! Choose a module to get started.',
      'hi': 'स्वागत है! शुरू करने के लिए मॉड्यूल चुनें।',
    },
    'language': {
      'en': 'Language',
      'hi': 'भाषा',
    },
    'switch_language': {
      'en': 'Switch to हिन्दी',
      'hi': 'Switch to English',
    },

    // ─── Home Modules ───
    'stock_management': {
      'en': 'Stock Management',
      'hi': 'स्टॉक प्रबंधन',
    },
    'stock_management_sub': {
      'en': 'Manage inbound & outbound inventory across construction sites',
      'hi': 'निर्माण साइटों पर आवक और जावक सामग्री का प्रबंधन करें',
    },
    'cash_book': {
      'en': 'Cash Book',
      'hi': 'रोकड़ बही (कैश बुक)',
    },
    'cash_book_sub': {
      'en': 'Track expenses, receipts, and cash-in-hand per site',
      'hi': 'प्रति साइट खर्च, रसीदें और शेष नकद राशि ट्रैक करें',
    },
    'daily_site_report': {
      'en': 'Daily Site Report',
      'hi': 'दैनिक साइट रिपोर्ट (DSR)',
    },
    'daily_site_report_sub': {
      'en': 'Voice-to-text reporting with photo attachments',
      'hi': 'फोटो और आवाज के साथ दैनिक कार्य प्रगति रिपोर्ट',
    },
    'attendance_punch': {
      'en': 'Attendance & Punch',
      'hi': 'उपस्थिति और हाजिरी',
    },
    'attendance_punch_sub': {
      'en': 'Selfie & GPS verified attendance with geofencing',
      'hi': 'सेल्फी और जीपीएस सत्यापन के साथ हाजिरी लगाएं',
    },
    'admin_portal': {
      'en': 'Management Portal (Admin, Accounts & Project Head)',
      'hi': 'प्रबंधन पोर्टल (एडमिन, अकाउंट्स और प्रोजेक्ट हेड)',
    },
    'admin_portal_sub': {
      'en': 'Approvals, audit reports, staff & site management',
      'hi': 'अनुमोदन, ऑडिट रिपोर्ट, स्टाफ और साइट प्रबंधन',
    },

    // ─── Sites & Location ───
    'select_site': {
      'en': 'Select Site',
      'hi': 'साइट चुनें',
    },
    'select_location': {
      'en': 'Select Location',
      'hi': 'स्थान चुनें',
    },
    'construction_site': {
      'en': 'Construction Site',
      'hi': 'निर्माण साइट',
    },
    'head_office': {
      'en': 'Head Office',
      'hi': 'प्रधान कार्यालय',
    },
    'active': {
      'en': 'Active',
      'hi': 'सक्रिय',
    },
    'completed': {
      'en': 'Completed',
      'hi': 'पूर्ण',
    },
    'search_sites': {
      'en': 'Search sites...',
      'hi': 'साइट खोजें...',
    },
    'no_sites_found': {
      'en': 'No sites found',
      'hi': 'कोई साइट नहीं मिली',
    },
    'manage_sites': {
      'en': 'Manage Sites',
      'hi': 'साइट प्रबंधन',
    },
    'add_new_site': {
      'en': 'Add New Site',
      'hi': 'नई साइट जोड़ें',
    },
    'edit_site': {
      'en': 'Edit Site',
      'hi': 'साइट संपादित करें',
    },
    'attendance_area': {
      'en': 'Attendance Area',
      'hi': 'हाजिरी क्षेत्र',
    },
    'enter_attendance_area': {
      'en': 'Enter Attendance Area',
      'hi': 'हाजिरी क्षेत्र निर्धारित करें',
    },
    'set_to_my_location': {
      'en': 'Set to My Current Location',
      'hi': '📍 वर्तमान स्थान सेट करें',
    },
    'capturing_gps': {
      'en': 'Capturing GPS...',
      'hi': 'जीपीएस प्राप्त किया जा रहा है...',
    },
    'google_maps_link_or_coords': {
      'en': 'Google Maps Link or Coordinates',
      'hi': 'गूगल मैप्स लिंक या निर्देशांक',
    },
    'paste_maps_url': {
      'en': 'Paste Google Maps URL or lat,lng',
      'hi': 'गूगल मैप्स लिंक या अक्षांश,देशांतर पेस्ट करें',
    },
    'latitude': {
      'en': 'Latitude',
      'hi': 'अक्षांश (Latitude)',
    },
    'longitude': {
      'en': 'Longitude',
      'hi': 'देशांतर (Longitude)',
    },
    'allowed_radius': {
      'en': 'Allowed Attendance Radius',
      'hi': 'अनुमत हाजिरी परिधि',
    },
    'verify_on_google_maps': {
      'en': 'Verify Location on Google Maps',
      'hi': 'गूगल मैप्स पर स्थान जांचें',
    },
    'save_attendance_area': {
      'en': 'Save Attendance Area',
      'hi': 'हाजिरी क्षेत्र सुरक्षित करें',
    },

    // ─── Login & Auth ───
    'management_login': {
      'en': 'Management Login',
      'hi': 'प्रबंधन लॉगिन',
    },
    'management_login_sub': {
      'en': 'Sign in with your Admin or Accounts credentials',
      'hi': 'अपने एडमिन या अकाउंट्स क्रेडेंशियल्स से साइन इन करें',
    },
    'email_address': {
      'en': 'Email Address',
      'hi': 'ईमेल पता',
    },
    'password': {
      'en': 'Password',
      'hi': 'पासवर्ड',
    },
    'sign_in': {
      'en': 'Sign In',
      'hi': 'साइन इन करें',
    },
    'site_staff_login': {
      'en': 'Site Staff Login',
      'hi': 'साइट स्टाफ लॉगिन',
    },
    'select_staff_member': {
      'en': 'Select Staff Member',
      'hi': 'कर्मचारी चुनें',
    },
    'enter_pin_or_password': {
      'en': 'Enter PIN or Password',
      'hi': 'पिन या पासवर्ड दर्ज करें',
    },
    'enter_admin_pin': {
      'en': 'Enter Admin Access Code',
      'hi': 'एडमिन एक्सेस कोड दर्ज करें',
    },
    'login_btn': {
      'en': 'Login',
      'hi': 'लॉगिन करें',
    },
    'invalid_pin': {
      'en': 'Invalid PIN or Password',
      'hi': 'अमान्य पिन या पासवर्ड',
    },
    'logged_in_as': {
      'en': 'Logged in as',
      'hi': 'लॉगिन किया गया:',
    },
    'switch_user': {
      'en': 'Switch User',
      'hi': 'यूज़र बदलें',
    },
    'logout': {
      'en': 'Logout',
      'hi': 'लॉगआउट',
    },

    // ─── Stock Management Screens ───
    'stock_inward': {
      'en': 'Stock Inward (Material In)',
      'hi': 'सामग्री आवक (स्टॉक इन)',
    },
    'stock_inward_sub': {
      'en': 'Receive materials from suppliers with challan details',
      'hi': 'सप्लायर से चालान विवरण सहित सामग्री प्राप्त करें',
    },
    'stock_outward': {
      'en': 'Stock Outward (Material Usage)',
      'hi': 'सामग्री खपत (स्टॉक आउट)',
    },
    'stock_outward_sub': {
      'en': 'Issue materials for site construction work',
      'hi': 'साइट निर्माण कार्य हेतु सामग्री जारी करें',
    },
    'stock_history': {
      'en': 'Stock History & Balances',
      'hi': 'स्टॉक इतिहास व शेष मात्रा',
    },
    'stock_history_sub': {
      'en': 'View all transactions and current stock in hand',
      'hi': 'सभी लेन-देन और वर्तमान उपलब्ध स्टॉक देखें',
    },
    'material_name': {
      'en': 'Material Name',
      'hi': 'सामग्री का नाम',
    },
    'quantity': {
      'en': 'Quantity',
      'hi': 'मात्रा',
    },
    'unit': {
      'en': 'Unit',
      'hi': 'इकाई',
    },
    'vendor_supplier': {
      'en': 'Vendor / Supplier Name',
      'hi': 'सप्लायर / वेंडर का नाम',
    },
    'challan_no': {
      'en': 'Challan / Bill Number',
      'hi': 'चालान / बिल नंबर',
    },
    'vehicle_no': {
      'en': 'Vehicle Number',
      'hi': 'गाड़ी नंबर',
    },
    'receiver_name': {
      'en': 'Received By',
      'hi': 'प्राप्तकर्ता का नाम',
    },
    'issued_to': {
      'en': 'Issued To / Used By',
      'hi': 'किसे जारी किया गया',
    },
    'purpose_work': {
      'en': 'Purpose / Work Section',
      'hi': 'उपयोग का उद्देश्य / कार्य विवरण',
    },
    'in_stock': {
      'en': 'In Stock',
      'hi': 'स्टॉक में उपलब्ध',
    },
    'low_stock_alert': {
      'en': 'Low Stock Alert',
      'hi': 'कम स्टॉक चेतावनी',
    },
    'add_product_title': {
      'en': 'Add Inward Material',
      'hi': 'आवक सामग्री दर्ज करें',
    },
    'use_product_title': {
      'en': 'Record Material Usage',
      'hi': 'सामग्री खपत दर्ज करें',
    },

    // ─── Cash Book Screens ───
    'cash_in_hand': {
      'en': 'Cash in Hand',
      'hi': 'उपलब्ध नकद राशि (हाथ में रोकड़)',
    },
    'record_expense': {
      'en': 'Record Expense',
      'hi': 'खर्च दर्ज करें',
    },
    'add_cash': {
      'en': 'Add Cash / Receipt',
      'hi': 'नकद प्राप्त करें / रसीद',
    },
    'expense_details': {
      'en': 'Expense Details',
      'hi': 'खर्च विवरण',
    },
    'amount': {
      'en': 'Amount (₹)',
      'hi': 'राशि (₹)',
    },
    'category': {
      'en': 'Category',
      'hi': 'खर्च श्रेणी',
    },
    'cat_diesel': {
      'en': 'Diesel & Fuel',
      'hi': 'डीजल और ईंधन',
    },
    'cat_labour': {
      'en': 'Labour & Wages',
      'hi': 'मजदूरी व लेबर',
    },
    'cat_material': {
      'en': 'Local Material Purchase',
      'hi': 'स्थानीय सामग्री खरीद',
    },
    'cat_machinery': {
      'en': 'Machinery Repair & Maintenance',
      'hi': 'मशीनरी मरम्मत व रखरखाव',
    },
    'cat_transport': {
      'en': 'Transport & Freight',
      'hi': 'परिवहन व भाड़ा',
    },
    'cat_food': {
      'en': 'Food & Refreshment',
      'hi': 'खान-पान व चाय नाश्ता',
    },
    'cat_misc': {
      'en': 'Miscellaneous',
      'hi': 'अन्य खर्च',
    },
    'payment_mode': {
      'en': 'Payment Mode',
      'hi': 'भुगतान माध्यम',
    },
    'mode_cash': {
      'en': 'Cash',
      'hi': 'नकद (Cash)',
    },
    'mode_upi': {
      'en': 'UPI / Online',
      'hi': 'यूपीआई / ऑनलाइन',
    },
    'mode_bank': {
      'en': 'Bank Transfer',
      'hi': 'बैंक ट्रांसफर',
    },
    'paid_to': {
      'en': 'Paid To (Person / Vendor)',
      'hi': 'भुगतान प्राप्तकर्ता (व्यक्ति / फर्म)',
    },
    'voucher_no': {
      'en': 'Voucher / Bill No',
      'hi': 'वाउचर / बिल नंबर',
    },
    'upload_receipt': {
      'en': 'Upload Bill / Receipt Photo',
      'hi': 'बिल / रसीद की फोटो संलग्न करें',
    },
    'cash_history': {
      'en': 'Cash History',
      'hi': 'कैश लेन-देन इतिहास',
    },
    'todays_expenses': {
      'en': "Today's Expenses",
      'hi': 'आज का कुल खर्च',
    },
    'months_expenses': {
      'en': "This Month's Expenses",
      'hi': 'इस महीने का कुल खर्च',
    },

    // ─── Attendance & Punch Screens ───
    'mark_attendance': {
      'en': 'Mark Attendance',
      'hi': 'हाजिरी लगाएं',
    },
    'punch_in': {
      'en': 'Punch In',
      'hi': 'पंच इन करें',
    },
    'punch_out': {
      'en': 'Punch Out',
      'hi': 'पंच आउट करें',
    },
    'punch_in_success': {
      'en': 'Punch In successful!',
      'hi': 'पंच इन सफलतापूर्वक हो गया!',
    },
    'punch_out_success': {
      'en': 'Punch Out successful!',
      'hi': 'पंच आउट सफलतापूर्वक हो गया!',
    },
    'present': {
      'en': 'Present',
      'hi': 'उपस्थित',
    },
    'late': {
      'en': 'Late',
      'hi': 'विलंब (लेट)',
    },
    'absent': {
      'en': 'Absent',
      'hi': 'अनुपस्थित',
    },
    'regularized': {
      'en': 'Regularized',
      'hi': 'नियमितीकृत (स्वीकृत)',
    },
    'shift_timing': {
      'en': 'Shift Timing',
      'hi': 'शिफ्ट का समय',
    },
    'in_time': {
      'en': 'In Time',
      'hi': 'आगमन समय (इन)',
    },
    'out_time': {
      'en': 'Out Time',
      'hi': 'प्रस्थान समय (आउट)',
    },
    'total_hours': {
      'en': 'Total Hours',
      'hi': 'कुल कार्य घंटे',
    },
    'gps_status': {
      'en': 'GPS Location Status',
      'hi': 'जीपीएस स्थान स्थिति',
    },
    'within_site': {
      'en': 'Within Site Attendance Area',
      'hi': 'साइट हाजिरी क्षेत्र के अंदर',
    },
    'outside_site': {
      'en': 'Outside Attendance Area',
      'hi': 'हाजिरी क्षेत्र से बाहर',
    },
    'distance_to_site': {
      'en': 'Distance to Site',
      'hi': 'साइट से दूरी',
    },
    'meters': {
      'en': 'meters',
      'hi': 'मीटर',
    },
    'late_by': {
      'en': 'Late by',
      'hi': 'देरी:',
    },
    'minutes': {
      'en': 'minutes',
      'hi': 'मिनट',
    },
    'lockout_title': {
      'en': 'Attendance Lockout (>40m Late)',
      'hi': 'हाजिरी लॉकआउट (40 मिनट से अधिक लेट)',
    },
    'lockout_msg': {
      'en': 'You are more than 40 minutes late. Punch-in is locked until Admin approves your late arrival request.',
      'hi': 'आप 40 मिनट से अधिक लेट हैं। जब तक एडमिन आपका अनुरोध स्वीकृत नहीं करता, हाजिरी लॉक रहेगी।',
    },
    'request_regularization': {
      'en': 'Request Late Regularization',
      'hi': 'विलंब नियमितीकरण का अनुरोध करें',
    },
    'enter_late_reason': {
      'en': 'Enter clear reason for late arrival...',
      'hi': 'देरी का स्पष्ट कारण लिखें...',
    },
    'request_submitted': {
      'en': 'Request submitted to Admin for approval',
      'hi': 'स्वीकृति हेतु एडमिन को अनुरोध भेज दिया गया है',
    },
    'take_selfie': {
      'en': 'Take Attendance Selfie',
      'hi': 'हाजिरी सेल्फी लें',
    },
    'retake_photo': {
      'en': 'Retake Photo',
      'hi': 'पुनः फोटो लें',
    },
    'todays_pulse': {
      'en': "Today's Attendance Pulse",
      'hi': 'आज की हाजिरी स्थिति (पल्स)',
    },
    'all_locations': {
      'en': 'All Locations',
      'hi': 'सभी स्थान',
    },
    'live_location': {
      'en': 'Live Location Radar',
      'hi': 'लाइव स्थान रडार',
    },
    'monthly_report': {
      'en': 'Monthly Report',
      'hi': 'मासिक रिपोर्ट',
    },
    'export_excel': {
      'en': 'Export Excel Sheet',
      'hi': 'एक्सेल शीट डाउनलोड करें',
    },

    // ─── Daily Site Report Screens ───
    'record_dsr': {
      'en': 'Record Daily Site Report',
      'hi': 'दैनिक साइट रिपोर्ट दर्ज करें',
    },
    'record_voice_note': {
      'en': 'Record Voice Summary',
      'hi': 'आवाज में सारांश रिकॉर्ड करें',
    },
    'recording': {
      'en': 'Recording in progress...',
      'hi': 'रिकॉर्डिंग जारी है...',
    },
    'tap_to_record': {
      'en': 'Tap mic to start speaking in Hindi or English',
      'hi': 'हिन्दी या अंग्रेजी में बोलने के लिए माइक दबाएं',
    },
    'transcribing': {
      'en': 'Transcribing & Structuring Report...',
      'hi': 'रिपोर्ट तैयार की जा रही है...',
    },
    'work_done': {
      'en': 'Work Done Today',
      'hi': 'आज किया गया कार्य',
    },
    'manpower_count': {
      'en': 'Manpower Deployed',
      'hi': 'कुल मजदूर / मैनपॉवर',
    },
    'machinery_used': {
      'en': 'Machinery Used',
      'hi': 'उपयोग की गई मशीनरी',
    },
    'weather_condition': {
      'en': 'Weather Condition',
      'hi': 'मौसम की स्थिति',
    },
    'site_photos': {
      'en': 'Site Photos',
      'hi': 'साइट की तस्वीरें',
    },
    'add_photos': {
      'en': 'Add Photos',
      'hi': 'फोटो जोड़ें',
    },

    // ─── Admin & Staff ───
    'admin_dashboard': {
      'en': 'Admin Dashboard',
      'hi': 'एडमिन डैशबोर्ड',
    },
    'all_staff': {
      'en': 'Manage Staff Members',
      'hi': 'कर्मचारी प्रबंधन',
    },
    'add_staff': {
      'en': 'Add Staff Member',
      'hi': 'नया कर्मचारी जोड़ें',
    },
    'staff_name': {
      'en': 'Full Name',
      'hi': 'पूरा नाम',
    },
    'phone_number': {
      'en': 'Phone Number',
      'hi': 'फ़ोन नंबर',
    },
    'assigned_roles': {
      'en': 'Assigned Module Access',
      'hi': 'अनुमत मॉड्यूल एक्सेस',
    },
    'staff_role': {
      'en': 'Role / Designation',
      'hi': 'पद / भूमिका',
    },
    'review_approvals': {
      'en': 'Review Approvals',
      'hi': 'स्वीकृति समीक्षा',
    },
    'approve': {
      'en': 'Approve',
      'hi': 'स्वीकृत करें',
    },
    'reject': {
      'en': 'Reject',
      'hi': 'अस्वीकृत करें',
    },
    'cashflow_summary': {
      'en': 'Cashflow Summary',
      'hi': 'कैशफ्लो विवरण',
    },

    // ─── Common UI Actions ───
    'submit': {
      'en': 'Submit',
      'hi': 'सबमिट करें',
    },
    'save': {
      'en': 'Save',
      'hi': 'सुरक्षित करें',
    },
    'cancel': {
      'en': 'Cancel',
      'hi': 'रद्द करें',
    },
    'confirm': {
      'en': 'Confirm',
      'hi': 'पुष्टि करें',
    },
    'delete': {
      'en': 'Delete',
      'hi': 'हटाएं',
    },
    'edit': {
      'en': 'Edit',
      'hi': 'संपादित करें',
    },
    'update': {
      'en': 'Update',
      'hi': 'अपडेट करें',
    },
    'close': {
      'en': 'Close',
      'hi': 'बंद करें',
    },
    'back': {
      'en': 'Back',
      'hi': 'वापस',
    },
    'search': {
      'en': 'Search...',
      'hi': 'खोजें...',
    },
    'filter': {
      'en': 'Filter',
      'hi': 'फ़िल्टर',
    },
    'loading': {
      'en': 'Loading...',
      'hi': 'लोड हो रहा है...',
    },
    'please_wait': {
      'en': 'Please wait...',
      'hi': 'कृपया प्रतीक्षा करें...',
    },
    'success': {
      'en': 'Success',
      'hi': 'सफलता',
    },
    'error': {
      'en': 'Error',
      'hi': 'त्रुटि',
    },
    'yes': {
      'en': 'Yes',
      'hi': 'हाँ',
    },
    'no': {
      'en': 'No',
      'hi': 'नहीं',
    },
    'date': {
      'en': 'Date',
      'hi': 'तारीख',
    },
    'time': {
      'en': 'Time',
      'hi': 'समय',
    },
    'status': {
      'en': 'Status',
      'hi': 'स्थिति',
    },
    'remarks': {
      'en': 'Remarks',
      'hi': 'टिप्पणी / विवरण',
    },
    'details': {
      'en': 'Details',
      'hi': 'विवरण',
    },
    'offline_banner': {
      'en': 'Offline Mode - Changes will sync when online',
      'hi': 'ऑफ़लाइन मोड - इंटरनेट आने पर डेटा सिंक हो जाएगा',
    },

    // ─── Daily Site Report (DSR) & Voice-to-Text Addons ───
    'daily_work_report': {
      'en': 'Daily Work Report',
      'hi': 'दैनिक कार्य प्रगति रिपोर्ट',
    },
    'reporting_staff': {
      'en': 'REPORTING STAFF (SUBMITTED BY)',
      'hi': 'रिपोर्टिंग कर्मचारी (प्रस्तुतकर्ता)',
    },
    'select_reporting_staff': {
      'en': 'Select who is entering this Daily Site Report. The approved report will be stamped with this person\'s name.',
      'hi': 'दैनिक रिपोर्ट दर्ज करने वाले कर्मचारी को चुनें। स्वीकृत रिपोर्ट पर इस कर्मचारी का नाम दर्ज होगा।',
    },
    'submitted_by': {
      'en': 'Submitted by',
      'hi': 'द्वारा प्रस्तुत',
    },
    'project_head_approved': {
      'en': 'Project Head Approved',
      'hi': 'प्रोजेक्ट हेड द्वारा स्वीकृत',
    },
    'project_head_review_pending': {
      'en': 'Project Head Review: Pending',
      'hi': 'प्रोजेक्ट हेड समीक्षा: लंबित',
    },
    'no_approved_reports': {
      'en': 'No Approved Reports',
      'hi': 'कोई स्वीकृत रिपोर्ट नहीं',
    },
    'no_approved_reports_today': {
      'en': 'No daily site reports have been approved by the Project Head yet today.',
      'hi': 'आज के लिए प्रोजेक्ट हेड द्वारा अभी तक कोई दैनिक रिपोर्ट स्वीकृत नहीं की गई है।',
    },
    'view_todays_reports': {
      'en': 'View Today\'s Reports',
      'hi': 'आज की रिपोर्ट देखें',
    },
    'check_yesterday_reports': {
      'en': 'Check Yesterday\'s Reports',
      'hi': 'कल की रिपोर्ट देखें',
    },
    'back_to_today': {
      'en': 'Back to Today',
      'hi': 'आज पर वापस आएं',
    },
    'yesterday': {
      'en': 'Yesterday',
      'hi': 'कल',
    },
    'today': {
      'en': 'Today',
      'hi': 'आज',
    },
    'next_day': {
      'en': 'Next Day',
      'hi': 'अगला दिन',
    },
    'dsr_entry': {
      'en': 'DSR Entry',
      'hi': 'DSR प्रविष्टि',
    },
    'voice_to_text': {
      'en': 'Voice-to-Text',
      'hi': 'बोलकर लिखें (वॉइस टू टेक्स्ट)',
    },
    'whisper_ai': {
      'en': 'Whisper AI (Extreme Accuracy)',
      'hi': 'व्हिस्पर एआई (अत्यधिक सटीक)',
    },
    'live_dictation': {
      'en': 'Live Dictation',
      'hi': 'लाइव डिक्टेशन',
    },
    'site_photos_evidence': {
      'en': 'SITE PHOTOS (EVIDENCE)',
      'hi': 'साइट तस्वीरें (प्रमाण)',
    },
    'speak_work_update': {
      'en': 'Speak or type today\'s work update...',
      'hi': 'आज किए गए कार्य की जानकारी बोलें या लिखें...',
    },
    'voice_settings': {
      'en': 'Voice Settings',
      'hi': 'आवाज़ सेटिंग्स',
    },
    'photos_attached': {
      'en': 'site photos attached',
      'hi': 'साइट तस्वीरें संलग्न हैं',
    },

    // ─── Notice Board & Announcements ───
    'notice_board': {
      'en': 'Notice Board & Broadcasts',
      'hi': 'सूचना पट्ट एवं प्रसारण',
    },
    'post_notice': {
      'en': 'Post Notice',
      'hi': 'सूचना जारी करें',
    },
    'active_notices': {
      'en': 'Official Broadcasts, Zoom Meetings & Staff Announcements',
      'hi': 'आधिकारिक प्रसारण, ज़ूम मीटिंग्स और कर्मचारी सूचनाएं',
    },
    'all_notices': {
      'en': 'All Notices',
      'hi': 'सभी सूचनाएं',
    },
    'zoom_meetings': {
      'en': 'Zoom Meetings',
      'hi': 'ज़ूम मीटिंग्स',
    },
    'urgent_alerts': {
      'en': 'Urgent Alerts',
      'hi': 'अति आवश्यक सूचनाएं',
    },
    'broadcast_to_all': {
      'en': 'Broadcast to All Staff & Sites',
      'hi': 'सभी कर्मचारियों व साइट्स को प्रसारित',
    },
    'publish_notice': {
      'en': 'Publish Notice',
      'hi': 'सूचना प्रकाशित करें',
    },
    'enter_notice_title': {
      'en': 'Notice Title',
      'hi': 'सूचना का शीर्षक',
    },
    'enter_notice_details': {
      'en': 'Notice Details / Instructions',
      'hi': 'सूचना का विवरण व निर्देश',
    },
    'no_active_notices': {
      'en': 'No active notices right now',
      'hi': 'वर्तमान में कोई सक्रिय सूचना नहीं है',
    },
    'join_zoom_meeting': {
      'en': 'Join Zoom Meeting',
      'hi': 'ज़ूम मीटिंग में शामिल हों',
    },

    // ─── Indore Head Office & Construction Sites ───
    'indore_head_office': {
      'en': 'Indore Head Office',
      'hi': 'इंदौर प्रधान कार्यालय',
    },
    'indore_office_reports': {
      'en': 'HEAD OFFICE (INDORE OFFICE REPORTS)',
      'hi': 'प्रधान कार्यालय (इंदौर ऑफिस रिपोर्ट)',
    },
    'indore_office_attendance': {
      'en': 'HEAD OFFICE (OFFICE ATTENDANCE)',
      'hi': 'प्रधान कार्यालय (इंदौर ऑफिस हाजिरी)',
    },
    'office_reports_badge': {
      'en': 'Office Reports',
      'hi': 'कार्यालय रिपोर्ट',
    },
    'office_attendance_badge': {
      'en': 'Office Attendance',
      'hi': 'कार्यालय हाजिरी',
    },
    'construction_sites': {
      'en': 'CONSTRUCTION SITES',
      'hi': 'निर्माण साइट्स',
    },
    'active_badge': {
      'en': 'Active',
      'hi': 'सक्रिय',
    },
    'storage_cache': {
      'en': 'Storage & Cache',
      'hi': 'मेमोरी व कैश प्रबंधन',
    },
    'sign_out': {
      'en': 'Sign Out',
      'hi': 'साइन आउट',
    },
    'dashboard': {
      'en': 'Dashboard',
      'hi': 'डैशबोर्ड',
    },
    'home': {
      'en': 'Home',
      'hi': 'होम',
    },
  };

  /// Translate a given key based on language code ('en' or 'hi')
  static String tr(String key, String langCode, {String? defaultText}) {
    final entry = _translations[key];
    if (entry != null) {
      final translated = entry[langCode] ?? entry['en'];
      if (translated != null && translated.isNotEmpty) {
        return translated;
      }
    }
    return defaultText ?? key;
  }

  /// Convenience lookup using BuildContext with reactive InheritedWidget subscription.
  static String of(BuildContext context, String key, {String? defaultText}) {
    // 1. Check Flutter's inherited Localizations widget so this BuildContext
    // automatically registers an InheritedWidget dependency and rebuilds immediately on locale change!
    final localizationsLocale = Localizations.maybeLocaleOf(context);
    if (localizationsLocale != null) {
      return tr(key, localizationsLocale.languageCode, defaultText: defaultText);
    }

    // 2. Fallback to ProviderScope if Localizations is not in tree yet
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final locale = container.read(localeProvider);
      return tr(key, locale.languageCode, defaultText: defaultText);
    } catch (_) {
      // Fallback to English
      return tr(key, 'en', defaultText: defaultText);
    }
  }
}

/// Extension on BuildContext for quick and clean translation calls:
/// Example: `Text(context.tr('stock_management'))`
extension LocalizedContextExtension on BuildContext {
  String tr(String key, {String? defaultText}) {
    return AppStrings.of(this, key, defaultText: defaultText);
  }
}
