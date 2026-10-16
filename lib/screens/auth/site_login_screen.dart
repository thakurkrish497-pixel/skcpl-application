import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../models/site_model.dart';
import '../../providers/auth_provider.dart';

/// Login screen for site workers — uses site-specific credentials
class SiteLoginScreen extends ConsumerStatefulWidget {
  final SiteModel site;
  final String module; // 'stock' or 'cashbook'

  const SiteLoginScreen({
    super.key,
    required this.site,
    required this.module,
  });

  @override
  ConsumerState<SiteLoginScreen> createState() => _SiteLoginScreenState();
}

class _SiteLoginScreenState extends ConsumerState<SiteLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill the login ID from the site
    _loginIdController.text = widget.site.siteLoginId;
  }

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authProvider.notifier).signInToSite(
          _loginIdController.text.trim(),
          _passwordController.text,
        );

    final authState = ref.read(authProvider);
    if (authState.hasSiteSession && mounted) {
      if (widget.module == 'stock') {
        Navigator.pushReplacementNamed(context, '/stock-choice');
      } else {
        Navigator.pushReplacementNamed(context, '/expense-form');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Site badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        widget.site.name,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),

                const SizedBox(height: 24),

                Text(
                  'Site Login',
                  style: AppTextStyles.h1.copyWith(color: AppColors.textPrimary),
                ).animate().fadeIn(delay: 100.ms),

                const SizedBox(height: 8),
                Text(
                  'Enter site credentials to continue',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 40),

                // Error
                if (authState.error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.rejectedSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.rejected.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      authState.error!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.rejected,
                      ),
                    ),
                  ).animate().fadeIn().shake(),

                // Login ID (pre-filled, read-only)
                TextFormField(
                  controller: _loginIdController,
                  validator: (v) => Validators.required(v, 'Login ID'),
                  readOnly: true,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Site Login ID',
                    prefixIcon: Icon(Icons.badge_outlined,
                        color: AppColors.textTertiary),
                  ),
                ).animate().fadeIn(delay: 300.ms),

                const SizedBox(height: 20),

                // Password
                TextFormField(
                  controller: _passwordController,
                  validator: Validators.password,
                  obscureText: _obscurePassword,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Site Password',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppColors.textTertiary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textTertiary,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms),

                const SizedBox(height: 36),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleLogin,
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enter Site'),
                  ),
                ).animate().fadeIn(delay: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
