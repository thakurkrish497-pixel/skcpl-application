import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/localization/app_strings.dart';
import '../../models/site_staff_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_staff_provider.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../auth/site_staff_selection_screen.dart';
import '../attendance/punch_attendance_screen.dart';
import '../../widgets/universal_sync_button.dart';
import '../../providers/stock_provider.dart';

/// Screen presenting choices: Add Product (Inbound) and Use Product (Outbound)
class StockChoiceScreen extends ConsumerStatefulWidget {
  const StockChoiceScreen({super.key});

  @override
  ConsumerState<StockChoiceScreen> createState() => _StockChoiceScreenState();
}

class _StockChoiceScreenState extends ConsumerState<StockChoiceScreen> {
  bool _isStockExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeSite = ref.read(authProvider).activeSite;
      if (activeSite != null) {
        ref.read(stockProvider.notifier).loadCurrentStock(activeSite.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeSite = ref.watch(authProvider).activeSite;
    final activeStaff = ref.watch(activeStaffProvider);
    final hasStockPermission =
        activeStaff == null || activeStaff.hasModule(StaffModule.stock);
    final stockState = ref.watch(stockProvider);
    final currentStock = stockState.currentStock;
    final isLight = AppColors.isLight;

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                activeSite != null
                    ? '${activeSite.name} — ${context.tr('stock_management')}'
                    : context.tr('stock_management'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          UniversalSyncButton(),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: LanguageToggleButton(isCompact: true),
          ),
        ],
      ),
      body: activeSite?.isHeadOffice == true
          ? _buildHeadOfficeGuard(context, activeSite!)
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Staff Banner
              if (ref.watch(activeStaffProvider) != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: ref.watch(activeStaffProvider)!.isSupervisor
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.secondary.withOpacity(0.2),
                        child: Icon(
                          ref.watch(activeStaffProvider)!.isSupervisor
                              ? Icons.admin_panel_settings_rounded
                              : Icons.person_rounded,
                          size: 16,
                          color: ref.watch(activeStaffProvider)!.isSupervisor
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Entering as: ${ref.watch(activeStaffProvider)!.name} (${ref.watch(activeStaffProvider)!.role.displayName})',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (activeSite != null) {
                            await ref.read(activeStaffProvider.notifier).clearActiveStaff(activeSite.id);
                            if (context.mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SiteStaffSelectionScreen(
                                    site: activeSite,
                                    module: 'stock',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Switch', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Attendance Quick Punch Card
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PunchAttendanceScreen(
                          site: activeSite,
                          staff: ref.read(activeStaffProvider)!,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14B8A6).withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.how_to_reg_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily Attendance Punch',
                                style: AppTextStyles.labelLarge
                                    .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Punch in/out with GPS live verification',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: Colors.white.withOpacity(0.85)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 20),
              ],

              // Access Denied Warning Banner if Stock toggle was turned off
              if (!hasStockPermission) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.rejected.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.rejected.withOpacity(0.5), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block_rounded, color: AppColors.rejected, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stock Permission Disabled',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.rejected,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stock module access has been turned off for ${activeStaff.name}. Inward and Outward stock operations are locked.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.rejected,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () async {
                          if (activeSite != null) {
                            await ref.read(activeStaffProvider.notifier).clearActiveStaff(activeSite.id, module: StaffModule.stock);
                            if (context.mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SiteStaffSelectionScreen(
                                    site: activeSite,
                                    module: 'stock',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Switch Staff', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ).animate().shake(),
              ],

              // ── SITE STOCK BALANCE IN HAND OVERVIEW (Visible before entering) ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isLight
                        ? [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)]
                        : [const Color(0xFF062319), const Color(0xFF0B3828)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLight ? const Color(0xFF86EFAC) : const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.inventory_2_rounded,
                                  color: Color(0xFF10B981), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Site Stock Balance in Hand',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  activeSite != null ? '${activeSite.name} Materials' : 'Available on Site',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isLight ? AppColors.textSecondaryLight : AppColors.textTertiaryDark,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '${currentStock.length} Item${currentStock.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (stockState.isLoading && currentStock.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                            ),
                            SizedBox(width: 10),
                            Text('Syncing live stock in hand...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      )
                    else if (currentStock.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: isLight ? AppColors.textSecondaryLight : Colors.white60),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No stock recorded yet on this site. Use "+ Add Product" to record your first inbound stock delivery.',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isLight ? AppColors.textSecondaryLight : Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // Material stock items list
                      ...((_isStockExpanded ? currentStock : currentStock.take(3)).map((item) {
                        final productName = item['product_name'] ?? 'Material';
                        final stock = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
                        final unit = item['metric_unit'] ?? '';
                        final inbound = (item['total_inbound'] as num?)?.toDouble() ?? 0.0;
                        final outbound = (item['total_outbound'] as num?)?.toDouble() ?? 0.0;
                        final isLow = stock <= 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isLight ? Colors.white.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isLow
                                  ? AppColors.rejected.withValues(alpha: 0.3)
                                  : (isLight ? const Color(0xFFBAE6FD) : Colors.white.withValues(alpha: 0.08)),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 4,
                                backgroundColor: isLow ? AppColors.rejected : const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      productName,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: isLight ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'In: $inbound $unit • Used: $outbound $unit',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isLight ? AppColors.textSecondaryLight : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$stock $unit',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: isLow
                                          ? AppColors.rejected
                                          : (isLight ? const Color(0xFF047857) : const Color(0xFF34D399)),
                                    ),
                                  ),
                                  Text(
                                    isLow ? 'Out of stock' : 'In hand',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isLow ? AppColors.rejected : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      })),

                      if (currentStock.length > 3)
                        InkWell(
                          onTap: () => setState(() => _isStockExpanded = !_isStockExpanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isStockExpanded
                                      ? 'Show Less'
                                      : 'Show All ${currentStock.length} Materials',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isLight ? const Color(0xFF0284c7) : AppColors.waveCyan,
                                  ),
                                ),
                                Icon(
                                  _isStockExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: isLight ? const Color(0xFF0284c7) : AppColors.waveCyan,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

              Text(
                'What would you like to do?',
                style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary),
              ).animate().fadeIn(),
              const SizedBox(height: 6),
              Text(
                'Select an operation to record inventory movements',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 24),

              // Add Product card
              Opacity(
                opacity: hasStockPermission ? 1.0 : 0.5,
                child: _ChoiceCard(
                  title: context.tr('stock_inward'),
                  subtitle: hasStockPermission ? context.tr('stock_inward_sub') : 'Locked: Stock access disabled for current staff',
                  icon: hasStockPermission ? Icons.add_circle_rounded : Icons.lock_outline_rounded,
                  gradient: hasStockPermission
                      ? const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)])
                      : const LinearGradient(colors: [Colors.grey, Color(0xFF4B5563)]),
                  onTap: () {
                    if (hasStockPermission) {
                      Navigator.pushNamed(context, '/add-product');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Access Denied: Stock module access is turned off for ${activeStaff.name}.',
                          ),
                          backgroundColor: AppColors.rejected,
                        ),
                      );
                    }
                  },
                ),
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05),

