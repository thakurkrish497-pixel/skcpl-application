import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/site_staff_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/photo_viewer_dialog.dart';
import 'employee_performance_screen.dart';

/// Screen for Admin to manage site staff (Workers and Supervisors) with unified
/// multi-module authorizations (Attendance, Cashbook, Daily Report, Stock),
/// duplicate name disambiguation, and 360° performance analytics.
class ManageSiteStaffScreen extends ConsumerStatefulWidget {
  final SiteModel site;

  const ManageSiteStaffScreen({super.key, required this.site});

  @override
  ConsumerState<ManageSiteStaffScreen> createState() =>
      _ManageSiteStaffScreenState();
}

class _ManageSiteStaffScreenState extends ConsumerState<ManageSiteStaffScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> get _tabNames => widget.site.isHeadOffice
      ? const ['All Staff', 'Attendance', 'Daily Report']
      : const ['All Staff', 'Attendance', 'Cashbook', 'Daily Report', 'Stock'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    Future.microtask(() {
      ref.read(siteStaffProvider(widget.site.id).notifier).loadStaff();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  StaffModule? get _filterModuleForTab {
    if (widget.site.isHeadOffice) {
      switch (_tabController.index) {
        case 1:
          return StaffModule.attendance;
        case 2:
          return StaffModule.report;
        default:
          return null;
      }
    }
    switch (_tabController.index) {
      case 1:
        return StaffModule.attendance;
      case 2:
        return StaffModule.cashbook;
      case 3:
        return StaffModule.report;
      case 4:
        return StaffModule.stock;
      default:
        return null; // All Staff
    }
  }

  Future<void> _pickDocPhoto({
    required BuildContext docCtx,
    required void Function(Uint8List bytes, String fileName) onPicked,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: docCtx,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: const Text('Take Photo with Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(bCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.secondary),
              title: const Text('Choose from Gallery / Files', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(bCtx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      onPicked(bytes, xfile.name);
    }
  }

  void _showAddStaffDialog([SiteStaffModel? existing, StaffModule? defaultModule]) {
    final isOffice = widget.site.isHeadOffice;
    final isEditing = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final pinController = TextEditingController(text: existing?.pin ?? '1234');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final empCodeController = TextEditingController(text: existing?.employeeCode ?? '');
    final designationController = TextEditingController(text: existing?.designation ?? '');
    final fatherNameController = TextEditingController(text: existing?.fatherName ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');

    DateTime? selectedDob = existing?.dateOfBirth;
    final aadharController = TextEditingController(text: existing?.aadharNumber ?? '');
    final panController = TextEditingController(text: existing?.panNumber ?? '');
    Uint8List? aadharBytes;
    String? aadharFileName;
    String? currentAadharUrl = existing?.aadharCardUrl;
    Uint8List? panBytes;
    String? panFileName;
    String? currentPanUrl = existing?.panCardUrl;

    SiteStaffRole selectedRole = existing?.role ?? SiteStaffRole.worker;

    // Multi-module selection: default to active tab's module or all common modules
    Set<StaffModule> selectedModules = existing != null
        ? existing.modules.toSet()
        : (defaultModule != null
            ? {defaultModule}
            : (isOffice
                ? {StaffModule.attendance, StaffModule.report}
                : {StaffModule.attendance, StaffModule.cashbook, StaffModule.report}));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isEditing
                    ? (isOffice ? 'Edit Office Staff Profile' : 'Edit Staff Member')
                    : (isOffice ? 'Add Office Staff Member' : 'Add Staff Member'),
                style: AppTextStyles.h4,
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full Name
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: isOffice ? 'Employee Full Name *' : 'Full Name *',
                      hintText: 'e.g. Ram Sharma',
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),



                  // Multi-Module Authorization Checkboxes
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.checklist_rounded, size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Authorized Modules (Tick all that apply) *',
                              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isOffice
                              ? 'Indore Head Office staff can be authorized for Attendance and Daily Work Reports.'
                              : 'If an option is unticked, this employee will NOT see their name in that feature.',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                        ),
                        const Divider(height: 16),
                        ...StaffModule.values.map((mod) {
                          if (isOffice && mod != StaffModule.attendance && mod != StaffModule.report) {
                            return const SizedBox.shrink();
                          }
                          final isChecked = selectedModules.contains(mod);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            activeColor: AppColors.primary,
                            title: Text(
                              mod.displayName,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isChecked ? AppColors.textPrimary : AppColors.textSecondary,
                                fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            value: isChecked,
                            onChanged: (bool? checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedModules.add(mod);
                                } else {
                                  selectedModules.remove(mod);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Login Password / PIN
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Login Password / PIN *',
                      hintText: 'e.g. 9826011223 or ram@123',
                      helperText: 'Admin can set letters or numbers of any length',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Duplicate Disambiguation Header
                  Text(
                    'Optional Details (Differentiates Duplicate Names):',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: empCodeController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Employee ID / Code',
                            hintText: 'e.g. SK-01',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: designationController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: isOffice ? 'Designation / Department' : 'Designation / Trade',
                            hintText: isOffice ? 'e.g. Accounts, HR, Manager' : 'e.g. Senior Mason',
                            prefixIcon: const Icon(Icons.work_outline),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fatherNameController,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: "Father's Name",
                            hintText: 'e.g. S/o Rameshwar',
                            prefixIcon: Icon(Icons.family_restroom_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Contact Phone',
                            hintText: 'e.g. 9826011223',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: descController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'General Notes (Optional)',
                      hintText: 'e.g. Joined Oct 2026, permanent staff',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Verification & KYC Documents ──
                  Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, color: AppColors.waveCyan, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Birth Date & KYC Verification Documents:',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.waveCyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Date of Birth Field
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cake_outlined, color: AppColors.goldAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Date of Birth',
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                              ),
                              Text(
                                selectedDob != null
                                    ? '${DateFormat('dd MMM yyyy').format(selectedDob!)}${selectedDob != null ? ' (${DateTime.now().year - selectedDob!.year} yrs old)' : ''}'
                                    : 'Tap to select Birth Date',
                                style: TextStyle(
                                  color: selectedDob != null ? Colors.white : AppColors.textSecondary,
                                  fontWeight: selectedDob != null ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selectedDob != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: AppColors.textTertiary),
                            onPressed: () => setDialogState(() => selectedDob = null),
                          ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceDark,
                            foregroundColor: AppColors.waveCyan,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: AppColors.divider),
                            ),
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDob ?? DateTime(1995, 1, 1),
                              firstDate: DateTime(1940),
                              lastDate: now,
                              builder: (context, child) {
                                return Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: AppColors.waveCyan,
                                      onPrimary: Colors.black,
                                      surface: AppColors.surfaceDark,
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDob = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month_rounded, size: 14),
                          label: const Text('Pick Date', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Aadhar Card / Extra Document Field & Attachment
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.badge_outlined, color: AppColors.waveCyan, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Extra Verification Document (Aadhar)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            if (aadharBytes != null || (currentAadharUrl != null && currentAadharUrl!.isNotEmpty))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.approved.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: AppColors.approved, size: 12),
                                    SizedBox(width: 4),
                                    Text('Doc Attached', style: TextStyle(color: AppColors.approved, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: aadharController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Aadhar / ID Number (Optional)',
                            hintText: 'e.g. 5421 8976 1234',
                            prefixIcon: Icon(Icons.fingerprint_rounded),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (aadharBytes != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(aadharBytes!, width: 44, height: 44, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                            ] else if (currentAadharUrl != null && currentAadharUrl!.isNotEmpty) ...[
                              InkWell(
                                onTap: () => PhotoViewerDialog.show(context, [currentAadharUrl!]),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(currentAadharUrl!, width: 44, height: 44, fit: BoxFit.cover),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.waveCyan,
                                  side: const BorderSide(color: AppColors.waveCyan),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _pickDocPhoto(
                                  docCtx: context,
                                  onPicked: (bytes, name) {
                                    setDialogState(() {
                                      aadharBytes = bytes;
                                      aadharFileName = name;
                                    });
                                  },
                                ),
                                icon: const Icon(Icons.upload_file_rounded, size: 16),
                                label: Text(
                                  aadharBytes != null || (currentAadharUrl != null && currentAadharUrl!.isNotEmpty)
                                      ? 'Change Document Photo / Scan'
                                      : 'Attach Aadhar / ID Photo or Scan',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                            if (aadharBytes != null || (currentAadharUrl != null && currentAadharUrl!.isNotEmpty))
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.rejected, size: 18),
                                tooltip: 'Remove Document',
                                onPressed: () => setDialogState(() {
                                  aadharBytes = null;
                                  currentAadharUrl = null;
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // PAN Card Field & Attachment
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.credit_card_rounded, color: AppColors.goldAccent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'PAN Card Details (Optional)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            if (panBytes != null || (currentPanUrl != null && currentPanUrl!.isNotEmpty))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.approved.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: AppColors.approved, size: 12),
                                    SizedBox(width: 4),
                                    Text('Card Attached', style: TextStyle(color: AppColors.approved, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: panController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'PAN Number (10 Characters)',
                            hintText: 'e.g. ABCDE1234F',
                            prefixIcon: Icon(Icons.credit_card_outlined),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (panBytes != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(panBytes!, width: 44, height: 44, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                            ] else if (currentPanUrl != null && currentPanUrl!.isNotEmpty) ...[
                              InkWell(
                                onTap: () => PhotoViewerDialog.show(context, [currentPanUrl!]),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(currentPanUrl!, width: 44, height: 44, fit: BoxFit.cover),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.goldAccent,
                                  side: const BorderSide(color: AppColors.goldAccent),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _pickDocPhoto(
                                  docCtx: context,
                                  onPicked: (bytes, name) {
                                    setDialogState(() {
                                      panBytes = bytes;
                                      panFileName = name;
                                    });
                                  },
                                ),
                                icon: const Icon(Icons.upload_file_rounded, size: 16),
                                label: Text(
                                  panBytes != null || (currentPanUrl != null && currentPanUrl!.isNotEmpty)
                                      ? 'Change PAN Photo / Scan'
                                      : 'Attach PAN Card Photo or Scan',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                            if (panBytes != null || (currentPanUrl != null && currentPanUrl!.isNotEmpty))
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.rejected, size: 18),
                                tooltip: 'Remove Card',
                                onPressed: () => setDialogState(() {
                                  panBytes = null;
                                  currentPanUrl = null;
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final name = nameController.text.trim();
                final pin = pinController.text.trim();
                if (name.isEmpty || pin.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter Full Name and Login Password'),
                      backgroundColor: AppColors.rejected,
                    ),
                  );
                  return;
                }

                if (selectedModules.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please tick at least one module for this staff member'),
                      backgroundColor: AppColors.rejected,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                final phone = phoneController.text.trim().isEmpty ? null : phoneController.text.trim();
                final code = empCodeController.text.trim().isEmpty ? null : empCodeController.text.trim();
                final designation = designationController.text.trim().isEmpty ? null : designationController.text.trim();
                final father = fatherNameController.text.trim().isEmpty ? null : fatherNameController.text.trim();
                final desc = descController.text.trim().isEmpty ? null : descController.text.trim();
                final aadharNum = aadharController.text.trim().isEmpty ? null : aadharController.text.trim();
                final panNum = panController.text.trim().isEmpty ? null : panController.text.trim().toUpperCase();

                try {
                  // Upload Aadhar card photo if a new file was chosen
                  String? finalAadharUrl = currentAadharUrl;
                  if (aadharBytes != null) {
                    try {
                      final storage = StorageService();
                      final cleanName = aadharFileName ?? 'aadhar.jpg';
                      finalAadharUrl = await storage.uploadPhotoBytes(
                        aadharBytes!,
                        fileName: 'aadhar_${name}_$cleanName',
                      );
                    } catch (uploadErr) {
                      debugPrint('Aadhar upload error: $uploadErr');
                    }
                  }

                  // Upload PAN card photo if a new file was chosen
                  String? finalPanUrl = currentPanUrl;
                  if (panBytes != null) {
                    try {
                      final storage = StorageService();
                      final cleanName = panFileName ?? 'pan.jpg';
                      finalPanUrl = await storage.uploadPhotoBytes(
                        panBytes!,
                        fileName: 'pan_${name}_$cleanName',
                      );
                    } catch (uploadErr) {
                      debugPrint('PAN upload error: $uploadErr');
                    }
                  }

                  if (isEditing) {
                    final updated = existing.copyWith(
                      name: name,
                      role: selectedRole,
                      modules: selectedModules.toList(),
                      pin: pin,
                      phone: phone,
                      employeeCode: code,
                      designation: designation,
                      fatherName: father,
                      description: desc,
                      dateOfBirth: selectedDob,
                      aadharNumber: aadharNum,
                      aadharCardUrl: finalAadharUrl,
                      panNumber: panNum,
                      panCardUrl: finalPanUrl,
                    );
                    await ref
                        .read(siteStaffProvider(widget.site.id).notifier)
                        .updateStaff(updated);
                  } else {
                    final newStaff = SiteStaffModel(
                      id: '',
                      siteId: widget.site.id,
                      name: name,
                      role: selectedRole,
                      modules: selectedModules.toList(),
                      pin: pin,
                      phone: phone,
                      employeeCode: code,
                      designation: designation,
                      fatherName: father,
                      description: desc,
                      dateOfBirth: selectedDob,
                      aadharNumber: aadharNum,
                      aadharCardUrl: finalAadharUrl,
                      panNumber: panNum,
                      panCardUrl: finalPanUrl,
                      createdAt: DateTime.now(),
                    );
                    await ref
                        .read(siteStaffProvider(widget.site.id).notifier)
                        .addStaff(newStaff);
                  }
                  ref.invalidate(allStaffProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEditing
                          ? (isOffice ? 'Office employee updated!' : 'Staff member updated!')
                          : '${isOffice ? "Office employee" : "Staff member"} "$name" saved with ${selectedModules.length} module(s)!'),
                      backgroundColor: AppColors.approved,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.rejected,
                    ),
                  );
                }
              },
              child: Text(isEditing
                  ? 'Save Changes'
                  : (isOffice ? 'Save Office Employee' : 'Save Staff Profile')),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteStaff(SiteStaffModel staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Delete Staff Member'),
        content: Text(
          'Are you sure you want to remove "${staff.name}" (${staff.role.displayName}) from ${widget.site.name}?',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(siteStaffProvider(widget.site.id).notifier)
                  .deleteStaff(staff.id);
              ref.invalidate(allStaffProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Staff member removed.'),
                  backgroundColor: AppColors.approved,
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffState = ref.watch(siteStaffProvider(widget.site.id));

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.site.isHeadOffice ? 'Manage Head Office Staff' : 'Manage Site Staff'),
            Text(
              widget.site.isHeadOffice ? '${widget.site.name} (Indore HQ)' : widget.site.name,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(siteStaffProvider(widget.site.id).notifier).loadStaff();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          isScrollable: true,
          tabs: widget.site.isHeadOffice
              ? [
                  _buildTab('All Office Staff', Icons.people_outline, staffState.staffList, null),
                  _buildTab('Attendance', Icons.how_to_reg_outlined, staffState.staffList, StaffModule.attendance),
                  _buildTab('Daily Report', Icons.assignment_outlined, staffState.staffList, StaffModule.report),
                ]
              : [
                  _buildTab('All Staff', Icons.people_outline, staffState.staffList, null),
                  _buildTab('Attendance', Icons.how_to_reg_outlined, staffState.staffList, StaffModule.attendance),
                  _buildTab('Cashbook', Icons.account_balance_wallet_outlined, staffState.staffList, StaffModule.cashbook),
                  _buildTab('Daily Report', Icons.assignment_outlined, staffState.staffList, StaffModule.report),
                  _buildTab('Stock', Icons.inventory_2_outlined, staffState.staffList, StaffModule.stock),
                ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showAddStaffDialog(null, _filterModuleForTab),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text(
          _filterModuleForTab != null
              ? 'Add ${_filterModuleForTab!.displayName} Staff'
              : (widget.site.isHeadOffice ? 'Add Office Staff Member' : 'Add Staff Member'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: staffState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: widget.site.isHeadOffice
                  ? [
                      _buildFilteredStaffList(staffState.staffList, null),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.attendance),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.report),
                    ]
                  : [
                      _buildFilteredStaffList(staffState.staffList, null),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.attendance),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.cashbook),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.report),
                      _buildFilteredStaffList(staffState.staffList, StaffModule.stock),
                    ],
            ),
    );
  }

  Widget _buildTab(String title, IconData icon, List<SiteStaffModel> allStaff, StaffModule? module) {
    final count = module == null
        ? allStaff.length
        : allStaff.where((s) => s.hasModule(module)).length;

    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(title),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilteredStaffList(List<SiteStaffModel> allStaff, StaffModule? module) {
    final filteredStaff = module == null
        ? allStaff
        : allStaff.where((s) => s.hasModule(module)).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(siteStaffProvider(widget.site.id).notifier).loadStaff(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Workflow Banner
          _buildWorkflowBanner(module),
          const SizedBox(height: 14),

          if (filteredStaff.isEmpty)
            _buildEmptyState(module)
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  module != null
                      ? '${module.displayName} Team (${filteredStaff.length})'
                      : (widget.site.isHeadOffice
                          ? 'All Office Team (${filteredStaff.length})'
                          : 'All Site Team (${filteredStaff.length})'),
                  style: AppTextStyles.h4.copyWith(fontSize: 15),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.waveCyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.waveCyan.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${filteredStaff.length} Member(s)',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.waveCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...filteredStaff.map((staff) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildStaffCard(staff),
                )),
          ],
          const SizedBox(height: 80), // Fab space
        ],
      ),
    );
  }

  Widget _buildWorkflowBanner(StaffModule? module) {
    final isOffice = widget.site.isHeadOffice;

    final String flowTitle = isOffice
        ? 'Head Office Operations & Attendance'
        : 'Multi-Tier Approval Workflow';

    final String flowDescription;
    if (isOffice) {
      if (module == StaffModule.attendance) {
        flowDescription = 'Office Employee Check-In ➔ GPS Geofenced Verification ➔ Admin Attendance Record';
      } else if (module == StaffModule.report) {
        flowDescription = 'Office Daily Work Report (DSR) ➔ Submitted by Employee ➔ Reviewed by Admin';
      } else {
        flowDescription = 'Office Employee Profile ➔ Attendance Check-In & Daily Work Reports (DSR)';
      }
    } else {
      if (module == StaffModule.attendance) {
        flowDescription = 'Staff Punches ➔ Project Head Review ➔ Admin Approval (No Accounts verification)';
      } else {
        flowDescription = 'Site Worker Entry ➔ Project Head Approval ➔ Accounts Review ➔ Admin Approval';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.waveCyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.waveCyan.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isOffice ? Icons.corporate_fare_rounded : Icons.account_tree_rounded,
            size: 20,
            color: AppColors.waveCyan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flowTitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.waveCyan,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  flowDescription,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(SiteStaffModel staff) {
    final isSupervisor = staff.isSupervisor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSupervisor ? AppColors.primary.withOpacity(0.35) : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isSupervisor
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.secondary.withOpacity(0.15),
                child: Icon(
                  isSupervisor ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                  color: isSupervisor ? AppColors.primary : AppColors.secondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            staff.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSupervisor
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.secondary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            staff.role.displayName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSupervisor ? AppColors.primary : AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (staff.identificationSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        staff.identificationSubtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          'Pass: ${staff.pin}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action Buttons
              IconButton(
                icon: const Icon(Icons.analytics_outlined, size: 20, color: AppColors.secondary),
                tooltip: 'Performance 360° Report',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeePerformanceScreen(staff: staff, site: widget.site),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                tooltip: 'Edit',
                onPressed: () => _showAddStaffDialog(staff),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.rejected),
                tooltip: 'Delete',
                onPressed: () => _confirmDeleteStaff(staff),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Authorized Modules Tags
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: staff.modules.map((m) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  m.displayName,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
          // KYC Information Section (Date of Birth, Aadhar Card, PAN Card)
          if (staff.dateOfBirth != null ||
              (staff.aadharNumber != null && staff.aadharNumber!.isNotEmpty) ||
              staff.hasAadharCard ||
              (staff.panNumber != null && staff.panNumber!.isNotEmpty) ||
              staff.hasPanCard) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (staff.dateOfBirth != null) () {
                    final now = DateTime.now();
                    final isBirthdayToday = staff.dateOfBirth!.month == now.month && staff.dateOfBirth!.day == now.day;
                    return Container(
                      padding: isBirthdayToday ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : EdgeInsets.zero,
                      decoration: isBirthdayToday ? BoxDecoration(
                        color: AppColors.goldAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.6)),
                      ) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isBirthdayToday ? Icons.cake_rounded : Icons.cake_outlined, size: 14, color: AppColors.goldAccent),
                          const SizedBox(width: 4),
                          Text(
                            isBirthdayToday
                                ? '🎂 Birthday Today! (${DateFormat('dd MMM').format(staff.dateOfBirth!)}, ${staff.age ?? 0} yrs)'
                                : 'DOB: ${DateFormat('dd MMM yyyy').format(staff.dateOfBirth!)}${staff.age != null ? ' (${staff.age} yrs)' : ''}',
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 11,
                              color: isBirthdayToday ? AppColors.goldAccent : AppColors.textPrimary,
                              fontWeight: isBirthdayToday ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                  if ((staff.aadharNumber != null && staff.aadharNumber!.isNotEmpty) || staff.hasAadharCard)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.badge_outlined, size: 14, color: AppColors.waveCyan),
                        const SizedBox(width: 4),
                        Text(
                          'Aadhar: ${(staff.maskedAadhar != null && staff.maskedAadhar!.isNotEmpty) ? staff.maskedAadhar! : 'Attached'}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (staff.hasAadharCard) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              PhotoViewerDialog.show(
                                context,
                                [staff.aadharCardUrl!],
                                initialIndex: 0,
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.waveCyan.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.waveCyan.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.remove_red_eye_rounded, size: 11, color: AppColors.waveCyan),
                                  SizedBox(width: 3),
                                  Text(
                                    'View Doc',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.waveCyan,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if ((staff.panNumber != null && staff.panNumber!.isNotEmpty) || staff.hasPanCard)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.credit_card_rounded, size: 14, color: AppColors.goldAccent),
                        const SizedBox(width: 4),
                        Text(
                          'PAN: ${staff.panNumber ?? 'Attached'}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (staff.hasPanCard) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              PhotoViewerDialog.show(
                                context,
                                [staff.panCardUrl!],
                                initialIndex: 0,
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.goldAccent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.remove_red_eye_rounded, size: 11, color: AppColors.goldAccent),
                                  SizedBox(width: 3),
                                  Text(
                                    'View PAN',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.goldAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(StaffModule? module) {
    final isOffice = widget.site.isHeadOffice;
    final title = module != null
        ? module.displayName
        : (isOffice ? 'Office Staff' : 'Staff Members');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffice ? Icons.corporate_fare_rounded : Icons.person_outline,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text('No $title Configured', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              isOffice
                  ? 'Add office employees and managers for $title at ${widget.site.name}. Authorize them for Attendance and Daily Work Reports.'
                  : 'Add site workers and supervisors for $title at ${widget.site.name}. You can tick all features they are authorized to access.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showAddStaffDialog(null, module),
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: Text(
                isOffice ? 'Add First Office Employee' : 'Add First Staff Member',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
