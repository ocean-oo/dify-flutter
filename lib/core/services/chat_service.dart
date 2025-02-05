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
    _log.info("====== get message history ======");
    _log.info('conversation id : $conversationId');
    try {
      final cachedMessages = await _cache.getCachedMessages(conversationId);
      if (cachedMessages.isNotEmpty) {
        _log.info('Using cached messages');
        return cachedMessages;
      }
      final queryParams = {
        'conversation_id': conversationId,
      };
      final response = await _api.request('GET', ApiConfig.messageHistory,
          queryParams: queryParams);
      final List<dynamic> messagesJson = response['data'];
      _log.info('Number of messages: ${messagesJson.length}');
      final messages = messagesJson
          .map((json) => MessageHistory.fromJson(json))
          .expand((history) => [
                ChatMessage.fromMessageHistory(history, true),
                ChatMessage.fromMessageHistory(history, false),
              ])
          .toList();
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await _cache.setCacheMessages(conversationId, messages);
      _log.info('The number of messages processed: ${messages.length}');

      return messages;
    } catch (e, stack) {
      _log.severe('Error getting message history: $e');
      _log.fine('stack: $stack');
      rethrow;
    }
  }

  Future<List<Conversation>> getConversations({int limit = 20}) async {
    _log.info('get list limit: $limit');
    final queryParams = {'limit': limit.toString()};
    final response = await _api.request('GET', ApiConfig.conversations,
        queryParams: queryParams);
    final List<dynamic> conversationsJson = response['data'];
    _log.info('length limit: ${conversationsJson.length}');
    return conversationsJson
        .map((json) => Conversation.fromJson(json))
        .toList();
  }

  Future<ChatMessage> sendMessage(ChatMessage msg) async {
    _log.info('content: ${msg.content}');
    _log.info('conversation id: $_currentConversationId');
    if (msg.files != null) {
      _log.info('length file: ${msg.files!.length}');
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
          _log.info(pendingData);
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
            _log.severe('Error parsing message: $e');
          }
        }
      }

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
      if (currentConversationId != null) {
        await _cache.addOneMsgToCache(currentConversationId, msg);
        await _cache.addOneMsgToCache(currentConversationId, finalMessage);
      }
      return finalMessage;
    } catch (e, stack) {
      _log.severe('Error sending message: $e');
      _log.fine('Stack: $stack');
      rethrow;
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    _log.info('Deleting a Session: $conversationId');
    await _api.request('DELETE', '${ApiConfig.conversations}/$conversationId');
    await _cache.clearCachedMessages(conversationId);
    _log.info('The session and its cache were deleted successfully');
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
