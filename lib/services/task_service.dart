import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/task_comment_model.dart';

class TaskService {
  final SupabaseClient _client;

  TaskService(this._client);

  /// Fetch tasks for a specific site
  Future<List<TaskModel>> getTasksForSite(String siteId) async {
    final data = await _client
        .from('tasks')
        .select()
        .eq('site_id', siteId)
        .order('created_at', ascending: false);

    return (data as List).map((json) => TaskModel.fromJson(json)).toList();
  }

  /// Fetch all tasks across all sites (for Admin)
  Future<List<TaskModel>> getAllTasks() async {
    final data = await _client
        .from('tasks')
        .select()
        .order('created_at', ascending: false);

    return (data as List).map((json) => TaskModel.fromJson(json)).toList();
  }

  /// Fetch tasks assigned to a specific user
  Future<List<TaskModel>> getTasksForUser(String userId) async {
    final data = await _client
        .from('tasks')
        .select()
        .eq('assigned_to', userId)
        .order('created_at', ascending: false);

    return (data as List).map((json) => TaskModel.fromJson(json)).toList();
  }

  /// Create a new task
  Future<TaskModel> createTask({
    required String siteId,
    required String title,
    String? description,
    String? assignedTo,
    required String createdBy,
    String status = 'pending',
    String priority = 'medium',
  }) async {
    final data = await _client.from('tasks').insert({
      'site_id': siteId,
      'title': title,
      'description': description,
      'assigned_to': assignedTo,
      'created_by': createdBy,
      'status': status,
      'priority': priority,
    }).select().single();

    return TaskModel.fromJson(data);
  }

  /// Update an existing task
  Future<TaskModel> updateTask(String taskId, Map<String, dynamic> updates) async {
    final data = await _client
        .from('tasks')
        .update(updates)
        .eq('id', taskId)
        .select()
        .single();

    return TaskModel.fromJson(data);
  }

  /// Fetch a single task by ID
  Future<TaskModel> getTaskById(String taskId) async {
    final data = await _client
        .from('tasks')
        .select()
        .eq('id', taskId)
        .single();
    
    return TaskModel.fromJson(data);
  }

  /// Get real-time stream of comments for a task
  Stream<List<TaskCommentModel>> getCommentsStream(String taskId) {
    return _client
        .from('task_comments')
        .stream(primaryKey: ['id'])
        .eq('task_id', taskId)
        .order('created_at', ascending: true)
        .map((list) => list.map((json) => TaskCommentModel.fromJson(json)).toList());
  }

  /// Add a new comment to a task
  Future<void> addComment({
    required String taskId,
    required String userId,
    required String content,
    String? imageUrl,
  }) async {
    await _client.from('task_comments').insert({
      'task_id': taskId,
      'user_id': userId,
      'content': content,
      'image_url': imageUrl,
    });
  }
}
