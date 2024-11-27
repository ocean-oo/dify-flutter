class ApiConfig {
  static const String baseUrl = 'https://api.dify.ai/v1';
  
  // API Key
  static const String apiKey = 'app-Zlmq1rDUsq2AdFPxyAMyyQuq';
  
  // API endpoints
  static const String login = '/auth/login';
  static const String messages = '/messages';
  static const String users = '/users';
  static const String chatMessages = '/chat-messages';
  static const String conversations = '/conversations';
  static const String messageHistory = '/message-history';
  
  // WebSocket URL
  static const String wsUrl = 'YOUR_WEBSOCKET_URL';
  
  // Headers
  static Map<String, String> get headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  // Default user ID (in real app, this might come from user settings)
  static const String defaultUserId = 'app-user';
}
