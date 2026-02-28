import 'user.dart';

class Conversation {
  final String id;
  final String type; // direct/group
  final String? name;
  final List<AppUser> participants;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.participants,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: (j['_id'] ?? '').toString(),
        type: (j['type'] ?? 'direct').toString(),
        name: j['name']?.toString(),
        participants: (j['participants'] as List? ?? [])
            .map((x) => AppUser.fromJson(x as Map<String, dynamic>))
            .toList(),
      );
}
