import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chat/models/chart_message.dart';

class CacheService {
  static final _log = Logger('CacheService');

  Future<void> setCacheMessages(
      String conversationId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    final messagesJson = messages.map((m) => m.toJson()).toList();
    await prefs.setString(key, jsonEncode(messagesJson));
  }

  Future<List<ChatMessage>> getCachedMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    final messagesJson = prefs.getString(key);
    if (messagesJson == null) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(messagesJson);
      final messages = decoded.map((m) => ChatMessage.fromJson(m)).toList();
      return messages;
    } catch (e) {
      return [];
    }
  }

  Future<void> addOneMsgToCache(
      String conversationId, ChatMessage message) async {
    final cachedMsg = await getCachedMessages(conversationId);
    cachedMsg.add(message);
    await setCacheMessages(conversationId, cachedMsg);
  }

  Future<void> clearCachedMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    await prefs.remove(key);
  }
}
