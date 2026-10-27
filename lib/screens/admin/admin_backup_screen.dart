import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/backup_service.dart';
import '../../services/audit_service.dart';
import '../../widgets/skcpl_brand_logo.dart';
import '../../widgets/skcpl_wave_widgets.dart';
import '../../widgets/responsive_layout.dart';

/// Screen for Layer 1 to 4 Data Loss Prevention, Disaster Recovery & Master Backups
class AdminBackupScreen extends ConsumerStatefulWidget {
  const AdminBackupScreen({super.key});

  @override
  ConsumerState<AdminBackupScreen> createState() => _AdminBackupScreenState();
}

class _AdminBackupScreenState extends ConsumerState<AdminBackupScreen> {
  bool _isLoadingStats = true;
  bool _isExportingExcel = false;
  bool _isExportingJson = false;
  bool _isExportingManifest = false;

  Map<String, dynamic>? _counts;
  List<Map<String, dynamic>> _vaultRecords = [];

  @override
  void initState() {
    super.initState();
    _loadLiveStats();
    _loadVault();
  }

  Future<void> _loadLiveStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final fullData = await BackupService.fetchFullOrganizationData();
      final metadata = fullData['metadata'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _counts = metadata['counts'] as Map<String, dynamic>? ?? {};
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _loadVault() async {
    final records = await AuditService.getArchivedVaultRecords();
    if (mounted) {
      setState(() => _vaultRecords = records);
    }
  }

  Future<void> _handleExportExcel() async {
    setState(() => _isExportingExcel = true);
    try {
      await BackupService.exportMasterExcelBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Master Excel Backup (.xlsx) generated & downloaded!'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  Future<void> _handleExportJson() async {
    setState(() => _isExportingJson = true);
    try {
      await BackupService.exportFullJsonBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Full Database Snapshot (.json) generated & downloaded!'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingJson = false);
    }
  }

  Future<void> _handleExportManifest() async {
    setState(() => _isExportingManifest = true);
    try {
      await BackupService.exportMediaManifest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Media & Receipts Manifest downloaded!'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingManifest = false);
    }
  }

  void _showCloudBackupModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.cloud_sync_rounded, color: AppColors.waveCyan, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Automated Cloud Backups & PITR',
                style: AppTextStyles.h4.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoBullet(
                  '1. Supabase Point-in-Time Recovery (PITR)',
                  'Your Supabase PostgreSQL cluster automatically retains WAL logs. Even if someone accidentally drops or updates data, the database can be rolled back to the exact second prior to the incident.',
                ),
                const SizedBox(height: 14),
                _buildInfoBullet(
                  '2. Nightly Automated GitHub Action',
                  'A pre-configured automated workflow runs at 00:00 AM IST midnight every night, queries all 10 tables, packages a compressed JSON archive, and stores it in GitHub artifacts with 90-day retention.',
                ),
                const SizedBox(height: 14),
                _buildInfoBullet(
                  '3. Media & Receipt Bucket Redundancy',
                  'All voucher photos, receipts, and DSR images are stored with immutable UUIDs in Supabase Cloud Storage. The Media Manifest download provides an index of all URLs.',
                ),
                const SizedBox(height: 14),
                _buildInfoBullet(
                  '4. Local Emergency Vault (Layer 4)',
                  'Whenever an admin or project head deletes an item, a copy of the entire record is saved into the Emergency Vault on this browser before deletion.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Understood',
              style: TextStyle(color: AppColors.waveCyan, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBullet(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.waveCyan,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appBackgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const SkcplBrandLogo(variant: LogoVariant.compact, customSize: 32),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Data Loss Protection',
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• Backups',
                      style: AppTextStyles.h4.copyWith(
                        color: AppColors.waveCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Connect to Waves • 4-Layer Disaster Recovery',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.waveCyan),
            tooltip: 'Refresh live counts',
            onPressed: () {
              _loadLiveStats();
              _loadVault();
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: AppColors.goldAccent),
            tooltip: 'Cloud Backup Architecture',
            onPressed: _showCloudBackupModal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 1200,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 4-Layer Protection Status Banner ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.waveCyan.withValues(alpha: 0.15),
                      AppColors.cardDark,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.waveCyan.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.waveCyan.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: AppColors.waveCyan,
                        size: 30,
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
                                '4-LAYER ZERO-DATA-LOSS ACTIVE',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.waveCyan,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.approved,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Automated Cloud Backups • In-App Master Snapshots • Media Manifest • Emergency Vault',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.waveCyan.withValues(alpha: 0.2),
                        foregroundColor: AppColors.waveCyan,
                        elevation: 0,
                        side: const BorderSide(color: AppColors.waveCyan, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _showCloudBackupModal,
                      icon: const Icon(Icons.info_outline_rounded, size: 16),
                      label: const Text('Architecture'),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05),

              const SizedBox(height: 22),

              // ── Live Company Data Inventory ──
              Text(
                'LIVE COMPANY DATA INVENTORY',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              _isLoadingStats
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: AppColors.waveCyan),
                      ),
                    )
                  : ResponsiveGrid(
                      mobileColumns: 2,
                      tabletColumns: 4,
                      desktopColumns: 4,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildStatCard(
                          icon: Icons.location_city_rounded,
                          title: 'Sites & Locations',
                          value: '${_counts?['sites'] ?? 0}',
                          color: AppColors.primaryLight,
                        ),
                        _buildStatCard(
                          icon: Icons.account_balance_wallet_rounded,
                          title: 'Cash Transactions',
                          value: '${_counts?['cash_transactions'] ?? 0}',
                          color: AppColors.approved,
                        ),
                        _buildStatCard(
                          icon: Icons.inventory_2_rounded,
                          title: 'Stock Entries',
                          value: '${_counts?['stock_transactions'] ?? 0}',
                          color: AppColors.goldAccent,
                        ),
                        _buildStatCard(
                          icon: Icons.assignment_turned_in_rounded,
                          title: 'Attendance & DSRs',
                          value:
                              '${(_counts?['attendance'] ?? 0) + (_counts?['daily_site_reports'] ?? 0)}',
                          color: const Color(0xFFF97316),
                        ),
                      ],
                    ),

              const SizedBox(height: 26),

              // ── Instant 1-Click Master Backup Actions ──
              Text(
                'INSTANT 1-CLICK MASTER BACKUPS & EXPORTS',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              ResponsiveGrid(
                mobileColumns: 1,
                tabletColumns: 3,
                desktopColumns: 3,
                spacing: 14,
                runSpacing: 14,
                children: [
                  // Excel Backup Card
                  _buildActionCard(
                    icon: Icons.table_view_rounded,
                    title: 'Master Excel (.xlsx)',
                    subtitle:
                        '6-sheet executive workbook: Sites, Imprest Cashbook, Stock Register, Attendance Logs, DSRs & Staff Directory.',
                    color: const Color(0xFF10B981),
                    buttonText: 'Download Master Excel',
                    isLoading: _isExportingExcel,
                    onTap: _handleExportExcel,
                  ),

                  // JSON Database Snapshot Card
                  _buildActionCard(
                    icon: Icons.data_object_rounded,
                    title: 'Database Snapshot (.json)',
                    subtitle:
                        '100% full-fidelity raw JSON export of all 10 tables. Ready for instant disaster recovery or server migration.',
                    color: AppColors.waveCyan,
                    buttonText: 'Download Full JSON',
                    isLoading: _isExportingJson,
                    onTap: _handleExportJson,
                  ),

                  // Media Manifest Card
                  _buildActionCard(
                    icon: Icons.photo_library_rounded,
                    title: 'Media Manifest (.json)',
                    subtitle:
                        'Complete catalog and verified URL index of all voucher receipts, delivery challans, DSR photos, and attendance selfies.',
                    color: const Color(0xFF8B5CF6),
                    buttonText: 'Download Media Catalog',
                    isLoading: _isExportingManifest,
                    onTap: _handleExportManifest,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Layer 4: Emergency Vault & Soft-Deleted Items ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'EMERGENCY VAULT & RECENT DELETIONS (${_vaultRecords.length})',
                    style: AppTextStyles.overline.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (_vaultRecords.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.rejected),
                      onPressed: () async {
                        await AuditService.clearVault();
                        _loadVault();
                      },
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Clear Vault', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: _vaultRecords.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: AppColors.approved.withValues(alpha: 0.6),
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Emergency Vault is Clean',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Any accidentally deleted or dismissed items will be safely captured here for instant recovery.',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _vaultRecords.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (context, index) {
                          final item = _vaultRecords[index];
                          final entity = (item['entity'] as String?)?.toUpperCase() ?? 'RECORD';
                          final deletedAt = item['deleted_at'] as String? ?? '';
                          final user = item['user_name'] as String? ?? 'Admin';
                          final data = item['data'] as Map<String, dynamic>? ?? {};
                          final remarks = data['remarks'] ?? data['name'] ?? 'Record';

                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.rejected.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.rejected,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '$entity: $remarks',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'Deleted by $user • $deletedAt',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded,
                                  color: AppColors.textSecondary, size: 20),
                              tooltip: 'Purge from vault',
                              onPressed: () async {
                                final vaultId = item['vault_id'] as String?;
                                if (vaultId != null) {
                                  await AuditService.purgeVaultEntry(vaultId);
                                  _loadVault();
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTextStyles.h3.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String buttonText,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '1-CLICK',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: isLoading ? null : onTap,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                isLoading ? 'Generating...' : buttonText,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
