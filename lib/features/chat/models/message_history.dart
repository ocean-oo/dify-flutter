class MessageHistory {
  final String id;
  final String conversationId;
  final Map<String, dynamic>? inputs;
  final String query;
  final String answer;
  final List<dynamic> messageFiles;
  final dynamic feedback;
  final List<dynamic> retrieverResources;
  final DateTime createdAt;

  MessageHistory({
    required this.id,
    required this.conversationId,
    this.inputs,
    required this.query,
    required this.answer,
    required this.messageFiles,
    this.feedback,
    required this.retrieverResources,
    required this.createdAt,
  });

  factory MessageHistory.fromJson(Map<String, dynamic> json) {
    return MessageHistory(
      id: json['id'],
      conversationId: json['conversation_id'],
      inputs: json['inputs'],
      query: json['query'],
      answer: json['answer'],
      messageFiles: json['message_files'] ?? [],
      feedback: json['feedback'],
      retrieverResources: json['retriever_resources'] ?? [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000),
    );
  }
}
