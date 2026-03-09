import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/chat_store.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/encryption_service.dart';
import 'chat_screen.dart';

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

    // Сначала ищем, есть ли уже диалог с этим юзером
    final existingConv = store.conversations.where((c) => c.type == 'direct' && c.participants.any((p) => p.id == user.id)).firstOrNull;

    String conversationId;
    if (existingConv != null) {
      conversationId = existingConv.id;
    } else {
      // Иначе создаем новый через API
      try {
        final newConv = await api.createConversation(user.id);
        await store.loadConversations();
        conversationId = newConv.id;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания чата: $e')));
        return;
      }
    }

    _stopSearch();
    await store.openConversation(conversationId);
    
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(title: user.title)));
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
                  case 'logout':
                    context.read<SocketService>().disconnect();
                    await api.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Перезапустите приложение')))),
                      (_) => false,
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
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Выйти', style: TextStyle(color: Colors.red)),
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
            const Text('У вас пока нет чатов', style: TextStyle(fontSize: 16, color: Colors.grey)),
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
          final other = c.participants.firstWhere(
            (p) => p.id != api.userId,
            orElse: () => c.participants.isNotEmpty ? c.participants.first : throw StateError('No users'),
          );

          final title = c.type == 'group' ? (c.name ?? 'Group') : other.title;
          final isOnline = store.onlineUsers.contains(other.id);

          return ListTile(
            leading: Stack(
              children: [
                CircleAvatar(child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?')),
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
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () async {
              await store.openConversation(c.id);
              if (!mounted) return;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(title: title)));
            },
          );
        },
      ),
    );
  }
}
