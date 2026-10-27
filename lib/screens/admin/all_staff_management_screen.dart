import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/site_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/photo_viewer_dialog.dart';
import 'employee_performance_screen.dart';

/// Unified Admin Command Center for Managing Employees across all construction sites
/// and the Indore Head Office.
class AllStaffManagementScreen extends ConsumerStatefulWidget {
  final String? initialSiteId;

  const AllStaffManagementScreen({super.key, this.initialSiteId});

  @override
  ConsumerState<AllStaffManagementScreen> createState() =>
      _AllStaffManagementScreenState();
}

class _AllStaffManagementScreenState
    extends ConsumerState<AllStaffManagementScreen>
    with SingleTickerProviderStateMixin {
  String _selectedLocationFilter = 'all'; // 'all' or site UUID
  late TabController _tabController;

  static const List<String> _tabNames = [
    'All Roles',
    'Attendance',
    'Cashbook',
    'Daily Report',
    'Stock',
  ];

  Map<String, List<SiteStaffModel>> _staffBySite = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialSiteId != null) {
      _selectedLocationFilter = widget.initialSiteId!;
    }
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllStaff() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sites = await ref.read(allSitesProvider.future);
      final service = ref.read(siteStaffServiceProvider);

      final Map<String, List<SiteStaffModel>> map = {};
      for (final site in sites) {
        final staffList = await service.getStaffForSite(site.id);
        map[site.id] = staffList;
      }

      if (mounted) {
        setState(() {
          _staffBySite = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  StaffModule? get _activeModuleFilter {
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
        return null; // All Roles
    }
  }

  void _showAddEditStaffDialog({
    SiteStaffModel? existing,
    String? defaultSiteId,
    required List<SiteModel> allSites,
  }) {
    final isEditing = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final pinController = TextEditingController(text: existing?.pin ?? '1234');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final empCodeController = TextEditingController(text: existing?.employeeCode ?? '');
    final designationController = TextEditingController(text: existing?.designation ?? '');
    final fatherNameController = TextEditingController(text: existing?.fatherName ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final aadharController = TextEditingController(text: existing?.aadharNumber ?? '');
    final panController = TextEditingController(text: existing?.panNumber ?? '');

    DateTime? selectedDob = existing?.dateOfBirth;

    Uint8List? aadharBytes;
    String? aadharFileName;
    String? currentAadharUrl = existing?.aadharCardUrl;

    Uint8List? panBytes;
    String? panFileName;
    String? currentPanUrl = existing?.panCardUrl;

    Future<void> pickDocPhoto({
      required BuildContext docCtx,
      required Function(Uint8List bytes, String name) onPicked,
    }) async {
      final source = await showModalBottomSheet<ImageSource>(
        context: docCtx,
        backgroundColor: AppColors.surfaceDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

    String selectedSiteId = existing?.siteId ??
        defaultSiteId ??
        (_selectedLocationFilter != 'all'
            ? _selectedLocationFilter
            : (allSites.isNotEmpty ? allSites.first.id : ''));

    SiteStaffRole selectedRole = existing?.role ?? SiteStaffRole.worker;

    // Multi-module selection: default to active tab's module or common modules
    Set<StaffModule> selectedModules = existing != null
        ? existing.modules.toSet()
        : (_activeModuleFilter != null
            ? {_activeModuleFilter!}
            : {StaffModule.attendance, StaffModule.cashbook, StaffModule.report});

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final chosenSite = allSites.firstWhere(
            (s) => s.id == selectedSiteId,
            orElse: () => allSites.first,
          );
          final isOffice = chosenSite.isHeadOffice;

          return AlertDialog(
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
                  isEditing ? 'Edit Staff Profile' : 'Add New Staff / Employee',
                  style: AppTextStyles.h4,
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location / Site Dropdown
                    if (!isEditing) ...[
                      DropdownButtonFormField<String>(
                        value: selectedSiteId,
                        dropdownColor: AppColors.cardDark,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Site / Head Office *',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        items: allSites.map((s) {
                          return DropdownMenuItem(
                            value: s.id,
                            child: Row(
                              children: [
                                Icon(
                                  s.isHeadOffice ? Icons.apartment_rounded : Icons.construction_rounded,
                                  size: 16,
                                  color: s.isHeadOffice ? AppColors.primary : AppColors.secondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.isHeadOffice ? '${s.name} (Office Attendance)' : s.name,
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedSiteId = val;
                              final newSite = allSites.firstWhere((s) => s.id == val);
                              if (newSite.isHeadOffice) {
                                selectedModules = {StaffModule.attendance, StaffModule.report};
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Full Name
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Ram Sharma',
                        prefixIcon: Icon(Icons.person_outline),
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
                                ? 'Indore Head Office supports Attendance and Daily Work Reports.'
                                : 'Unticked modules will hide this person from that feature\'s login list.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                          ),
                          const Divider(height: 16),
                          ...StaffModule.values.map((mod) {
                            // If Head Office, allow attendance and daily report
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

                    // Duplicate Identification Helper
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
                              labelText: 'Employee ID',
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
                            decoration: const InputDecoration(
                              labelText: 'Designation / Trade',
                              hintText: 'e.g. Senior Mason',
                              prefixIcon: Icon(Icons.work_outline),
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
                        hintText: 'e.g. Permanent staff, Kukshi resident',
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

                    // Aadhar Card Field & Attachment
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
                                'Aadhar Card Details',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              if (aadharBytes != null || (currentAadharUrl != null && currentAadharUrl!.isNotEmpty))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.approved.withValues(alpha: 0.2),
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
                            controller: aadharController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Aadhar Number (12 Digits)',
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
                                  onPressed: () => pickDocPhoto(
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
                                        ? 'Change Aadhar Photo / Scan'
                                        : 'Attach Aadhar Card Photo / Scan',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                              if (aadharBytes != null || (currentAadharUrl != null && currentAadharUrl!.isNotEmpty))
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.rejected, size: 18),
                                  tooltip: 'Remove Card',
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
                                'PAN Card Details',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              if (panBytes != null || (currentPanUrl != null && currentPanUrl!.isNotEmpty))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.approved.withValues(alpha: 0.2),
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
                                  onPressed: () => pickDocPhoto(
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
                                        : 'Attach PAN Card Photo / Scan',
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
                        content: Text('Please select at least one module'),
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

                    final service = ref.read(siteStaffServiceProvider);
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
                      await service.updateStaff(updated);
                    } else {
                      final newStaff = SiteStaffModel(
                        id: '',
                        siteId: selectedSiteId,
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
                      await service.createStaff(newStaff);
                    }

                    // Invalidate caches so other screens immediately see the changes
                    ref.invalidate(siteStaffProvider(selectedSiteId));
                    ref.invalidate(allStaffProvider);

                    // Reload
                    await _loadAllStaff();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEditing
                              ? 'Staff profile updated!'
                              : 'Employee "$name" created successfully!'),
                          backgroundColor: AppColors.approved,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
                      );
                    }
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Create Staff Member'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteStaff(SiteStaffModel staff, String siteName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Delete Staff Member'),
        content: Text(
          'Are you sure you want to remove "${staff.name}" (${staff.role.displayName}) from $siteName?',
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
              await ref.read(siteStaffServiceProvider).deleteStaff(staff.id, staff.siteId);
              ref.invalidate(siteStaffProvider(staff.siteId));
              ref.invalidate(allStaffProvider);
              await _loadAllStaff();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Staff member removed.'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(allSitesProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: const Text('Manage Employees & Staff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Staff',
            onPressed: _loadAllStaff,
          ),
        ],
      ),
      body: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, _) => Center(
          child: Text('Error loading sites: $err', style: const TextStyle(color: AppColors.rejected)),
        ),
        data: (sites) {
          // Flatten all staff according to current filters
          final filteredStaffWithSite = <({SiteStaffModel staff, SiteModel site})>[];

          for (final site in sites) {
            if (_selectedLocationFilter != 'all' && site.id != _selectedLocationFilter) {
              continue;
            }
            final staffList = _staffBySite[site.id] ?? [];
            for (final staff in staffList) {
              if (_activeModuleFilter == null || staff.hasModule(_activeModuleFilter!)) {
                filteredStaffWithSite.add((staff: staff, site: site));
              }
            }
          }

          return Column(
            children: [
              // ── Location Filter Bar ──
              Container(
                color: AppColors.surfaceDark,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'FILTER BY LOCATION:',
                          style: AppTextStyles.overline.copyWith(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All Locations'),
                            selected: _selectedLocationFilter == 'all',
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.cardDark,
                            labelStyle: TextStyle(
                              color: _selectedLocationFilter == 'all' ? Colors.white : AppColors.textSecondary,
                              fontWeight: _selectedLocationFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _selectedLocationFilter = 'all');
                            },
                          ),
                          ...sites.map((site) {
                            final isSel = _selectedLocationFilter == site.id;
                            final isOffice = site.isHeadOffice;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                avatar: Icon(
                                  isOffice ? Icons.apartment_rounded : Icons.construction_rounded,
                                  size: 14,
                                  color: isSel
                                      ? Colors.white
                                      : (isOffice ? AppColors.primary : AppColors.secondary),
                                ),
                                label: Text(isOffice ? 'Indore Head Office' : site.name),
                                selected: isSel,
                                selectedColor: isOffice ? AppColors.primary : AppColors.secondary,
                                backgroundColor: AppColors.cardDark,
                                labelStyle: TextStyle(
                                  color: isSel ? Colors.white : AppColors.textSecondary,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                                onSelected: (val) {
                                  if (val) setState(() => _selectedLocationFilter = site.id);
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Module Tabs ──
              Container(
                color: AppColors.cardDark,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  isScrollable: true,
                  tabs: _tabNames.map((name) => Tab(text: name)).toList(),
                ),
              ),

              // ── Staff Count Bar & Add Button ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filteredStaffWithSite.length} Staff Member(s) Found',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                      label: const Text('Add Employee', style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        _showAddEditStaffDialog(
                          allSites: sites,
                          defaultSiteId: _selectedLocationFilter != 'all' ? _selectedLocationFilter : null,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── Staff List ──
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _errorMessage != null
                        ? Center(
                            child: Text(
                              'Error: $_errorMessage',
                              style: const TextStyle(color: AppColors.rejected),
                            ),
                          )
                        : filteredStaffWithSite.isEmpty
                            ? _buildEmptyState(sites)
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: filteredStaffWithSite.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = filteredStaffWithSite[index];
                                  return _buildStaffItemCard(
                                    staff: item.staff,
                                    site: item.site,
                                    allSites: sites,
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStaffItemCard({
    required SiteStaffModel staff,
    required SiteModel site,
    required List<SiteModel> allSites,
  }) {
    final isSupervisor = staff.isSupervisor;
    final isOffice = site.isHeadOffice;

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
                              fontSize: 15,
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          isOffice ? Icons.apartment_rounded : Icons.construction_rounded,
                          size: 13,
                          color: isOffice ? AppColors.primary : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOffice ? 'Indore Head Office' : site.name,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isOffice ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
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
                            fontSize: 11,
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
                      builder: (_) => EmployeePerformanceScreen(staff: staff, site: site),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                tooltip: 'Edit Profile',
                onPressed: () {
                  _showAddEditStaffDialog(existing: staff, allSites: allSites);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.rejected),
                tooltip: 'Delete Profile',
                onPressed: () => _confirmDeleteStaff(staff, site.name),
              ),
            ],
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
                color: AppColors.surfaceDark.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider.withOpacity(0.5)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (staff.dateOfBirth != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cake_outlined, size: 14, color: AppColors.goldAccent),
                        const SizedBox(width: 4),
                        Text(
                          'DOB: ${DateFormat('dd MMM yyyy').format(staff.dateOfBirth!)}${staff.age != null ? ' (${staff.age} yrs)' : ''}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  if ((staff.aadharNumber != null && staff.aadharNumber!.isNotEmpty) || staff.hasAadharCard)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.badge_outlined, size: 14, color: AppColors.primary),
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
                                color: AppColors.primary.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.remove_red_eye_rounded, size: 11, color: AppColors.primary),
                                  SizedBox(width: 3),
                                  Text(
                                    'View Card',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
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
                        const Icon(Icons.credit_card_rounded, size: 14, color: AppColors.secondary),
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
                                color: AppColors.secondary.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.remove_red_eye_rounded, size: 11, color: AppColors.secondary),
                                  SizedBox(width: 3),
                                  Text(
                                    'View Card',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.secondary,
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
          const SizedBox(height: 10),
          // Modules badges
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
        ],
      ),
    );
  }

  Widget _buildEmptyState(List<SiteModel> sites) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text('No Employees Found', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'No staff members match the selected location or role filter.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: const Text('Add First Employee', style: TextStyle(color: Colors.white)),
              onPressed: () {
                _showAddEditStaffDialog(allSites: sites);
              },
            ),
          ],
        ),
      ),
    );
  }
}
