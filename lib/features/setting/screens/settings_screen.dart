import 'package:chat_app/core/config/api_config.dart';
import 'package:flutter/material.dart';
import '../../../core/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = SettingsService();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _userIdController = TextEditingController();
  String _originalApiKey = '';


  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) return apiKey;
    return '${apiKey.substring(0, 4)}${'*' * (apiKey.length - 8)}${apiKey.substring(apiKey.length - 4)}';
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.getSettings();
    setState(() {
      _baseUrlController.text = settings['baseUrl']!;
      _originalApiKey = settings['apiKey']!;
      _apiKeyController.text = _maskApiKey(_originalApiKey);
      _userIdController.text = settings['defaultUserId']!;
    });
  }

  Future<void> _saveSettings() async {
    final apiKey = _apiKeyController.text.contains('*')
        ? _originalApiKey
        : _apiKeyController.text;

    await _settingsService.saveSettings(
      baseUrl: _baseUrlController.text,
      apiKey: apiKey,
      userId: _userIdController.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'Enter API base URL',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'Enter API key',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'User ID',
                hintText: 'Enter user ID',
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save Settings'),
            ),
            const Spacer(),
            const Text(
              'Version ${ApiConfig.version}',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _userIdController.dispose();
    super.dispose();
  }
}
