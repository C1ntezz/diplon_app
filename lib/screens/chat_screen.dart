import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../models/gif_result.dart';
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
    if (msg.type == 'gif') return 'GIF';
    if (msg.type == 'image') return 'Изображение';
    if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) return 'Файл';
    return 'Сообщение';
  }

  String _resolveMediaUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    return '$baseUrl$url';
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

  Future<void> _showGifPicker(ChatStore store) async {
    final searchController = TextEditingController(text: 'реакция');
    var loading = false;
    var results = <GifResult>[];
    String? error;
    var requestedInitialSearch = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> search() async {
            final query = searchController.text.trim();
            if (query.isEmpty) return;

            setSheetState(() {
              loading = true;
              error = null;
            });

            try {
              final loaded = await context.read<ApiService>().searchGifs(query);
              if (!sheetContext.mounted) return;
              setSheetState(() => results = loaded);
            } catch (e) {
              if (!sheetContext.mounted) return;
              setSheetState(() => error = e.toString());
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => loading = false);
              }
            }
          }

          if (!requestedInitialSearch) {
            requestedInitialSearch = true;
            Future.microtask(search);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => search(),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Поиск GIF',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          icon: const Icon(Icons.search),
                          tooltip: 'Искать',
                          onPressed: loading ? null : search,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Expanded(child: Center(child: CircularProgressIndicator()))
                    else if (error != null)
                      Expanded(
                        child: Center(
                          child: Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    else if (results.isEmpty)
                      const Expanded(child: Center(child: Text('GIF не найдены')))
                    else
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: results.length,
                          itemBuilder: (_, index) {
                            final gif = results[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                Navigator.of(sheetContext).pop();
                                await store.sendGif(gif.gifUrl);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  gif.previewUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.gif_box_outlined),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    searchController.dispose();
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
                          if (!msg.isDeleted &&
                              (msg.type == 'gif' || msg.type == 'image') &&
                              msg.mediaUrl != null &&
                              msg.mediaUrl!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _resolveMediaUrl(msg.mediaUrl!),
                                width: 240,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    width: 240,
                                    height: 150,
                                    alignment: Alignment.center,
                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Container(
                                  width: 240,
                                  height: 120,
                                  alignment: Alignment.center,
                                  color: Colors.grey.shade200,
                                  child: Text(
                                    msg.type == 'gif'
                                        ? 'Не удалось загрузить GIF'
                                        : 'Не удалось загрузить изображение',
                                  ),
                                ),
                              ),
                            ),
                          ] else if (!msg.isDeleted && msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) ...[
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
                      TextButton(
                        onPressed: () => _showGifPicker(store),
                        child: const Text('GIF'),
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
