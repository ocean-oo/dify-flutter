class Conversation {
  final String id;
  final String name;
  final Map<String, dynamic>? inputs;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.name,
    this.inputs,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // API返回的是秒级时间戳，需要转换为毫秒
    final createdTimestamp = DateTime.fromMillisecondsSinceEpoch(
      json['created_at'] * 1000,
      isUtc: true,
    ).toLocal();

    final updatedTimestamp = DateTime.fromMillisecondsSinceEpoch(
      json['updated_at'] * 1000,
      isUtc: true,
    ).toLocal();

    return Conversation(
      id: json['id'],
      name: json['name'],
      inputs: json['inputs'],
      status: json['status'],
      createdAt: createdTimestamp,
      updatedAt: updatedTimestamp,
    );
  }
}
