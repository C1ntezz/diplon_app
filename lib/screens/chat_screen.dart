import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/chat_store.dart';
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
  bool _uploadingAttachment = false;

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
    
    // Сбрасываем активный чат в ChatStore при выходе с экрана диалога.
    context.read<ChatStore>().closeActiveConversation();
    
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

  Future<void> _sendAttachment({
    required List<int> bytes,
    required String filename,
    required String type,
  }) async {
    final store = context.read<ChatStore>();
    final api = context.read<ApiService>();

    if (store.activeConversationId == null) return;

    setState(() => _uploadingAttachment = true);
    try {
      final mediaUrl = await api.uploadFile(bytes, filename);
      await store.sendText(type == 'file' ? filename : '', type: type, mediaUrl: mediaUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(type == 'image' ? 'Изображение отправлено' : 'Файл отправлен')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 90,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    await _sendAttachment(
      bytes: bytes,
      filename: image.name.isNotEmpty ? image.name : 'image.jpg',
      type: 'image',
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    await _sendAttachment(
      bytes: bytes,
      filename: file.name,
      type: 'file',
    );
  }

  Future<void> _showAttachmentOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Изображение из галереи'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Файл'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
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
                          else if ((msg.content ?? '').isNotEmpty && msg.type != 'file')
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file, size: 18, color: textColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    (msg.content ?? '').isNotEmpty ? msg.content! : 'Файл',
                                    style: TextStyle(
                                      color: textColor,
                                      decoration: TextDecoration.underline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
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
                        icon: _uploadingAttachment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.attach_file),
                        tooltip: 'Прикрепить',
                        onPressed: _uploadingAttachment ? null : _showAttachmentOptions,
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
