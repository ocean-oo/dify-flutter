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
    _log.info('已缓存会话 $conversationId 的 ${messages.length} 条消息');
  }

  Future<List<ChatMessage>> getCachedMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    final messagesJson = prefs.getString(key);
    if (messagesJson == null) {
      _log.info('未找到会话 $conversationId 的缓存消息');
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(messagesJson);
      final messages = decoded.map((m) => ChatMessage.fromJson(m)).toList();
      _log.info('从缓存加载了 ${messages.length} 条消息');
      return messages;
    } catch (e) {
      _log.severe('解析缓存消息失败: $e');
      return [];
    }
  }

  Future<void> addOneMsgToCache(
      String conversationId, ChatMessage message) async {
    final cachedMsg = await getCachedMessages(conversationId);
    cachedMsg.add(message);
    await setCacheMessages(conversationId, cachedMsg);
  }

  // 删除会话的缓存消息
  Future<void> clearCachedMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    await prefs.remove(key);
    _log.info('已清除会话 $conversationId 的缓存消息');
  }
}
