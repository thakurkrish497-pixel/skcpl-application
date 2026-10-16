import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_provider.dart';
import 'site_details_screen.dart';

/// Admin screen for creating and managing construction sites
class ManageSitesScreen extends ConsumerStatefulWidget {
  const ManageSitesScreen({super.key});

  @override
  ConsumerState<ManageSitesScreen> createState() => _ManageSitesScreenState();
}

class _ManageSitesScreenState extends ConsumerState<ManageSitesScreen> {
  void _showCreateSiteDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final loginIdController = TextEditingController();
    final passwordController = TextEditingController();
    final budgetController = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Create New Site',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  validator: (v) => Validators.required(v, 'Site Name'),
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Site Name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: addressController,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: loginIdController,
                  validator: (v) => Validators.required(v, 'Login ID'),
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Site Login ID',
                    helperText: 'Unique credential for workers',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: budgetController,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Must be a number';
                    return null;
                  },
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Allocated Budget'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: passwordController,
                  validator: Validators.password,
                  obscureText: true,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Site Password'),
                ),
              ],
            ),
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
              if (!formKey.currentState!.validate()) return;

              final siteService = ref.read(siteServiceProvider);
              try {
                await siteService.createSite(
                  name: nameController.text.trim(),
                  address: addressController.text.trim(),
                  loginId: loginIdController.text.trim(),
                  password: passwordController.text,
                  createdBy: ref.read(authServiceProvider).currentUserId!,
                  allocatedBudget: double.tryParse(budgetController.text) ?? 0.0,
                );
                ref.refresh(allSitesProvider);
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: const Text('Site created successfully!'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.rejected,
                  ),
                );
              }
            },
            child: const Text('Create Site'),
          ),
        ],
      ),
    );
  }

  void _showEditSiteDialog(SiteModel site) {
    final nameController = TextEditingController(text: site.name);
    final addressController = TextEditingController(text: site.address);
    final budgetController = TextEditingController(text: site.allocatedBudget.toString());
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Edit Site',
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  validator: (v) => Validators.required(v, 'Site Name'),
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Site Name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: addressController,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: budgetController,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Must be a number';
                    return null;
                  },
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Allocated Budget'),
                ),
              ],
            ),
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
              if (!formKey.currentState!.validate()) return;

              final siteService = ref.read(siteServiceProvider);
              try {
                await siteService.updateSite(site.id, {
                  'name': nameController.text.trim(),
                  'address': addressController.text.trim(),
                  'allocated_budget': double.tryParse(budgetController.text) ?? 0.0,
                });
                ref.refresh(allSitesProvider);
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: const Text('Site updated successfully!'),
                    backgroundColor: AppColors.approved,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.rejected,
                  ),
                );
              }
            },
            child: const Text('Save Changes'),
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
      appBar: AppBar(title: const Text('Manage Sites')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSiteDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Site'),
      ),
      body: sitesAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sites) => sites.isEmpty
            ? Center(
                child: Text('No sites yet. Tap + to create one.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary)),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final site = sites[index];
                     return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SiteDetailsScreen(site: site),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AppColors.divider, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.construction,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(site.name,
                                    style: AppTextStyles.labelLarge.copyWith(
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text(
                                  'Login: ${site.siteLoginId}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          // Status
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: site.isActive
                                  ? AppColors.approvedSurface
                                  : AppColors.rejectedSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              site.isActive ? 'Active' : 'Inactive',
                              style: AppTextStyles.caption.copyWith(
                                color: site.isActive
                                    ? AppColors.approved
                                    : AppColors.rejected,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            color: AppColors.cardDark,
                            onSelected: (val) async {
                              final siteService = ref.read(siteServiceProvider);
                              if (val == 'deactivate') {
                                await siteService.deactivateSite(site.id);
                              } else if (val == 'activate') {
                                await siteService.activateSite(site.id);
                              } else if (val == 'edit') {
                                _showEditSiteDialog(site);
                                return; // Don't refresh yet
                              }
                              ref.invalidate(allSitesProvider);
                            },
                            itemBuilder: (context) => [
                              if (site.isActive)
                                const PopupMenuItem(
                                  value: 'deactivate',
                                  child: Text('Deactivate',
                                      style: TextStyle(color: AppColors.rejected)),
                                )
                              else
                                const PopupMenuItem(
                                  value: 'activate',
                                  child: Text('Activate',
                                      style: TextStyle(color: AppColors.approved)),
                                ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit Details', style: TextStyle(color: AppColors.primary)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(
                        delay: Duration(milliseconds: 50 * index),
                      );
                },
              ),
      ),
    );
  }
}
