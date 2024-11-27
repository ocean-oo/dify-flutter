class StreamResponse {
  final String event;
  final Map<String, dynamic> data;
  final String? messageId;
  final String? conversationId;
  final String? answer;
  final int? createdAt;

  StreamResponse({
    required this.event,
    required this.data,
    this.messageId,
    this.conversationId,
    this.answer,
    this.createdAt,
  });

  factory StreamResponse.fromJson(Map<String, dynamic> json) {
    return StreamResponse(
      event: json['event'],
      messageId: json['message_id'],
      conversationId: json['conversation_id'],
      answer: json['answer'],
      createdAt: json['created_at'],
      data: json['data'] ?? {},
    );
  }

  bool get isMessage => event == 'message';
  bool get isMessageEnd => event == 'message_end';
  bool get isWorkflowStarted => event == 'workflow_started';
  bool get isWorkflowFinished => event == 'workflow_finished';
  bool get isTtsMessage => event == 'tts_message';
  bool get isTtsMessageEnd => event == 'tts_message_end';
}