              const SizedBox(height: 16),

              // Use Product card
              Opacity(
                opacity: hasStockPermission ? 1.0 : 0.5,
                child: _ChoiceCard(
                  title: context.tr('stock_outward'),
                  subtitle: hasStockPermission ? context.tr('stock_outward_sub') : 'Locked: Stock access disabled for current staff',
                  icon: hasStockPermission ? Icons.remove_circle_rounded : Icons.lock_outline_rounded,
                  gradient: hasStockPermission
                      ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])
                      : const LinearGradient(colors: [Colors.grey, Color(0xFF4B5563)]),
                  onTap: () {
                    if (hasStockPermission) {
                      Navigator.pushNamed(context, '/use-product');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Access Denied: Stock module access is turned off for ${activeStaff.name}.',
                          ),
                          backgroundColor: AppColors.rejected,
                        ),
                      );
                    }
                  },
                ),
              ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.05),

              const SizedBox(height: 24),

              // View History Button
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/stock-history'),
                icon: const Icon(Icons.history_rounded),
                label: Text(context.tr('stock_history')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadOfficeGuard(BuildContext context, dynamic activeSite) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.waveCyan.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.waveCyan.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppColors.waveCyan,
                  size: 48,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                activeSite.name,
                style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.waveCyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'HEAD OFFICE / HQ',
                  style: TextStyle(
                    color: AppColors.waveCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Head Office (Indore Office) does not maintain site construction materials (Cement, Steel, Aggregates, Sand, etc.). Stock management is strictly designated for active construction project sites.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.divider),
              const SizedBox(height: 16),
              Text(
                'Available Head Office Modules:',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.how_to_reg_rounded, size: 20),
                  label: const Text('Mark Office Attendance'),
                  onPressed: () {
                    final staff = ref.read(activeStaffProvider);
                    if (staff != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PunchAttendanceScreen(
                            site: activeSite,
                            staff: staff,
                          ),
                        ),
                      );
                    } else {
                      Navigator.pushReplacementNamed(context, '/site-staff-selection');
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.description_rounded, size: 20),
                  label: const Text('Daily Work Report (DSR)'),
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/site-report');
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Switch to a Construction Site'),
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/sites');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.first.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.h4.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.7), size: 16),
          ],
        ),
      ),
    );
  }
}
