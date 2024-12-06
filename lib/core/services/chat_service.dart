import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import '../../features/chat/models/chart_message.dart';
import '../../features/chat/models/conversation.dart';
import '../../features/chat/models/message_history.dart';
import '../../features/chat/models/stream_response.dart';
import '../config/api_config.dart';
import './api_service.dart';
import './cache_service.dart';

class ChatService {
  static final _log = Logger('ChatService');
  final _api = ApiService();
  final _cache = CacheService();
  String? _currentConversationId;
  final StreamController<ChatMessage> messageStreamController =
      StreamController<ChatMessage>();

  String? get currentConversationId => _currentConversationId;

  void setConversationId(String? id) {
    _currentConversationId = id;
  }

  Future<List<ChatMessage>> getMessageHistory(String conversationId) async {
    _log.info('获取会话消息历史: $conversationId');
    try {
      // 先尝试从缓存获取消息
      final cachedMessages = await _cache.getCachedMessages(conversationId);
      if (cachedMessages.isNotEmpty) {
        _log.info('使用缓存的消息');
        return cachedMessages;
      }
      // 如果缓存为空，则从服务器获取
      final queryParams = {
        'conversation_id': conversationId,
      };
      final response = await _api.request('GET', ApiConfig.messageHistory,
          queryParams: queryParams);
      final List<dynamic> messagesJson = response['data'];
      _log.info('消息数量: ${messagesJson.length}');
      final messages = messagesJson
          .map((json) => MessageHistory.fromJson(json))
          .expand((history) => [
                ChatMessage.fromMessageHistory(history, true),
                ChatMessage.fromMessageHistory(history, false),
              ])
          .toList();
      // 按时间排序
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // 缓存获取到的消息
      await _cache.setCacheMessages(conversationId, messages);
      _log.info('处理后的消息数量: ${messages.length}');

      return messages;
    } catch (e, stack) {
      _log.severe('获取消息历史出错: $e');
      _log.fine('错误堆栈: $stack');
      rethrow;
    }
  }

  Future<List<Conversation>> getConversations({int limit = 20}) async {
    _log.info('开始获取会话列表, 限制数量: $limit');
    final queryParams = {'limit': limit.toString()};
    final response = await _api.request('GET', ApiConfig.conversations,
        queryParams: queryParams);
    final List<dynamic> conversationsJson = response['data'];
    _log.info('会话数量: ${conversationsJson.length}');
    return conversationsJson
        .map((json) => Conversation.fromJson(json))
        .toList();
  }

  Future<ChatMessage> sendMessage(ChatMessage msg) async {
    _log.info('消息内容: ${msg.content}');
    _log.info('当前会话ID: $_currentConversationId');
    if (msg.files != null) {
      _log.info('附带文件数量: ${msg.files!.length}');
    }

    try {
      final Map<String, dynamic> body = {
        'inputs': {},
        'query': msg.content,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
      };

      if (msg.files != null) {
        body['files'] = msg.files!.map((f) => f.toRequest()).toList();
      }

      final response =
          await _api.streamRequest('POST', ApiConfig.chatMessages, body: body);

      String currentAnswer = '';
      String? currentMessageId;
      String? currentConversationId;
      int? createdAt;
      String pendingData = '';

      // 创建初始消息
      final initialMessage = ChatMessage(
        content: '',
        isUser: false,
        timestamp: DateTime.now(),
        isStreaming: true,
      );
      messageStreamController.add(initialMessage);

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pendingData += chunk;

        while (true) {
          final lineEnd = pendingData.indexOf('\n');
          if (lineEnd == -1) break;

          final line = pendingData.substring(0, lineEnd).trim();
          pendingData = pendingData.substring(lineEnd + 1);

          if (line.isEmpty || !line.startsWith('data: ')) continue;

          try {
            final jsonStr = line.substring(6);
            final json = jsonDecode(jsonStr);
            final streamResponse = StreamResponse.fromJson(json);

            if (streamResponse.isMessage && streamResponse.answer != null) {
              currentAnswer += streamResponse.answer!;
              currentMessageId = streamResponse.messageId;
              currentConversationId = streamResponse.conversationId;
              createdAt = streamResponse.createdAt;
              _currentConversationId = currentConversationId;

              // 发送更新的消息
              final updatedMessage = ChatMessage(
                content: currentAnswer,
                isUser: false,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    (createdAt ?? DateTime.now().millisecondsSinceEpoch) *
                        1000),
                messageId: currentMessageId,
                conversationId: currentConversationId,
                isStreaming: true,
              );
              messageStreamController.add(updatedMessage);
            }
          } catch (e) {
            _log.severe('解析消息时出错: $e');
          }
        }
      }

      // 发送最终消息
      final finalMessage = ChatMessage(
        content: currentAnswer,
        isUser: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (createdAt ?? DateTime.now().millisecondsSinceEpoch) * 1000),
        messageId: currentMessageId,
        conversationId: currentConversationId,
        isStreaming: false,
      );
      messageStreamController.add(finalMessage);

      // 收到返回时，同时更新用户消息和最终消息
      if (currentConversationId != null) {
        await _cache.addOneMsgToCache(currentConversationId, msg);
        await _cache.addOneMsgToCache(currentConversationId, finalMessage);
      }

      return finalMessage;
    } catch (e, stack) {
      _log.severe('发送消息时出错: $e');
      _log.fine('堆栈: $stack');
      rethrow;
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    _log.info('删除会话: $conversationId');
    await _api.request('DELETE', '${ApiConfig.conversations}/$conversationId');
    await _cache.clearCachedMessages(conversationId);
    _log.info('成功删除会话及其缓存');
  }

  Future<String> renameConversation(String conversationId, String name,
      {bool autoGenerate = false}) async {
    _log.info('开始重命名会话');

    final requestBody = {
      'name': name.isEmpty ? '' : name,
      'auto_generate': autoGenerate,
    };

    final response = await _api.request(
      'POST',
      '${ApiConfig.conversations}/$conversationId${ApiConfig.conversationRename}',
      body: requestBody,
    );

    return response['name'];
  }
}
