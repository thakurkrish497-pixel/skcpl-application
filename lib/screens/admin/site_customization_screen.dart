import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/site_model.dart';
import '../../models/dropdown_item_model.dart';
import '../../providers/dropdown_provider.dart';
import '../../providers/site_provider.dart';

/// Admin screen to fully customize a specific site:
/// Basic info, login ID, password, allocated budget, active status,
/// and site-scoped dropdowns (Vendors, Materials, Units, Expense Types).
class SiteCustomizationScreen extends ConsumerStatefulWidget {
  final SiteModel site;

  const SiteCustomizationScreen({
    super.key,
    required this.site,
  });

  @override
  ConsumerState<SiteCustomizationScreen> createState() =>
      _SiteCustomizationScreenState();
}

class _SiteCustomizationScreenState
    extends ConsumerState<SiteCustomizationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SiteModel _currentSite;

  // Controllers for Site Details tab
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _loginIdController;
  late TextEditingController _budgetController;
  final TextEditingController _passwordController = TextEditingController();
  final _siteFormKey = GlobalKey<FormState>();

  bool _isSavingSite = false;
  bool _obscurePassword = true;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _currentSite = widget.site;
    _tabController = TabController(length: 5, vsync: this);

    _nameController = TextEditingController(text: _currentSite.name);
    _addressController = TextEditingController(text: _currentSite.address ?? '');
    _loginIdController = TextEditingController(text: _currentSite.siteLoginId);
    _budgetController =
        TextEditingController(text: _currentSite.allocatedBudget.toStringAsFixed(0));
    _isActive = _currentSite.isActive;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _loginIdController.dispose();
    _budgetController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveSiteDetails() async {
    if (!_siteFormKey.currentState!.validate()) return;

    setState(() => _isSavingSite = true);
    final siteService = ref.read(siteServiceProvider);

    try {
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'site_login_id': _loginIdController.text.trim(),
        'allocated_budget':
            double.tryParse(_budgetController.text.trim()) ?? 0.0,
        'is_active': _isActive,
      };

      if (_passwordController.text.trim().isNotEmpty) {
        updates['password'] = _passwordController.text.trim();
      }

      final updatedSite = await siteService.updateSite(_currentSite.id, updates);

      setState(() {
        _currentSite = updatedSite;
        _passwordController.clear();
      });

      ref.invalidate(allSitesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Site settings saved successfully!'),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating site: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSite = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customize Site', style: AppTextStyles.h4),
            Text(
              _currentSite.name,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Site Details'),
            Tab(icon: Icon(Icons.inventory_2_rounded, size: 18), text: 'Materials'),
            Tab(icon: Icon(Icons.store_rounded, size: 18), text: 'Vendors'),
            Tab(icon: Icon(Icons.straighten_rounded, size: 18), text: 'Units'),
            Tab(icon: Icon(Icons.payments_rounded, size: 18), text: 'Expense Types'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSiteDetailsTab(),
          _SiteDropdownTab(
            siteId: _currentSite.id,
            siteName: _currentSite.name,
            category: DropdownCategory.product,
          ),
          _SiteDropdownTab(
            siteId: _currentSite.id,
            siteName: _currentSite.name,
            category: DropdownCategory.vendor,
          ),
          _SiteDropdownTab(
            siteId: _currentSite.id,
            siteName: _currentSite.name,
            category: DropdownCategory.metricUnit,
          ),
          _SiteDropdownTab(
            siteId: _currentSite.id,
            siteName: _currentSite.name,
            category: DropdownCategory.expenseType,
          ),
        ],
      ),
    );
  }

  Widget _buildSiteDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _siteFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_city, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentSite.name,
                          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${_currentSite.siteLoginId}',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isActive,
                    activeThumbColor: AppColors.approved,
                    onChanged: (val) => setState(() => _isActive = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'SITE CREDENTIALS & INFO',
              style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),

            // Site Name
            TextFormField(
              controller: _nameController,
              validator: (v) => Validators.required(v, 'Site Name'),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Site Name',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Address
            TextFormField(
              controller: _addressController,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Location / Address',
                prefixIcon: Icon(Icons.place_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Allocated Budget
            TextFormField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Must be a valid number';
                return null;
              },
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Allocated Budget (₹)',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Login ID
            TextFormField(
              controller: _loginIdController,
              validator: (v) => Validators.required(v, 'Login ID'),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Site Worker Login ID',
                prefixIcon: Icon(Icons.badge_rounded),
                helperText: 'Used by site workers to sign in',
              ),
            ),
            const SizedBox(height: 14),

            // Password Reset Field
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              validator: (v) {
                if (v != null && v.isNotEmpty && v.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Reset Worker Password',
                hintText: 'Leave empty to keep unchanged',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSavingSite ? null : _saveSiteDetails,
                icon: _isSavingSite
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSavingSite ? 'Saving...' : 'Save Site Details',
                  style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dedicated tab component for managing site-scoped dropdowns (Materials, Vendors, Units, Expense Types)
class _SiteDropdownTab extends ConsumerStatefulWidget {
  final String siteId;
  final String siteName;
  final DropdownCategory category;

  const _SiteDropdownTab({
    required this.siteId,
    required this.siteName,
    required this.category,
  });

  @override
  ConsumerState<_SiteDropdownTab> createState() => _SiteDropdownTabState();
}

class _SiteDropdownTabState extends ConsumerState<_SiteDropdownTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSeeding = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Add ${widget.category.displayName} for ${widget.siteName}',
          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
        ),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: '${widget.category.displayName} Name',
            hintText: 'e.g. ${widget.category == DropdownCategory.vendor ? "Sharma Building Materials" : widget.category == DropdownCategory.product ? "UltraTech Cement" : "New Item"}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(this.context);
              final service = ref.read(dropdownServiceProvider);
              try {
                await service.addDropdown(
                  category: widget.category,
                  value: text,
                  siteId: widget.siteId,
                );
                ref.invalidate(allDropdownsProvider(
                    (category: widget.category, siteId: widget.siteId)));
                ref.invalidate(dropdownProvider(
                    (category: widget.category, siteId: widget.siteId)));
                nav.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Added "$text" to ${widget.siteName}!'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.rejected,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(DropdownItemModel item) {
    final controller = TextEditingController(text: item.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Edit ${widget.category.displayName}',
          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
        ),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(this.context);
              final service = ref.read(dropdownServiceProvider);
              try {
                await service.updateDropdown(item.id, {'value': text});
                ref.invalidate(allDropdownsProvider(
                    (category: widget.category, siteId: widget.siteId)));
                ref.invalidate(dropdownProvider(
                    (category: widget.category, siteId: widget.siteId)));
                nav.pop();
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.rejected,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(DropdownItemModel item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Delete "${item.value}"?',
          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete this ${widget.category.displayName.toLowerCase()} for ${widget.siteName}? If it is already used in transactions, you should deactivate it instead.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rejected),
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(this.context);
              nav.pop();
              final service = ref.read(dropdownServiceProvider);
              try {
                await service.deleteDropdown(item.id);
                ref.invalidate(allDropdownsProvider(
                    (category: widget.category, siteId: widget.siteId)));
                ref.invalidate(dropdownProvider(
                    (category: widget.category, siteId: widget.siteId)));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Deleted successfully'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('$e'),
                    backgroundColor: AppColors.rejected,
                    duration: const Duration(seconds: 4),
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

  Future<void> _importStandardDefaults() async {
    setState(() => _isSeeding = true);
    final service = ref.read(dropdownServiceProvider);

    try {
      final addedCount =
          await service.seedCategoryDefaultsForSite(widget.siteId, widget.category);
      ref.invalidate(allDropdownsProvider(
          (category: widget.category, siteId: widget.siteId)));
      ref.invalidate(dropdownProvider(
          (category: widget.category, siteId: widget.siteId)));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              addedCount > 0
                  ? 'Imported $addedCount standard ${widget.category.displayName}!'
                  : 'All standard ${widget.category.displayName} already exist for this site.',
            ),
            backgroundColor: AppColors.approved,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing defaults: $e'),
            backgroundColor: AppColors.rejected,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSeeding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(allDropdownsProvider(
        (category: widget.category, siteId: widget.siteId)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_site_${widget.category.name}_${widget.siteId}',
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: Text('Add ${widget.category.displayName}'),
      ),
      body: Column(
        children: [
          // Top Controls (Search & Import Defaults)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.category.displayName.toLowerCase()}...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isSeeding ? null : _importStandardDefaults,
                  icon: _isSeeding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Import Defaults'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading items: $e',
                      style: const TextStyle(color: AppColors.rejected)),
                ),
              ),
              data: (items) {
                final filtered = items.where((it) {
                  if (_searchQuery.isEmpty) return true;
                  return it.value.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              color: AppColors.textTertiary, size: 52),
                          const SizedBox(height: 14),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No matching items found'
                                : 'No ${widget.category.displayName} added for this site yet',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap "+ Add" or "Import Defaults" to configure this site.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.divider, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.isActive
                                ? Icons.check_circle_rounded
                                : Icons.remove_circle_outline_rounded,
                            color: item.isActive
                                ? AppColors.approved
                                : AppColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.value,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: item.isActive
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary,
                                decoration: item.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                          // Edit button
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            color: AppColors.textSecondary,
                            tooltip: 'Edit name',
                            onPressed: () => _showEditDialog(item),
                          ),
                          // Delete button
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 20),
                            color: AppColors.rejected,
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(item),
                          ),
                          // Active Switch
                          Switch(
                            value: item.isActive,
                            activeThumbColor: AppColors.approved,
                            onChanged: (val) async {
                              final service = ref.read(dropdownServiceProvider);
                              await service.toggleActive(item.id, val);
                              ref.invalidate(allDropdownsProvider((
                                category: widget.category,
                                siteId: widget.siteId
                              )));
                              ref.invalidate(dropdownProvider((
                                category: widget.category,
                                siteId: widget.siteId
                              )));
                            },
                          ),
                        ],
                      ),
                    ).animate().fadeIn(
                          delay: Duration(milliseconds: 20 * index),
                        );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
