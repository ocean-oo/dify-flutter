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

  // 流式发送消息
  Stream<ChatMessage> sendMessageStream(String message) async* {
    try {
      print('=== 开始发送流式消息 ===');
      final request = http.Request(
        'POST',
        Uri.parse(ApiConfig.baseUrl + ApiConfig.chatMessages),
      );

      request.headers.addAll({
        ...ApiConfig.headers,
        'Accept': 'text/event-stream',
      });

      final body = {
        'inputs': {},
        'query': message,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
        'user': ApiConfig.defaultUserId,
      };
      request.body = json.encode(body);
      
      print('请求URL: ${request.url}');
      print('请求头: ${request.headers}');
      print('请求体: ${request.body}');

      final response = await _client.send(request);
      print('响应状态码: ${response.statusCode}');
      print('响应头: ${response.headers}');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.transform(utf8.decoder).join();
        print('错误响应体: $errorBody');
        throw Exception('Failed to send message: ${response.statusCode}\n$errorBody');
      }

      String currentAnswer = '';
      String? currentMessageId;
      String? currentConversationId;
      Map<String, dynamic>? metadata;
      
      // 用于存储不完整的数据行
      String pendingLine = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        print('收到数据块: $chunk');
        
        // 将之前未完成的行与新数据块合并
        String processData = pendingLine + chunk;
        pendingLine = '';
        
        final lines = processData.split('\n');
        
        // 如果最后一行不是空行，可能是不完整的，保存到pendingLine
        if (!lines.last.trim().isEmpty) {
          pendingLine = lines.last;
          lines.removeLast();
        }

        for (var line in lines) {
          if (line.trim().isEmpty) {
            print('跳过空行');
            continue;
          }
          if (!line.startsWith('data: ')) {
            print('跳过非data行: $line');
            continue;
          }

          try {
            final jsonStr = line.substring(6);
            print('解析JSON字符串: $jsonStr');
            
            // 验证JSON是否完整
            try {
              final json = jsonDecode(jsonStr);
              print('解析后的JSON: $json');
              
              final streamResponse = StreamResponse.fromJson(json);
              print('事件类型: ${streamResponse.event}');

              if (streamResponse.isMessage) {
                final answer = streamResponse.answer ?? '';
                print('收到消息片段: $answer');
                currentAnswer += answer;
                currentMessageId = streamResponse.messageId;
                currentConversationId = streamResponse.conversationId;
                _currentConversationId = currentConversationId;

                yield ChatMessage(
                  content: currentAnswer,
                  isUser: false,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                      (streamResponse.createdAt ?? 0) * 1000),
                  messageId: currentMessageId,
                  conversationId: currentConversationId,
                  isStreaming: true,
                );
              } else if (streamResponse.isMessageEnd) {
                metadata = streamResponse.data;
                print('消息结束，元数据: $metadata');
                yield ChatMessage(
                  content: currentAnswer,
                  isUser: false,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                      (streamResponse.createdAt ?? 0) * 1000),
                  messageId: currentMessageId,
                  conversationId: currentConversationId,
                  isStreaming: false,
                  metadata: metadata,
                );
              }
            } catch (e) {
              print('JSON解析失败，可能是不完整的数据: $e');
              pendingLine = line;
              continue;
            }
          } catch (e, stack) {
            print('处理消息时出错:');
            print('错误: $e');
            print('堆栈: $stack');
            print('问题数据行: $line');
            continue;  // 继续处理下一行，而不是中断整个流
          }
        }
      }
    } catch (e, stack) {
      print('发送消息时出错:');
      print('错误: $e');
      print('堆栈: $stack');
      throw Exception('Error sending message: $e');
    }
  }

  Future<ChatMessage> sendMessage(String message) async {
    try {
      print('=== 开始发送消息 ===');
      print('消息内容: $message');
      print('当前会话ID: $_currentConversationId');

      final request = http.Request(
        'POST',
        Uri.parse(ApiConfig.baseUrl + ApiConfig.chatMessages),
      );

      // 打印请求 URL
      print('请求URL: ${request.url}');

      final headers = {
        ...ApiConfig.headers,
        'Accept': 'text/event-stream',
      };
      request.headers.addAll(headers);
      
      // 打印请求头
      print('请求头:');
      headers.forEach((key, value) => print('  $key: $value'));

      final body = {
        'inputs': {},
        'query': message,
        'response_mode': 'streaming',
        'conversation_id': _currentConversationId ?? '',
        'user': ApiConfig.defaultUserId,
      };
      request.body = json.encode(body);
      
      // 打印请求体
      print('请求体: ${request.body}');

      print('=== 发送请求 ===');
      final streamedResponse = await _client.send(request);
      print('响应状态码: ${streamedResponse.statusCode}');
      print('响应头:');
      streamedResponse.headers.forEach((key, value) => print('  $key: $value'));

      if (streamedResponse.statusCode != 200) {
        // 读取错误响应
        final errorBody = await streamedResponse.stream.transform(utf8.decoder).join();
        print('错误响应内容: $errorBody');
        throw Exception('发送消息失败: ${streamedResponse.statusCode}\n响应内容: $errorBody');
      }

      String currentAnswer = '';
      String? currentMessageId;
      String? currentConversationId;
      int? createdAt;

      print('=== 开始处理响应流 ===');
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        print('接收到数据块: $chunk');
        
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.trim().isEmpty) {
            print('跳过空行');
            continue;
          }
          if (!line.startsWith('data: ')) {
            print('跳过非data行: $line');
            continue;
          }

          try {
            final jsonStr = line.substring(6);
            print('解析JSON: $jsonStr');
            
            final json = jsonDecode(jsonStr);
            print('解析后的JSON: $json');
            
            final streamResponse = StreamResponse.fromJson(json);
            print('事件类型: ${streamResponse.event}');

            if (streamResponse.isMessage) {
              final answer = streamResponse.answer ?? '';
              print('收到消息片段: $answer');
              currentAnswer += answer;
              currentMessageId = streamResponse.messageId;
              currentConversationId = streamResponse.conversationId;
              createdAt = streamResponse.createdAt;
              _currentConversationId = currentConversationId;
              
              print('当前累积答案: $currentAnswer');
              print('消息ID: $currentMessageId');
              print('会话ID: $currentConversationId');
            } else {
              print('跳过非消息事件');
            }
          } catch (e, stack) {
            print('处理消息时出错:');
            print('错误: $e');
            print('堆栈: $stack');
            print('问题数据: $line');
          }
        }
      }

      print('=== 消息处理完成 ===');
      print('最终答案: $currentAnswer');
      print('最终消息ID: $currentMessageId');
      print('最终会话ID: $currentConversationId');

      return ChatMessage(
        content: currentAnswer,
        isUser: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch((createdAt ?? 0) * 1000),
        messageId: currentMessageId,
        conversationId: currentConversationId,
      );
    } catch (e, stack) {
      print('=== 发生错误 ===');
      print('错误: $e');
      print('堆栈: $stack');
      throw Exception('发送消息时出错: $e');
    }
  }

  Future<void> deleteConversation(String conversationId) async {
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

  Future<void> renameConversation(String conversationId, String name) async {
    final response = await _client.post(
      Uri.parse(ApiConfig.baseUrl + '/conversations/$conversationId/name'),
      headers: {
        ...ApiConfig.headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'user': ApiConfig.defaultUserId,
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('重命名会话失败: ${response.statusCode}');
    }
  }

  String? get currentConversationId => _currentConversationId;

  void resetConversation() {
    _currentConversationId = null;
  }

  void setConversationId(String id) {
    _currentConversationId = id;
  }
}
