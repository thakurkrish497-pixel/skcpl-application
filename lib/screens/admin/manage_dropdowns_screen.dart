import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/dropdown_item_model.dart';
import '../../providers/dropdown_provider.dart';

/// Admin screen for managing dropdown lookup values
class ManageDropdownsScreen extends ConsumerStatefulWidget {
  final String? siteId;
  final String? siteName;

  const ManageDropdownsScreen({
    super.key,
    this.siteId,
    this.siteName,
  });

  @override
  ConsumerState<ManageDropdownsScreen> createState() =>
      _ManageDropdownsScreenState();
}

class _ManageDropdownsScreenState extends ConsumerState<ManageDropdownsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _categories = DropdownCategory.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddDialog(DropdownCategory category) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Add ${category.displayName}',
            style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
        content: TextFormField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: '${category.displayName} Name',
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
              if (controller.text.trim().isEmpty) return;
              final service = ref.read(dropdownServiceProvider);
              try {
                await service.addDropdown(
                  category: category,
                  value: controller.text.trim(),
                  siteId: widget.siteId,
                );
                ref.refresh(allDropdownsProvider((category: category, siteId: widget.siteId)));
                if (mounted) Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(this.context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        title: Text(widget.siteName != null
            ? '${widget.siteName} Dropdowns'
            : 'Global Dropdowns'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          tabs: _categories.map((c) => Tab(text: c.displayName)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((category) {
          return _DropdownCategoryTab(
            category: category,
            siteId: widget.siteId,
            onAdd: () => _showAddDialog(category),
          );
        }).toList(),
      ),
    );
  }
}

class _DropdownCategoryTab extends ConsumerWidget {
  final DropdownCategory category;
  final String? siteId;
  final VoidCallback onAdd;

  const _DropdownCategoryTab({
    required this.category,
    this.siteId,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allDropdownsProvider((category: category, siteId: siteId)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_${category.name}',
        onPressed: onAdd,
        child: const Icon(Icons.add),
      ),
      body: itemsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline,
                        color: AppColors.textTertiary, size: 48),
                    const SizedBox(height: 12),
                    Text('No ${category.displayName} yet',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Tap + to add one',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.divider, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.isActive
                              ? Icons.check_circle
                              : Icons.cancel,
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
                        // Toggle active
                        Switch(
                          value: item.isActive,
                          activeColor: AppColors.approved,
                          onChanged: (val) async {
                            final service =
                                ref.read(dropdownServiceProvider);
                            await service.toggleActive(item.id, val);
                            ref.refresh(
                                allDropdownsProvider((category: category, siteId: siteId)));
                          },
                        ),
                      ],
                    ),
                  ).animate().fadeIn(
                        delay: Duration(milliseconds: 30 * index),
                      );
                },
              ),
      ),
    );
  }
}
