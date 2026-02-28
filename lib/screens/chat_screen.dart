import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_store.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  const ChatScreen({super.key, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.pixels <= 0) {
        context.read<ChatStore>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChatStore>();
    final api = context.read<ApiService>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            if (store.typingText != null)
              Text(store.typingText!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: store.messages.length + (store.loadingMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (store.loadingMore && i == 0) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final msg = store.messages[store.loadingMore ? i - 1 : i];
                final isOwn = msg.senderId() == api.userId;

                final bubbleColor = isOwn ? Colors.blue : const Color(0xFFE9ECEF);
                final textColor = isOwn ? Colors.white : Colors.black;

                final status = isOwn
                    ? (msg.status == 'read' ? '✓✓' : msg.status == 'delivered' ? '✓✓' : '✓')
                    : '';

                return Align(
                  alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.senderAsUser()?.title ?? (isOwn ? (api.displayName ?? '@') : 'User'),
                          style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.85), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if ((msg.content ?? '').isNotEmpty)
                          Text(msg.content!, style: TextStyle(color: textColor)),
                        if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('📎 ', style: TextStyle(color: textColor, decoration: TextDecoration.underline)),
                        ],
                        if (isOwn)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              status,
                              style: TextStyle(color: msg.status == 'read' ? Colors.lightBlueAccent : textColor.withOpacity(0.9)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Файлы добавлю следующим шагом (через file_picker + /api/upload).')),
                      );
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      onChanged: (_) => store.emitTyping(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = input.text.trim();
                      if (text.isEmpty) return;
                      store.sendText(text);
                      input.clear();
                      FocusScope.of(context).unfocus();
                    },
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
