import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/site_staff_provider.dart';
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

  // Tab indices: 0 = All Staff, 1 = Attendance, 2 = Cashbook, 3 = Daily Report, 4 = Stock
  static const List<String> _tabNames = [
    'All Staff',
    'Attendance',
    'Cashbook',
    'Daily Report',
    'Stock',
  ];

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

  void _showAddStaffDialog([SiteStaffModel? existing, StaffModule? defaultModule]) {
    final isEditing = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final pinController = TextEditingController(text: existing?.pin ?? '1234');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final empCodeController = TextEditingController(text: existing?.employeeCode ?? '');
    final designationController = TextEditingController(text: existing?.designation ?? '');
    final fatherNameController = TextEditingController(text: existing?.fatherName ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');

    SiteStaffRole selectedRole = existing?.role ?? SiteStaffRole.worker;

    // Multi-module selection: default to active tab's module or all common modules
    Set<StaffModule> selectedModules = existing != null
        ? existing.modules.toSet()
        : (defaultModule != null
            ? {defaultModule}
            : {StaffModule.attendance, StaffModule.cashbook, StaffModule.report});

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
                isEditing ? 'Edit Staff Member' : 'Add Staff Member',
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
                          'If an option is unticked, this employee will NOT see their name in that feature.',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                        ),
                        const Divider(height: 16),
                        ...StaffModule.values.map((mod) {
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
                      hintText: 'e.g. Joined Oct 2026, permanent staff',
                      prefixIcon: Icon(Icons.info_outline),
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

                try {
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
                          ? 'Staff member updated!'
                          : 'Staff member "$name" saved with ${selectedModules.length} module(s)!'),
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
              child: Text(isEditing ? 'Save Changes' : 'Save Staff Profile'),
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
            const Text('Manage Site Staff'),
            Text(
              widget.site.name,
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
          tabs: [
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
              : 'Add Staff Member',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: staffState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
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
                      : 'All Site Team (${filteredStaff.length})',
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
    final String flowDescription;
    if (module == StaffModule.attendance) {
      flowDescription = 'Staff Punches ➔ Project Head Review ➔ Admin Approval (No Accounts verification)';
    } else {
      flowDescription = 'Site Worker Entry ➔ Project Head Approval ➔ Accounts Review ➔ Admin Approval';
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
          const Icon(
            Icons.account_tree_rounded,
            size: 20,
            color: AppColors.waveCyan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Multi-Tier Approval Workflow',
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
        ],
      ),
    );
  }

  Widget _buildEmptyState(StaffModule? module) {
    final title = module != null ? module.displayName : 'Staff Members';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text('No $title Configured', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'Add site workers and supervisors for $title at ${widget.site.name}. You can tick all features they are authorized to access.',
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
              label: Text('Add First Staff Member', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
