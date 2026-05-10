import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/chat_store.dart';
import '../services/encryption_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  List<AppUser> _allUsers = [];
  List<AppUser> _searchResults = [];
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() {
      _searchResults = _allUsers.where((u) {
        final uname = u.username.toLowerCase();
        final dname = (u.displayName ?? '').toLowerCase();
        return uname.contains(query) || dname.contains(query);
      }).toList();
    });
  }

  Future<void> _startSearch() async {
    setState(() {
      _isSearching = true;
      _loadingUsers = true;
    });

    try {
      final api = context.read<ApiService>();
      _allUsers = await api.getUsers();
      _onSearchChanged();
    } catch (e) {
      debugPrint('Ошибка загрузки пользователей: $e');
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });
  }

  Future<void> _showExportKeysDialog(BuildContext context) async {
    final encryption = context.read<EncryptionService>();
    final exportData = await encryption.exportKeys();

    if (exportData == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: ключи не найдены')),
      );
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔐 Экспорт ключей'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Сохраните этот код в безопасном месте. Он понадобится для восстановления доступа к сообщениям на другом устройстве.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                exportData,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: exportData));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ключи скопированы в буфер обмена')),
              );
            },
            child: const Text('Копировать'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportKeysDialog(BuildContext context) async {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📥 Импорт ключей'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Вставьте код резервной копии ключей:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '{"version": 2, "publicKey": "...", "privateKey": "..."}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final jsonData = controller.text.trim();
              if (jsonData.isEmpty) return;

              final encryption = context.read<EncryptionService>();
              final api = context.read<ApiService>();

              final success = await encryption.importKeys(jsonData, api);

              if (!context.mounted) return;
              Navigator.of(context).pop();

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Ключи успешно импортированы')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Ошибка импорта. Проверьте код ключей.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _startChatWithUser(AppUser user) async {
    final store = context.read<ChatStore>();
    final api = context.read<ApiService>();

    final existingConv = store.conversations
        .where((c) =>
            c.type == 'direct' &&
            c.participants.any((p) => p.id == user.id))
        .firstOrNull;

    String conversationId;
    if (existingConv != null) {
      conversationId = existingConv.id;
    } else {
      try {
        final newConv = await api.createConversation(user.id);
        await store.loadConversations();
        conversationId = newConv.id;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания чата: $e')),
        );
        return;
      }
    }

    _stopSearch();
    await store.openConversation(conversationId);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(title: user.title),
      ),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final selectedIds = <String>{};
    var users = <AppUser>[];
    var loading = true;
    var requestedUsers = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> loadUsers() async {
            try {
              final loaded = await context.read<ApiService>().getUsers();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                users = loaded;
                loading = false;
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                error = e.toString();
                loading = false;
              });
            }
          }

          if (!requestedUsers && loading && users.isEmpty && error == null) {
            requestedUsers = true;
            Future.microtask(loadUsers);
          }

          return AlertDialog(
            title: const Text('Создать группу'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название группы',
                      prefixIcon: Icon(Icons.groups_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    )
                  else if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red))
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: users.length,
                        itemBuilder: (_, index) {
                          final user = users[index];
                          final selected = selectedIds.contains(user.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedIds.add(user.id);
                                } else {
                                  selectedIds.remove(user.id);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              child: Text(user.title.isNotEmpty ? user.title[0].toUpperCase() : '?'),
                            ),
                            title: Text(user.title),
                            subtitle: Text('@${user.username}'),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.group_add),
                label: const Text('Создать'),
                onPressed: loading
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Введите название группы')),
                          );
                          return;
                        }
                        if (selectedIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Выберите хотя бы одного участника')),
                          );
                          return;
                        }

                        try {
                          final group = await context.read<ChatStore>().createGroup(
                                name: name,
                                participantIds: selectedIds.toList(),
                              );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          await context.read<ChatStore>().openConversation(group.id);
                          if (!mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(title: group.name ?? 'Группа'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка создания группы: $e')),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChatStore>();
    final api = context.read<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск по логину...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 16),
              )
            : const Text('Чаты'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _stopSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _startSearch,
            ),
          if (!_isSearching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                switch (value) {
                  case 'export_keys':
                    await _showExportKeysDialog(context);
                    break;
                  case 'import_keys':
                    await _showImportKeysDialog(context);
                    break;
                  case 'create_group':
                    await _showCreateGroupDialog();
                    break;
                  case 'settings':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'export_keys',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 8),
                      Text('Экспорт ключей'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'import_keys',
                  child: Row(
                    children: [
                      Icon(Icons.upload, size: 20),
                      SizedBox(width: 8),
                      Text('Импорт ключей'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'create_group',
                  child: Row(
                    children: [
                      Icon(Icons.group_add, size: 20),
                      SizedBox(width: 8),
                      Text('Создать группу'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, size: 20),
                      SizedBox(width: 8),
                      Text('Настройки'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isSearching ? _buildSearchResults() : _buildChatList(store, api),
    );
  }

  Widget _buildSearchResults() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return const Center(child: Text('Введите логин пользователя'));
    }

    if (_searchResults.isEmpty) {
      return const Center(child: Text('Никто не найден 🤷‍♂️'));
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user.title),
          subtitle: Text('@${user.username}'),
          onTap: () => _startChatWithUser(user),
        );
      },
    );
  }

  Widget _buildChatList(ChatStore store, ApiService api) {
    if (store.conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'У вас пока нет чатов',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Найти собеседника'),
              onPressed: _startSearch,
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => store.loadConversations(),
      child: ListView.separated(
        itemCount: store.conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = store.conversations[i];
          final isPinned = store.isConversationPinned(c.id);
          final other = c.participants.firstWhere(
            (p) => p.id != api.userId,
            orElse: () => c.participants.isNotEmpty
                ? c.participants.first
                : throw StateError('No users'),
          );

          final title = c.type == 'group' ? (c.name ?? 'Group') : other.title;
          final isOnline = store.onlineUsers.contains(other.id);

          return ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?'),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  )
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (c.updatedAt != null)
                  Text(
                    '${c.updatedAt!.hour.toString().padLeft(2, '0')}:${c.updatedAt!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                if (isPinned)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.push_pin, size: 14, color: Colors.amber),
                  ),
              ],
            ),
            subtitle: Text(
              c.lastMessage?.content ?? (c.lastMessage?.type == 'image' ? '📷 Изображение' : 'Нет сообщений'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.unreadCount > 0 ? Colors.black87 : (c.lastMessage == null ? Colors.grey[400] : Colors.grey[600]),
                fontWeight: c.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned ? Colors.amber[700] : Colors.grey,
                  ),
                  tooltip: isPinned ? 'Открепить чат' : 'Закрепить чат',
                  onPressed: () => store.toggleConversationPinned(c.id),
                ),
              ],
            ),
            onTap: () async {
              await store.openConversation(c.id);
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(title: title),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
