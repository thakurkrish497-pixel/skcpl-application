class TaskCommentModel {
  final String id;
  final String taskId;
  final String userId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  
  // Optional field to hold the user's name if fetched via join
  final String? userName;

  const TaskCommentModel({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.userName,
  });

  factory TaskCommentModel.fromJson(Map<String, dynamic> json) {
    return TaskCommentModel(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['users'] != null ? json['users']['full_name'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'user_id': userId,
      'content': content,
      'image_url': imageUrl,
    };
  }
}
