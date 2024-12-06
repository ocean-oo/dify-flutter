import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../services/settings_service.dart';

class ApiConfig {
  // APP default config
  static const String version = '0.0.1';
  static const String baseUrl = 'https://api.dify.ai/v1';
  static const String apiKey = 'app-Zlmq1rDUsq2AdFPxyAMyyQuq';
  static String _defaultUserId = 'app-user';
  static String get defaultUserId => _defaultUserId;

  static final _settingsService = SettingsService();

  static Future<void> initialize() async {
    _defaultUserId = await getDefaultUserId();
  }

  static Future<Map<String, String>> get currentSettings async {
    return await _settingsService.getSettings();
  }

  static Future<String> getDefaultUserId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown-ios';
      }
      return 'unknown-device';
    } catch (e) {
      return 'fallback-user-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // API endpoints
  static const String chatMessages = '/chat-messages';
  static const String conversations = '/conversations';
  static const String conversationRename = '/name';
  static const String messageHistory = '/messages';
  static const String fileUpload = '/files/upload';
  static const String info = '/info';

  // Headers
  static Future<Map<String, String>> get headers async {
    final settings = await currentSettings;
    return {
      'Authorization': 'Bearer ${settings['apiKey']}',
      'Content-Type': 'application/json',
    };
  }
}
