import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';
import '../services/task_service.dart';
import 'auth_provider.dart';

/// Provides the TaskService instance
final taskServiceProvider = Provider<TaskService>((ref) {
  final supabase = ref.read(supabaseServiceClientProvider);
  return TaskService(supabase);
});

/// FutureProvider to fetch all tasks for a specific site
final siteTasksProvider = FutureProvider.family<List<TaskModel>, String>((ref, siteId) {
  final taskService = ref.read(taskServiceProvider);
  return taskService.getTasksForSite(siteId);
});

/// FutureProvider to fetch all tasks (for Admin)
final allTasksAdminProvider = FutureProvider<List<TaskModel>>((ref) async {
  final taskService = ref.read(taskServiceProvider);
  return taskService.getAllTasks();
});

/// FutureProvider to fetch all tasks assigned to the current user
final myTasksProvider = FutureProvider<List<TaskModel>>((ref) async {
  final taskService = ref.read(taskServiceProvider);
  final user = ref.watch(authProvider).user;
  
  if (user == null) return [];
  
  return taskService.getTasksForUser(user.id);
});

/// FutureProvider to fetch a single task by ID
final taskDetailProvider = FutureProvider.family<TaskModel, String>((ref, taskId) {
  final taskService = ref.read(taskServiceProvider);
  return taskService.getTaskById(taskId);
});

/// StreamProvider for real-time task comments
final taskCommentsProvider = StreamProvider.family<List<TaskCommentModel>, String>((ref, taskId) {
  final taskService = ref.read(taskServiceProvider);
  return taskService.getCommentsStream(taskId);
});
