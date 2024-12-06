import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import './api_service.dart';

class SettingsService {
  static const String _baseUrlKey = 'baseUrl';
  static const String _apiKeyKey = 'apiKey';
  static const String _userIdKey = 'defaultUserId';
  final _api = ApiService();

  Future<void> saveSettings({
    String? baseUrl,
    String? apiKey,
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (baseUrl != null) await prefs.setString(_baseUrlKey, baseUrl);
    if (apiKey != null) await prefs.setString(_apiKeyKey, apiKey);
    if (userId != null) await prefs.setString(_userIdKey, userId);
  }

  Future<Map<String, String>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'baseUrl': prefs.getString(_baseUrlKey) ?? ApiConfig.baseUrl,
      'apiKey': prefs.getString(_apiKeyKey) ?? ApiConfig.apiKey,
      'defaultUserId': prefs.getString(_userIdKey) ?? ApiConfig.defaultUserId,
    };
  }

  Future<Map<String, dynamic>> getApiInfo() async {
    try {
      final response = await _api.request('GET', ApiConfig.info);
      return response;
    } catch (e) {
      return {
        'name': 'Chat App',
        'description': 'A chat application',
        'tags': []
      };
    }
  }
}
