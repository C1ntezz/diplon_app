import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../services/chat_store.dart';
import '../services/api_service.dart';
import 'group_settings_screen.dart';

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

  String _messagePreview(ChatMessage msg) {
    if (msg.isDeleted) return 'Сообщение удалено';
    final content = msg.content?.trim();
    if (content != null && content.isNotEmpty) return content;
    if (msg.type == 'image') return 'Изображение';
    if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) return 'Файл';
    return 'Сообщение';
  }

  void _sendCurrentText(ChatStore store) {
    final text = input.text.trim();
    if (text.isEmpty) return;
    store.sendText(text);
    input.clear();
    FocusScope.of(context).unfocus();
  }

  void _showMessageActions(ChatMessage msg, bool canDelete) {
    if (msg.isDeleted || msg.type == 'system') return;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Ответить'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.read<ChatStore>().startReply(msg);
              },
            ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await context.read<ChatStore>().deleteMessage(msg);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка удаления: $e')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBlock(ChatMessage reply, bool isOwn) {
    final color = isOwn ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.06);
    final lineColor = isOwn ? Colors.white70 : Theme.of(context).primaryColor;
    final textColor = isOwn ? Colors.white70 : Colors.black54;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: color,
        border: Border(left: BorderSide(color: lineColor, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderAsUser()?.title ?? 'Сообщение',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _messagePreview(reply),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChatStore>();
    final api = context.read<ApiService>();
    final activeConversation = store.activeConversation;
    final title = activeConversation?.type == 'group'
        ? (activeConversation?.name ?? widget.title)
        : widget.title;

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
            Text(title),
            if (store.typingText != null)
              Text(store.typingText!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          if (activeConversation?.type == 'group')
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'Настройки группы',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(conversationId: activeConversation!.id),
                  ),
                );
              },
            ),
        ],
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
                if (msg.type == 'system') {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        msg.content ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  );
                }

                final isOwn = msg.senderId() == api.userId;
                final canDelete = activeConversation?.type == 'group'
                    ? (activeConversation?.isAdmin(api.userId) ?? false)
                    : isOwn;

                final bubbleColor = isOwn ? Colors.blue : const Color(0xFFE9ECEF);
                final textColor = msg.isDeleted
                    ? Colors.grey.shade600
                    : (isOwn ? Colors.white : Colors.black);

                final status = isOwn
                    ? (msg.status == 'read' ? '✓✓' : msg.status == 'delivered' ? '✓✓' : '✓')
                    : '';

                return GestureDetector(
                  onLongPress: () => _showMessageActions(msg, canDelete),
                  child: Align(
                    alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: msg.isDeleted ? Colors.grey.shade200 : bubbleColor,
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
                          if (msg.replyTo != null && !msg.isDeleted)
                            _buildReplyBlock(msg.replyTo!, isOwn),
                          if (msg.isDeleted)
                            Text(
                              'Сообщение удалено',
                              style: TextStyle(color: textColor, fontStyle: FontStyle.italic),
                            )
                          else if ((msg.content ?? '').isNotEmpty)
                            Text(msg.content!, style: TextStyle(color: textColor)),
                          if (!msg.isDeleted && msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('📎 ', style: TextStyle(color: textColor, decoration: TextDecoration.underline)),
                          ],
                          if (isOwn && !msg.isDeleted)
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
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (store.replyingTo != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(left: BorderSide(color: Theme.of(context).primaryColor, width: 3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ответ на ${store.replyingTo!.senderAsUser()?.title ?? 'сообщение'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _messagePreview(store.replyingTo!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'Отменить ответ',
                            onPressed: store.cancelReply,
                          ),
                        ],
                      ),
                    ),
                  Row(
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
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendCurrentText(store),
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _sendCurrentText(store),
                        child: const Text('Send'),
                      ),
                    ],
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
