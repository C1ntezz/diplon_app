import 'user.dart';
import 'message.dart';

class GroupRole {
  final AppUser user;
  final String role; // admin/member

  GroupRole({
    required this.user,
    required this.role,
  });

  factory GroupRole.fromJson(Map<String, dynamic> j) {
    final rawUser = j['user'];
    return GroupRole(
      user: rawUser is Map<String, dynamic>
          ? AppUser.fromJson(rawUser)
          : AppUser(id: rawUser?.toString() ?? '', username: ''),
      role: (j['role'] ?? 'member').toString(),
    );
  }
}

class Conversation {
  final String id;
  final String type; // direct/group
  final String? name;
  final List<AppUser> participants;
  final List<GroupRole> roles;
  
  // Добавлено для отображения последнего сообщения в списке чатов
  ChatMessage? lastMessage;
  DateTime? updatedAt;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.participants,
    this.roles = const [],
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
        roles: (j['roles'] as List? ?? [])
            .map((x) => GroupRole.fromJson(x as Map<String, dynamic>))
            .toList(),
        lastMessage: j['lastMessage'] != null ? ChatMessage.fromJson(j['lastMessage']) : null,
        updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'].toString()) : null,
        unreadCount: j['unreadCount'] ?? 0,
      );

  bool isAdmin(String? userId) {
    if (userId == null || type != 'group') return false;
    return roles.any((entry) => entry.user.id == userId && entry.role == 'admin');
  }

  String roleOf(String userId) {
    return roles
        .firstWhere(
          (entry) => entry.user.id == userId,
          orElse: () => GroupRole(user: AppUser(id: userId, username: ''), role: 'member'),
        )
        .role;
  }
}
