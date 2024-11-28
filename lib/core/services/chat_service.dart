import 'dart:convert';
import 'package:http/http.dart' as http;
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
  final http.Client _client = http.Client();
  String? _currentConversationId;

  // 获取历史消息
  Future<List<ChatMessage>> getMessageHistory(String conversationId) async {
    print('=== 开始获取历史消息 ===');
    print('会话ID: $conversationId');

    try {
      final queryParams = {
        'user': ApiConfig.defaultUserId,
        'conversation_id': conversationId,
      };

      print('查询参数: $queryParams');
      final uri = Uri.parse(ApiConfig.baseUrl + ApiConfig.messages)
          .replace(queryParameters: queryParams);
      print('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: ApiConfig.headers,
      );

      print('响应状态码: ${response.statusCode}');
      print('响应头: ${response.headers}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('响应数据: $data');

        final List<dynamic> messagesJson = data['data'];
        print('消息数量: ${messagesJson.length}');

        final messages = messagesJson
            .map((json) => MessageHistory.fromJson(json))
            .expand((history) => [
                  ChatMessage.fromMessageHistory(history, true),
                  ChatMessage.fromMessageHistory(history, false),
                ])
            .toList();

        // 按时间排序
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        print('处理后的消息数量: ${messages.length}');
        return messages;
      } else {
        final error = '获取历史消息失败: ${response.statusCode}\n${response.body}';
        print(error);
        throw Exception(error);
      }
    } catch (e, stack) {
      print('获取历史消息时出错: $e');
      print('错误堆栈: $stack');
      throw Exception('获取历史消息失败: $e');
    }
  }

  // 获取会话列表
  Future<List<Conversation>> getConversations({int limit = 20}) async {
    print('=== 开始获取会话列表 ===');
    print('限制数量: $limit');

    try {
      final queryParams = {
        'user': ApiConfig.defaultUserId,
        'limit': limit.toString(),
      };

      print('查询参数: $queryParams');
      final uri = Uri.parse(ApiConfig.baseUrl + '/conversations')
          .replace(queryParameters: queryParams);
      print('请求URL: $uri');

      final response = await _client.get(
        uri,
        headers: ApiConfig.headers,
      );

      print('响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> conversationsJson = data['data'];
        print('会话数量: ${conversationsJson.length}');

        // 打印每个会话的时间戳
        for (var json in conversationsJson) {
          print('会话ID: ${json['id']}');
          print('创建时间戳: ${json['created_at']}');
          print('更新时间戳: ${json['updated_at']}');
          final createdTimestamp = DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] * 1000,
            isUtc: true,
          ).toLocal();
          final updatedTimestamp = DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] * 1000,
            isUtc: true,
          ).toLocal();
          print('创建时间: $createdTimestamp');
          print('最后更新时间: $updatedTimestamp');
          print('---');
        }

        return conversationsJson
            .map((json) => Conversation.fromJson(json))
            .toList();
      } else {
        print('获取会话列表失败: ${response.statusCode}');
        print('错误响应: ${response.body}');
        throw Exception('获取会话列表失败: ${response.statusCode}');
      }
    } catch (e, stack) {
      print('获取会话列表出错: $e');
      print('堆栈: $stack');
      throw Exception('获取会话列表出错: $e');
    }
  }

  Future<ChatMessage> sendMessage(String message) async {
    print('=== 发送消息 ===');
    print('消息内容: $message');
    print('当前会话ID: $_currentConversationId');

    final request = http.Request(
      'POST',
      Uri.parse(ApiConfig.baseUrl + '/chat-messages'),
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
      print('响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.transform(utf8.decoder).join();
        throw Exception('发送消息失败: ${response.statusCode}\n$errorBody');
      }

      String currentAnswer = '';
      String? currentMessageId;
      String? currentConversationId;
      int? createdAt;
      String pendingData = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pendingData += chunk;

        while (true) {
          // 查找下一个完整的数据行
          final lineEnd = pendingData.indexOf('\n');
          if (lineEnd == -1) break; // 没有完整的行

          // 提取一行数据
          final line = pendingData.substring(0, lineEnd).trim();
          pendingData = pendingData.substring(lineEnd + 1);

          if (line.isEmpty || !line.startsWith('data: ')) continue;

          try {
            final jsonStr = line.substring(6); // 移除 'data: ' 前缀
            final json = jsonDecode(jsonStr);
            final streamResponse = StreamResponse.fromJson(json);

            if (streamResponse.isMessage && streamResponse.answer != null) {
              currentAnswer += streamResponse.answer!;
              currentMessageId = streamResponse.messageId;
              currentConversationId = streamResponse.conversationId;
              createdAt = streamResponse.createdAt;
              _currentConversationId = currentConversationId;
            }
          } catch (e) {
            print('解析消息时出错: $e');
            // 继续处理下一行
          }
        }
      }

      // 处理最后可能剩余的数据
      if (pendingData.isNotEmpty && pendingData.startsWith('data: ')) {
        try {
          final jsonStr = pendingData.substring(6);
          final json = jsonDecode(jsonStr);
          final streamResponse = StreamResponse.fromJson(json);

          if (streamResponse.isMessage && streamResponse.answer != null) {
            currentAnswer += streamResponse.answer!;
            currentMessageId = streamResponse.messageId;
            currentConversationId = streamResponse.conversationId;
            createdAt = streamResponse.createdAt;
            _currentConversationId = currentConversationId;
          }
        } catch (e) {
          print('处理剩余数据时出错: $e');
        }
      }

      return ChatMessage(
        content: currentAnswer,
        isUser: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch((createdAt ?? 0) * 1000),
        messageId: currentMessageId,
        conversationId: currentConversationId,
      );
    } catch (e, stack) {
      print('发送消息时出错: $e');
      print('堆栈: $stack');
      rethrow;
    }
  }

  Future<void> deleteConversation(String? conversationId) async {
    if (conversationId == null) return;

    final response = await _client.delete(
      Uri.parse(ApiConfig.baseUrl + '/conversations/$conversationId'),
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
    if (conversationId == null) return "";

    print('=== 开始重命名会话 ===');
    print('会话ID: $conversationId');
    print('新名称: ${name.isEmpty ? "(空)" : name}');
    print('自动生成: $autoGenerate');

    final requestBody = {
      'name': name.isEmpty ? '' : name,
      'user': ApiConfig.defaultUserId,
      'auto_generate': autoGenerate,
    };
    print('请求体: $requestBody');

    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/conversations/$conversationId/name'),
      headers: {
        ...ApiConfig.headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    print('响应状态码: ${response.statusCode}');
    print('响应体: ${response.body}');

    if (response.statusCode != 200) {
      final error = '重命名会话失败: ${response.statusCode}\n${response.body}';
      print(error);
      throw Exception(error);
    }

    print('重命名会话成功');
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
