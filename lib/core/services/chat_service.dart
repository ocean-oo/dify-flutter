import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../config/api_config.dart';
import '../../features/chat/models/conversation.dart';
import '../../features/chat/models/message_history.dart';
import '../../features/chat/models/stream_response.dart';

class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? messageId;
  final String? conversationId;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.messageId,
    this.conversationId,
    this.isStreaming = false,
    this.metadata,
  });

  ChatMessage copyWith({
    String? content,
    bool? isUser,
    DateTime? timestamp,
    String? messageId,
    String? conversationId,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
    );
  }

  factory ChatMessage.fromMessageHistory(MessageHistory history, bool isUser) {
    return ChatMessage(
      content: isUser ? history.query : history.answer,
      isUser: isUser,
      timestamp: history.createdAt,
      messageId: history.id,
      conversationId: history.conversationId,
    );
  }
}

class ChatService {
  static final _log = Logger('ChatService');
  final _client = http.Client();
  String? _currentConversationId;
  final StreamController<ChatMessage> messageStreamController =
      StreamController<ChatMessage>();

  // 获取历史消息
  Future<List<ChatMessage>> getMessageHistory(String conversationId) async {
    _log.info('开始获取历史消息');
    _log.info('会话ID: $conversationId');

    try {
      final queryParams = {
        'user': ApiConfig.defaultUserId,
        'conversation_id': conversationId,
      };

      _log.info('查询参数: $queryParams');
      final uri = Uri.parse(ApiConfig.baseUrl + ApiConfig.messages)
          .replace(queryParameters: queryParams);
      _log.info('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: ApiConfig.headers,
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

        _log.info('处理后的消息数量: ${messages.length}');
        return messages;
      } else {
        final error = '获取历史消息失败: ${response.statusCode}\n${response.body}';
        _log.severe(error);
        throw Exception(error);
      }
    } catch (e, stack) {
      _log.severe('获取历史消息时出错: $e');
      _log.fine('错误堆栈: $stack');
      throw Exception('获取历史消息失败: $e');
    }
  }

  // 获取会话列表
  Future<List<Conversation>> getConversations({int limit = 20}) async {
    _log.info('开始获取会话列表');
    _log.info('限制数量: $limit');

    try {
      final queryParams = {
        'user': ApiConfig.defaultUserId,
        'limit': limit.toString(),
      };

      _log.info('查询参数: $queryParams');
      final uri = Uri.parse('${ApiConfig.baseUrl}/conversations')
          .replace(queryParameters: queryParams);
      _log.info('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: ApiConfig.headers,
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

  Future<ChatMessage> sendMessage(String message) async {
    _log.info('发送消息');
    _log.info('消息内容: $message');
    _log.info('当前会话ID: $_currentConversationId');

    final request = http.Request(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/chat-messages'),
    );

    try {
      request.headers.addAll({
        ...ApiConfig.headers,
        'Accept': 'text/event-stream',
      });

      request.body = json.encode({
        'inputs': {},
        'query': message,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
        'user': ApiConfig.defaultUserId,
      });

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
                    createdAt ?? DateTime.now().millisecondsSinceEpoch),
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
            createdAt ?? DateTime.now().millisecondsSinceEpoch),
        messageId: currentMessageId,
        conversationId: currentConversationId,
        isStreaming: false,
      );
      messageStreamController.add(finalMessage);

      // 返回空消息，避免触发新的消息添加
      return ChatMessage(
        content: '',
        isUser: false,
        timestamp: DateTime.now(),
      );
    } catch (e, stack) {
      _log.severe('发送消息时出错: $e');
      _log.fine('堆栈: $stack');
      rethrow;
    }
  }

  Future<void> deleteConversation(String? conversationId) async {
    if (conversationId == null) return;

    final response = await _client.delete(
      Uri.parse('${ApiConfig.baseUrl}/conversations/$conversationId'),
      headers: {
        ...ApiConfig.headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'user': ApiConfig.defaultUserId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('删除会话失败: ${response.statusCode}');
    }
  }

  Future<String> renameConversation(String? conversationId, String name,
      {bool autoGenerate = false}) async {
    if (conversationId == null) {
      throw Exception('会话ID不能为空');
    }

    _log.info('开始重命名会话');
    _log.info('会话ID: $conversationId');
    _log.info('新名称: ${name.isEmpty ? "(空)" : name}');
    _log.info('自动生成: $autoGenerate');

    final requestBody = {
      'name': name.isEmpty ? '' : name,
      'user': ApiConfig.defaultUserId,
      'auto_generate': autoGenerate,
    };
    _log.info('请求体: $requestBody');

    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/conversations/$conversationId/name'),
      headers: {
        ...ApiConfig.headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    _log.info('响应状态码: ${response.statusCode}');
    _log.fine('响应体: ${response.body}');

    if (response.statusCode != 200) {
      final error = '重命名会话失败: ${response.statusCode}\n${response.body}';
      _log.severe(error);
      throw Exception(error);
    }

    _log.info('重命名会话成功');
    return json.decode(response.body)['name'];
  }

  String? get currentConversationId => _currentConversationId;

  void resetConversation() {
    _currentConversationId = null;
  }

  void setConversationId(String? id) {
    _currentConversationId = id;
  }
}
