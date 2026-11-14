import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class RoleGate extends ConsumerWidget {
  final List<UserRole> allowedRoles;
  final Widget child;
  const RoleGate({super.key, required this.allowedRoles, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider);
    if (session.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session.user == null || !allowedRoles.contains(session.user!.role)) {
      return Scaffold(
          appBar: AppBar(title: const Text('Access required')),
          body: const Center(
              child: Text(
                  'Sign in with the required company role to open this page.')));
    }
    return child;
  }
}
