import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:iconsax/iconsax.dart';
import '../../providers/task_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/site_provider.dart';
import '../../models/task_model.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'task_detail_screen.dart';

class TaskListScreen extends ConsumerWidget {
  final String? siteId; // If provided, shows tasks for this site. If null, shows tasks for current user.

  const TaskListScreen({super.key, this.siteId});

  void _showCreateTaskDialog(BuildContext context, WidgetRef ref, String? preselectedSiteId) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    String? selectedSiteId = preselectedSiteId;
    String priority = 'medium';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Create New Task', style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preselectedSiteId == null)
                  Consumer(
                    builder: (context, ref, _) {
                      final sitesAsync = ref.watch(activeSitesProvider);
                      return sitesAsync.when(
                        data: (sites) => DropdownButtonFormField<String>(
                          value: selectedSiteId,
                          decoration: const InputDecoration(labelText: 'Select Site'),
                          dropdownColor: AppColors.surfaceDark,
                          items: sites.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                          onChanged: (v) => selectedSiteId = v,
                          validator: (v) => v == null ? 'Please select a site' : null,
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (_, __) => const Text('Error loading sites'),
                      );
                    },
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: titleController,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  decoration: const InputDecoration(labelText: 'Task Title'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description (Optional)'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  dropdownColor: AppColors.surfaceDark,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => priority = v!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (selectedSiteId == null) return;

              final user = ref.read(authProvider).user!;
              final taskService = ref.read(taskServiceProvider);

              try {
                await taskService.createTask(
                  siteId: selectedSiteId!,
                  title: titleController.text.trim(),
                  description: descriptionController.text.trim(),
                  createdBy: user.id,
                  priority: priority,
                );
                
                // Refresh list
                if (siteId != null) {
                  ref.invalidate(siteTasksProvider(siteId!));
                } else if (user.isAdmin) {
                  ref.invalidate(allTasksAdminProvider);
                } else {
                  ref.invalidate(myTasksProvider);
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Task created!'), backgroundColor: AppColors.approved),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.rejected),
                  );
                }
              }
            },
            child: const Text('Create Task'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    
    // Fetch either site-specific tasks, all tasks (for admin), or user-specific tasks
    AsyncValue<List<TaskModel>> tasksAsync;
    
    if (siteId != null) {
      tasksAsync = ref.watch(siteTasksProvider(siteId!));
    } else if (user?.isAdmin == true) {
      tasksAsync = ref.watch(allTasksAdminProvider);
    } else {
      tasksAsync = ref.watch(myTasksProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(siteId != null ? 'Site Tasks' : (user?.isAdmin == true ? 'All Tasks' : 'My Tasks')),
        actions: [
          if (user != null && (user.isAdmin || user.isAccounts))
            IconButton(
              icon: const Icon(Iconsax.add),
              onPressed: () => _showCreateTaskDialog(context, ref, siteId),
            ),
        ],
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks found.'));
          }
          
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TaskCard(task: task);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;

  const _TaskCard({required this.task});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'verified':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(task.status);
    final formattedDate = DateFormat('MMM d, yyyy').format(task.createdAt.toLocal());

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Navigate to task detail screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskDetailScreen(taskId: task.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      task.status.replaceAll('_', ' ').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (task.description != null)
                Text(
                  task.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Iconsax.calendar_1, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    task.priority == 'high' ? Iconsax.arrow_up_3 : (task.priority == 'low' ? Iconsax.arrow_down : Iconsax.minus),
                    size: 14,
                    color: task.priority == 'high' ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.priority.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
