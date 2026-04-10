import 'user.dart';
import 'message.dart';

class Conversation {
  final String id;
  final String type; // direct/group
  final String? name;
  final List<AppUser> participants;
  
  // Добавлено для отображения последнего сообщения в списке чатов
  ChatMessage? lastMessage;
  DateTime? updatedAt;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.participants,
    this.lastMessage,
    this.updatedAt,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: (j['_id'] ?? '').toString(),
        type: (j['type'] ?? 'direct').toString(),
        name: j['name']?.toString(),
        participants: (j['participants'] as List? ?? [])
            .map((x) => AppUser.fromJson(x as Map<String, dynamic>))
            .toList(),
        lastMessage: j['lastMessage'] != null ? ChatMessage.fromJson(j['lastMessage']) : null,
        updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'].toString()) : null,
        unreadCount: j['unreadCount'] ?? 0,
      );
}
