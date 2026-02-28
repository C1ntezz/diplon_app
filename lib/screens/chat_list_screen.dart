import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_store.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChatStore>();
    final api = context.read<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => store.loadConversations(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              context.read<SocketService>().disconnect();
              await api.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Перезапусти приложение')))),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: store.conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = store.conversations[i];
          final other = c.participants.firstWhere(
            (p) => p.id != api.userId,
            orElse: () => c.participants.isNotEmpty ? c.participants.first : throw StateError('No users'),
          );

          final title = c.type == 'group' ? (c.name ?? 'Group') : other.title;
          final isOnline = store.onlineUsers.contains(other.id);

          return ListTile(
            title: Text(title),
            trailing: isOnline ? const Icon(Icons.circle, size: 10, color: Colors.green) : null,
            onTap: () async {
              await store.openConversation(c.id);
              if (!context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(title: title)));
            },
          );
        },
      ),
    );
  }
}
