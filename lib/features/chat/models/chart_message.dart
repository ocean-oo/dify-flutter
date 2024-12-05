import './uploaded_file.dart';
import './message_history.dart';

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
          ?.map((f) => UploadedFile.fromJson(f))
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