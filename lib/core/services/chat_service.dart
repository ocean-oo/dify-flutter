import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../../features/chat/models/conversation.dart';
import '../../features/chat/models/message_history.dart';
import '../../features/chat/models/stream_response.dart';
import '../../features/chat/models/uploaded_file.dart';

class ChatMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? messageId;
  final String? conversationId;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;
  final List<UploadedFile>? files;

  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.messageId,
    this.conversationId,
    this.isStreaming = false,
    this.metadata,
    this.files,
  });

  ChatMessage copyWith({
    String? content,
    bool? isUser,
    DateTime? timestamp,
    String? messageId,
    String? conversationId,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
    List<UploadedFile>? files,
  }) {
    return ChatMessage(
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
      files: files ?? this.files,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'messageId': messageId,
      'conversationId': conversationId,
      'isStreaming': isStreaming,
      'metadata': metadata,
      'files': files?.map((f) => f.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      content: json['content'],
      isUser: json['isUser'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      messageId: json['messageId'],
      conversationId: json['conversationId'],
      isStreaming: json['isStreaming'] ?? false,
      metadata: json['metadata'],
      files: (json['files'] as List<dynamic>?)
          ?.map((f) => UploadedFile(
                id: f['upload_file_id'],
                mimeType: f['mime_type'],
                name: f['name'] ?? '',
                size: f['size'] ?? 0,
                extension: f['extension'] ?? '',
                createdAt: f['created_at'],
                createdBy: f['created_by'],
              ))
          .toList(),
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

  String? get currentConversationId => _currentConversationId;

  void setConversationId(String? id) {
    _currentConversationId = id;
  }

  // 缓存消息
  Future<void> _cacheMessages(
      String conversationId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    final messagesJson = messages.map((m) => m.toJson()).toList();
    await prefs.setString(key, jsonEncode(messagesJson));
    _log.info('已缓存会话 $conversationId 的 ${messages.length} 条消息');
  }

  // 获取缓存的消息
  Future<List<ChatMessage>> _getCachedMessages(String conversationId) async {
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

  // 添加新消息到缓存
  Future<void> _addMessageToCache(
      String conversationId, ChatMessage message) async {
    final cachedMessages = await _getCachedMessages(conversationId);
    cachedMessages.add(message);
    await _cacheMessages(conversationId, cachedMessages);
  }

  // 删除会话的缓存消息
  Future<void> clearConversationCache(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'chat_messages_$conversationId';
    await prefs.remove(key);
    _log.info('已清除会话 $conversationId 的缓存消息');
  }

  Future<List<ChatMessage>> getMessageHistory(String conversationId) async {
    _log.info('获取会话消息历史: $conversationId');

    try {
      // 先尝试从缓存获取消息
      final cachedMessages = await _getCachedMessages(conversationId);
      if (cachedMessages.isNotEmpty) {
        _log.info('使用缓存的消息');
        return cachedMessages;
      }

      // 如果缓存为空，则从服务器获取
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

        // 缓存获取到的消息
        await _cacheMessages(conversationId, messages);

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

  Future<ChatMessage> sendMessage(String message,
      {List<UploadedFile>? files}) async {
    _log.info('发送消息');
    _log.info('消息内容: $message');
    _log.info('当前会话ID: $_currentConversationId');
    if (files != null && files.isNotEmpty) {
      _log.info('附带文件数量: ${files.length}');
    }

    // 先新建用户消息
    final userMessage = ChatMessage(
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
      conversationId: _currentConversationId,
      files: files,
    );

    final request = http.Request(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/chat-messages'),
    );

    try {
      request.headers.addAll({
        ...ApiConfig.headers,
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
      });

      final Map<String, dynamic> body = {
        'inputs': {},
        'query': message,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
        'user': ApiConfig.defaultUserId,
      };

      if (files != null && files.isNotEmpty) {
        body['files'] = files.map((f) => f.toJson()).toList();
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
        await _addMessageToCache(currentConversationId, userMessage);
        await _addMessageToCache(currentConversationId, finalMessage);
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

    try {
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

      if (response.statusCode == 200) {
        // 同时删除缓存
        await clearConversationCache(conversationId);
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
}
