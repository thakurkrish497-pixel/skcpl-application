import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import '../../providers/task_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/chat_bubble.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      String? imageUrl;
      // TODO: Implement StorageService logic to upload _selectedImage and get URL
      // if (_selectedImage != null) {
      //   imageUrl = await ref.read(storageServiceProvider).uploadTaskImage(widget.taskId, _selectedImage!);
      // }

      await ref.read(taskServiceProvider).addComment(
        taskId: widget.taskId,
        userId: user.id,
        content: text.isNotEmpty ? text : 'Attached an image',
        imageUrl: imageUrl,
      );

      _messageController.clear();
      setState(() {
        _selectedImage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taskAsync = ref.watch(taskDetailProvider(widget.taskId));
    final commentsAsync = ref.watch(taskCommentsProvider(widget.taskId));
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: [
          taskAsync.when(
            data: (task) => Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: DropdownButton<String>(
                  value: task.status,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  dropdownColor: theme.colorScheme.primary,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      ref.read(taskServiceProvider).updateTask(task.id, {'status': newValue});
                      ref.invalidate(taskDetailProvider(widget.taskId));
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'verified', child: Text('Verified')),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Task Info Header
          taskAsync.when(
            data: (task) => Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  if (task.description != null) ...[
                    const SizedBox(height: 8),
                    Text(task.description!),
                  ]
                ],
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error loading task: $err')),
          ),
          
          // Chat Stream
          Expanded(
            child: commentsAsync.when(
              data: (comments) {
                if (comments.isEmpty) {
                  return const Center(child: Text('No comments yet. Start the conversation!'));
                }
                return ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final isMe = user?.id == comment.userId;
                    return ChatBubble(comment: comment, isMe: isMe);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
          
          // Chat Input Area
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  if (_selectedImage != null)
                    Container(
                      height: 100,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(_selectedImage!, fit: BoxFit.cover, width: 80, height: 80),
                          ),
                          Positioned(
                            right: -10,
                            top: -10,
                            child: IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _selectedImage = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Iconsax.camera),
                        color: theme.colorScheme.primary,
                        onPressed: _isSending ? null : _pickImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              icon: const Icon(Iconsax.send_1),
                              color: theme.colorScheme.primary,
                              onPressed: _sendMessage,
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
