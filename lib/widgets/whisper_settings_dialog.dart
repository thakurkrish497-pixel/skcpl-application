import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../services/whisper_service.dart';

class WhisperSettingsDialog extends StatefulWidget {
  const WhisperSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const WhisperSettingsDialog(),
    );
  }

  @override
  State<WhisperSettingsDialog> createState() => _WhisperSettingsDialogState();
}

class _WhisperSettingsDialogState extends State<WhisperSettingsDialog> {
  final _service = WhisperService();
  final _keyController = TextEditingController();
  String _provider = 'groq'; // 'groq' | 'openai'
  bool _isLoading = true;
  bool _isTesting = false;
  bool _obscureText = true;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prov = await _service.getProvider();
    final key = await _service.getApiKey();
    if (mounted) {
      setState(() {
        _provider = prov;
        _keyController.text = key ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testMessage = 'Please enter an API key to test.';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    final success = await _service.verifyKey(key, _provider);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = success;
        _testMessage = success
            ? 'Connected successfully to ${_provider.toUpperCase()} Whisper!'
            : 'Connection failed. Please check the API key and internet.';
      });
    }
  }

  Future<void> _save() async {
    await _service.setProvider(_provider);
    await _service.saveApiKey(_keyController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice-to-Text settings saved successfully!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.settings_voice_rounded, color: AppColors.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Voice-to-Text Setup',
                                style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
                              ),
                              Text(
                                'Extreme-accuracy Hindi & English speech engine',
                                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Provider selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(() => _provider = 'groq');
                                final key = await _service.getApiKey();
                                _keyController.text = key ?? '';
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _provider == 'groq' ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    'Groq Whisper (Free)',
                                    style: TextStyle(
                                      color: _provider == 'groq' ? Colors.black : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(() => _provider = 'openai');
                                final key = await _service.getApiKey();
                                _keyController.text = key ?? '';
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _provider == 'openai' ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    'OpenAI Whisper',
                                    style: TextStyle(
                                      color: _provider == 'openai' ? Colors.black : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _provider == 'groq'
                                ? '⚡ Groq Whisper provides sub-second (~300ms) transcription and is 100% free with no credit card needed.'
                                : '🤖 OpenAI Whisper provides standard whisper-1 transcription.',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () {
                              final url = _provider == 'groq'
                                  ? 'https://console.groq.com/keys'
                                  : 'https://platform.openai.com/api-keys';
                              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.open_in_new, color: AppColors.primary, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  _provider == 'groq'
                                      ? 'Get Free Groq API Key (console.groq.com)'
                                      : 'Get OpenAI API Key (platform.openai.com)',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // API Key Field
                    Text(
                      '${_provider.toUpperCase()} API KEY',
                      style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _keyController,
                      obscureText: _obscureText,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _provider == 'groq' ? 'gsk_...' : 'sk-...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: AppColors.cardDark,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.divider),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscureText = !_obscureText),
                        ),
                      ),
                    ),

                    if (_testMessage != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            _testSuccess ? Icons.check_circle : Icons.error,
                            color: _testSuccess ? AppColors.approved : AppColors.rejected,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testMessage!,
                              style: TextStyle(
                                color: _testSuccess ? AppColors.approved : AppColors.rejected,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 22),

                    // Actions
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _isTesting ? null : _testConnection,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.divider),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          child: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                )
                              : const Text('Test Connection', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
