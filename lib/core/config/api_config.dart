import '../services/settings_service.dart';

class ApiConfig {
  static const String baseUrl = 'https://api.dify.ai/v1';
  static const String apiKey = 'app-Zlmq1rDUsq2AdFPxyAMyyQuq';
  static const String defaultUserId = 'app-user';

  static final _settingsService = SettingsService();

  static Future<Map<String, String>> get currentSettings async {
    return await _settingsService.getSettings();
  }

  // API endpoints
  static const String chatMessages = '/chat-messages';
  static const String conversations = '/conversations';
  static const String conversationRename = '/name';
  static const String messageHistory = '/messages';
  static const String fileUpload = '/files/upload';

  // Headers
  static Future<Map<String, String>> get headers async {
    final settings = await currentSettings;
    return {
      'Authorization': 'Bearer ${settings['apiKey']}',
      'Content-Type': 'application/json',
    };
  }
}
