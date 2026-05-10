import 'user.dart';

class ChatMessage {
  final String id;
  final String conversationId;
  final dynamic sender; // object or id
  final String? content;
  final String? senderContent; // То что зашифровано для меня самого
  final String? encryptedPayload;
  final String type; // text/image/gif/voice/file/sticker
  final String? mediaUrl;
  final String status; // sent/delivered/read
  final List<String> readBy;
  final ChatMessage? replyTo;
  final DateTime? deletedAt;
  final String? deletedBy;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    this.senderContent,
    required this.encryptedPayload,
    required this.type,
    required this.mediaUrl,
    required this.status,
    this.readBy = const [],
    this.replyTo,
    this.deletedAt,
    this.deletedBy,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['_id'] ?? '').toString(),
        conversationId: (j['conversationId'] ?? '').toString(),
        sender: j['sender'],
        content: j['content']?.toString(),
        senderContent: j['senderContent']?.toString(),
        encryptedPayload: j['content']?.toString(),
        type: (j['type'] ?? 'text').toString(),
        mediaUrl: j['mediaUrl']?.toString(),
        status: (j['status'] ?? 'sent').toString(),
        readBy: (j['readBy'] as List? ?? []).map(_userIdFromJson).toList(),
        replyTo: j['replyTo'] is Map<String, dynamic>
            ? ChatMessage.fromJson(j['replyTo'] as Map<String, dynamic>)
            : null,
        deletedAt: j['deletedAt'] != null ? DateTime.tryParse(j['deletedAt'].toString()) : null,
        deletedBy: _userIdFromJson(j['deletedBy']),
        timestamp: DateTime.tryParse((j['timestamp'] ?? '').toString()) ?? DateTime.now(),
      );

  static String _userIdFromJson(dynamic value) {
    if (value is Map<String, dynamic>) return (value['_id'] ?? '').toString();
    return value?.toString() ?? '';
  }

  AppUser? senderAsUser() {
    if (sender is Map<String, dynamic>) return AppUser.fromJson(sender as Map<String, dynamic>);
    return null;
  }

  String senderId() {
    if (sender is Map<String, dynamic>) return ((sender as Map<String, dynamic>)['_id'] ?? '').toString();
    return (sender ?? '').toString();
  }

  bool get isDeleted => deletedAt != null;

  ChatMessage copyWith({
    String? content,
    String? senderContent,
    String? encryptedPayload,
    String? status,
    List<String>? readBy,
    ChatMessage? replyTo,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      sender: sender,
      content: content ?? this.content,
      senderContent: senderContent ?? this.senderContent,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      type: type,
      mediaUrl: mediaUrl,
      status: status ?? this.status,
      readBy: readBy ?? this.readBy,
      replyTo: replyTo ?? this.replyTo,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      timestamp: timestamp,
    );
  }
}
