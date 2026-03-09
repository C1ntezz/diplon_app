import 'user.dart';

class ChatMessage {
  final String id;
  final String conversationId;
  final dynamic sender; // object or id
  final String? content;
  final String? senderContent; // То что зашифровано для меня самого
  final String? encryptedPayload;
  final String type; // text/image/voice/file/sticker
  final String? mediaUrl;
  final String status; // sent/delivered/read
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
        timestamp: DateTime.tryParse((j['timestamp'] ?? '').toString()) ?? DateTime.now(),
      );

  AppUser? senderAsUser() {
    if (sender is Map<String, dynamic>) return AppUser.fromJson(sender as Map<String, dynamic>);
    return null;
  }

  String senderId() {
    if (sender is Map<String, dynamic>) return ((sender as Map<String, dynamic>)['_id'] ?? '').toString();
    return (sender ?? '').toString();
  }

  ChatMessage copyWith({
    String? content,
    String? senderContent,
    String? encryptedPayload,
    String? status,
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
      timestamp: timestamp,
    );
  }
}
