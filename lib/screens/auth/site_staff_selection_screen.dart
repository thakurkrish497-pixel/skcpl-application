import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/site_model.dart';
import '../../models/site_staff_model.dart';
import '../../providers/site_staff_provider.dart';
import '../../providers/cash_provider.dart';
import '../../providers/stock_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../project_head/project_head_dashboard.dart';
import '../attendance/punch_attendance_screen.dart';

/// Screen displayed after site password to choose which staff member (Worker/Supervisor)
/// is recording transactions on this device. Supports "Remember Me".
class SiteStaffSelectionScreen extends ConsumerStatefulWidget {
  final SiteModel site;
  final String module; // 'stock', 'cashbook', or 'report'

  const SiteStaffSelectionScreen({
    super.key,
    required this.site,
    required this.module,
  });

  @override
  ConsumerState<SiteStaffSelectionScreen> createState() =>
      _SiteStaffSelectionScreenState();
}

class _SiteStaffSelectionScreenState
    extends ConsumerState<SiteStaffSelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh and invalidate cache so staff list and permissions are always 100% fresh
    Future.microtask(() {
      ref.invalidate(siteStaffProvider(widget.site.id));
      ref.read(siteStaffProvider(widget.site.id).notifier).loadStaff();
    });
  }

  void _proceedToModule(SiteStaffModel? staff) {
    // Preload transactions
    ref.read(cashProvider.notifier).loadTransactions(widget.site.id);
    if (widget.module == 'stock') {
      ref.read(stockProvider.notifier).loadTransactions(widget.site.id);
      Navigator.pushReplacementNamed(context, '/stock-choice');
    } else if (widget.module == 'report') {
      Navigator.pushReplacementNamed(context, '/site-report');
    } else if (widget.module == 'attendance') {
      if (staff != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PunchAttendanceScreen(
              site: widget.site,
              staff: staff,
            ),
          ),
        );
      }
    } else {
      Navigator.pushReplacementNamed(context, '/expense-form');
    }
  }

  void _showPinDialog(SiteStaffModel staff) {
    final pinController = TextEditingController();
    bool rememberMe = true;
    String? errorMessage;
    bool obscurePin = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: staff.isSupervisor
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.secondary.withOpacity(0.2),
                        child: Icon(
                          staff.isSupervisor
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          color: staff.isSupervisor
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(staff.name, style: AppTextStyles.h4),
                            Text(
                              staff.role.displayName +
                                  (staff.description != null &&
                                          staff.description!.isNotEmpty
                                      ? ' • ${staff.description}'
                                      : ''),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enter Password / Phone No / PIN to continue:',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.text,
                    obscureText: obscurePin,
                    autofocus: true,
                    style: AppTextStyles.h4.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter Password or Phone No',
                      errorText: errorMessage,
                      filled: true,
                      fillColor: AppColors.cardDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePin
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscurePin = !obscurePin;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) {
                      _verifyAndLogin(
                        pinController.text.trim(),
                        staff,
                        rememberMe,
                        setModalState,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Remember me checkbox
                  InkWell(
                    onTap: () {
                      setModalState(() {
                        rememberMe = !rememberMe;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Checkbox(
                            value: rememberMe,
                            activeColor: AppColors.primary,
                            onChanged: (val) {
                              setModalState(() {
                                rememberMe = val ?? true;
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              'Remember me on this device (quick auto-login)',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: staff.isSupervisor
                            ? AppColors.primary
                            : AppColors.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        _verifyAndLogin(
                          pinController.text.trim(),
                          staff,
                          rememberMe,
                          setModalState,
                        );
                      },
                      child: Text(
                        widget.module == 'attendance' ? 'Confirm & Punch Attendance' : 'Confirm & Login',
                        style: AppTextStyles.button.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _verifyAndLogin(
    String enteredPin,
    SiteStaffModel staff,
    bool remember,
    StateSetter setModalState,
  ) async {
    if (enteredPin.isEmpty) {
      setModalState(() {
        // empty pin
      });
      return;
    }

    if (enteredPin != staff.pin) {
      setModalState(() {
        // wrong pin
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect Password / PIN. Please try again.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    // PIN verified! Check module authorization
    final targetModule = StaffModule.fromString(widget.module);
    final isAllowed = staff.hasModule(targetModule) || widget.site.isHeadOffice;
    if (!isAllowed) {
      setModalState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: ${staff.name} is not authorized for ${targetModule.displayName}.'),
          backgroundColor: AppColors.rejected,
        ),
      );
      return;
    }

    await ref.read(activeStaffProvider.notifier).setActiveStaff(
          staff,
          siteId: widget.site.id,
          module: targetModule,
          remember: remember,
        );

    if (mounted) {
      Navigator.pop(context); // Close bottom sheet
      
      // If attendance, proceed directly to punch screen
      if (widget.module == 'attendance') {
        _proceedToModule(staff);
      } else if (staff.isSupervisor) {
        // If Project Head, offer direct choices: Review vs Entry
        _showProjectHeadActionSheet(staff);
      } else {
        _proceedToModule(staff);
      }
    }
  }

  void _showProjectHeadActionSheet(SiteStaffModel projectHead) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded,
                      color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Text('Project Head: ${projectHead.name}',
                      style: AppTextStyles.h4),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'What would you like to do?',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ListTile(
                tileColor: AppColors.cardDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fact_check_rounded,
                      color: AppColors.primary),
                ),
                title: Text('Review & Approve Submissions',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary)),
                subtitle: Text('Review requests in Project Head Dashboard',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textTertiary),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProjectHeadDashboard(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                tileColor: AppColors.cardDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.post_add_rounded,
                      color: AppColors.secondary),
                ),
                title: Text('Make an Entry (Direct)',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary)),
                subtitle: Text('Add Stock, Cash Expense, or Daily Report',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textTertiary),
                onTap: () {
                  Navigator.pop(ctx);
                  _proceedToModule(projectHead);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffState = ref.watch(siteStaffProvider(widget.site.id));
    final isAttendance = widget.module == 'attendance';
    final targetModule = StaffModule.fromString(widget.module);
    final moduleStaffList = staffState.staffList.where((s) {
      if (widget.site.isHeadOffice) {
        return true; // All staff added to Indore Head Office are visible & selectable
      }
      return s.hasModule(targetModule);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(isAttendance
            ? '${widget.site.name} — ${context.tr('attendance_punch')}'
            : '${widget.site.name} — ${targetModule.displayName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: LanguageToggleButton(isCompact: true),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.15),
                      AppColors.cardDark,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded,
                            color: AppColors.primary, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          isAttendance
                              ? 'Who is Punching Attendance?'
                              : 'Who is entering ${targetModule.displayName}?',
                          style: AppTextStyles.h4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAttendance
                          ? 'Select your name and enter PIN to punch in/out with GPS live verification.'
                          : 'Select your name below. Every entry will be stamped with your name for full accountability.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.1, end: 0),

              const SizedBox(height: 20),

              Expanded(
                child: staffState.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : moduleStaffList.isEmpty
                        ? _buildEmptyStaffState()
                        : ListView.separated(
                            itemCount: moduleStaffList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final staff = moduleStaffList[index];
                              return _buildStaffTile(staff, index);
                            },
                          ),
              ),

              const SizedBox(height: 12),

              // Skip / Fallback button so workers are never blocked
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    // Continue anonymously / as general site worker
                    ref.read(activeStaffProvider.notifier).setActiveStaff(
                          null,
                          siteId: widget.site.id,
                          module: targetModule,
                          remember: false,
                        );
                    _proceedToModule(null);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppColors.textSecondary),
                  label: Text(
                    'Continue as General Site Staff',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStaffState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_add_disabled_rounded,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No Staff Added Yet',
              style: AppTextStyles.h4,
            ),
            const SizedBox(height: 8),
            Text(
              'Admin can configure site workers and supervisors in Admin Dashboard > Site Details > Manage Staff.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                _proceedToModule(null);
              },
              icon: const Icon(Icons.login_rounded, color: Colors.white),
              label: Text(
                'Continue as Site Worker',
                style: AppTextStyles.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffTile(SiteStaffModel staff, int index) {
    final isSupervisor = staff.isSupervisor;

    return InkWell(
      onTap: () => _showPinDialog(staff),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSupervisor
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.divider,
            width: isSupervisor ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isSupervisor
                  ? AppColors.primary.withOpacity(0.15)
                  : AppColors.secondary.withOpacity(0.15),
              child: Icon(
                isSupervisor
                    ? Icons.admin_panel_settings_rounded
                    : Icons.person_rounded,
                color: isSupervisor ? AppColors.primary : AppColors.secondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        staff.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                            fontWeight: FontWeight.w600,
                            color: isSupervisor
                                ? AppColors.primary
                                : AppColors.secondary,
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
                  ] else if (staff.description != null &&
                      staff.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      staff.description!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 60 * index));
  }
}
