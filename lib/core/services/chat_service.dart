import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../config/api_config.dart';
import './cache_service.dart';
import '../../features/chat/models/conversation.dart';
import '../../features/chat/models/message_history.dart';
import '../../features/chat/models/stream_response.dart';
import '../../features/chat/models/chart_message.dart';

class ChatService {
  static final _log = Logger('ChatService');
  final _client = http.Client();
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

    final settings = await ApiConfig.currentSettings;
    final baseUrl = settings['baseUrl'];
    final defaultUserId = settings['defaultUserId'];
    final headers = await ApiConfig.headers;

    try {
      // 先尝试从缓存获取消息
      final cachedMessages = await _cache.getCachedMessages(conversationId);
      if (cachedMessages.isNotEmpty) {
        _log.info('使用缓存的消息');
        return cachedMessages;
      }

      // 如果缓存为空，则从服务器获取
      final queryParams = {
        'user': defaultUserId,
        'conversation_id': conversationId,
      };

      _log.info('查询参数: $queryParams');
      final uri = Uri.parse('$baseUrl${ApiConfig.messages}')
          .replace(queryParameters: queryParams);
      _log.info('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: headers,
      );

      _log.info('响应状态码: ${response.statusCode}');
      _log.fine('响应头: ${response.headers}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log.info('响应数据: $data');

        final List<dynamic> messagesJson = data['data'];
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
      } else {
        final error = '获取历史消息失败: ${response.statusCode}\n${response.body}';
        _log.severe(error);
        throw Exception(error);
      }
    } catch (e, stack) {
      _log.severe('获取消息历史出错: $e');
      _log.fine('错误堆栈: $stack');
      rethrow;
    }
  }

  Future<List<Conversation>> getConversations({int limit = 20}) async {
    _log.info('开始获取会话列表');
    _log.info('限制数量: $limit');

    final settings = await ApiConfig.currentSettings;
    final baseUrl = settings['baseUrl'];
    final defaultUserId = settings['defaultUserId'];
    final headers = await ApiConfig.headers;

    try {
      final queryParams = {
        'user': defaultUserId,
        'limit': limit.toString(),
      };

      _log.info('查询参数: $queryParams');
      final uri = Uri.parse('$baseUrl${ApiConfig.conversations}')
          .replace(queryParameters: queryParams);
      _log.info('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: headers,
      );

      _log.info('响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> conversationsJson = data['data'];
        _log.info('会话数量: ${conversationsJson.length}');

        return conversationsJson
            .map((json) => Conversation.fromJson(json))
            .toList();
      } else {
        _log.fine('错误响应: ${response.body}');
        throw Exception('获取会话列表失败: ${response.statusCode}');
      }
    } catch (e, stack) {
      _log.fine('堆栈: $stack');
      throw Exception('获取会话列表出错: $e');
    }
  }

  Future<ChatMessage> sendMessage(ChatMessage msg) async {
    _log.info('消息内容: ${msg.content}');
    _log.info('当前会话ID: $_currentConversationId');
    if (msg.files != null) {
      _log.info('附带文件数量: ${msg.files!.length}');
    }

    final settings = await ApiConfig.currentSettings;
    final baseUrl = settings['baseUrl'];
    final defaultUserId = settings['defaultUserId'];
    final headers = await ApiConfig.headers;

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl${ApiConfig.chatMessages}'),
    );

    try {
      request.headers.addAll(headers);

      final Map<String, dynamic> body = {
        'inputs': {},
        'query': msg.content,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
        'user': defaultUserId,
      };

      if (msg.files != null) {
        body['files'] = msg.files!.map((f) => f.toRequest()).toList();
      }

      request.body = json.encode(body);

      final response = await _client.send(request);
      _log.info('响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.transform(utf8.decoder).join();
        throw Exception('发送消息失败: ${response.statusCode}\n$errorBody');
      }

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
    final settings = await ApiConfig.currentSettings;
    final baseUrl = settings['baseUrl'];
    final defaultUserId = settings['defaultUserId'];
    final headers = await ApiConfig.headers;
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl${ApiConfig.conversations}/$conversationId'),
        headers: headers,
        body: jsonEncode({
          'user': defaultUserId,
        }),
      );

      if (response.statusCode == 200) {
        // 同时删除缓存
        await _cache.clearCachedMessages(conversationId);
        _log.info('成功删除会话及其缓存');
      } else {
        _log.info(response.body);
        final error = json.decode(response.body)['message'];
        throw Exception(error);
      }
    } catch (e, stack) {
      _log.severe('删除会话时出错: $e');
      _log.fine('错误堆栈: $stack');
      rethrow;
    }
  }

  Future<String> renameConversation(String conversationId, String name,
      {bool autoGenerate = false}) async {
    _log.info('开始重命名会话');
    _log.info('会话ID: $conversationId');
    _log.info('新名称: ${name.isEmpty ? "(空)" : name}');
    _log.info('自动生成: $autoGenerate');

    final settings = await ApiConfig.currentSettings;
    final baseUrl = settings['baseUrl'];
    final defaultUserId = settings['defaultUserId'];
    final headers = await ApiConfig.headers;

    final requestBody = {
      'name': name.isEmpty ? '' : name,
      'user': defaultUserId,
      'auto_generate': autoGenerate,
    };
    _log.info('请求体: $requestBody');

    final response = await _client.post(
      Uri.parse('$baseUrl${ApiConfig.conversations}/$conversationId${ApiConfig.conversationRename}'),
      headers: headers,
      body: jsonEncode(requestBody),
    );

    _log.fine('响应体: ${response.body}');

    if (response.statusCode != 200) {
      final error = '重命名会话失败: ${response.statusCode}\n${response.body}';
      _log.severe(error);
      throw Exception(error);
    }

    _log.info('重命名会话成功');
    return json.decode(response.body)['name'];
  }
}
