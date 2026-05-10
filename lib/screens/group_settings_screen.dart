import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/chat_store.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;

  const GroupSettingsScreen({
    super.key,
    required this.conversationId,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _savingName = false;
  bool _savingRole = false;
  bool _savingMembers = false;
  bool _leavingGroup = false;

  Conversation? _conversation(ChatStore store) {
    try {
      return store.conversations.firstWhere((c) => c.id == widget.conversationId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _renameGroup(Conversation conversation) async {
    final controller = TextEditingController(text: conversation.name ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Название группы'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Название',
              prefixIcon: Icon(Icons.edit_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _savingName ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: _savingName
                  ? null
                  : () async {
                      final name = controller.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Введите название группы')),
                        );
                        return;
                      }

                      setDialogState(() => _savingName = true);
                      setState(() => _savingName = true);

                      try {
                        await context.read<ChatStore>().renameGroup(conversation.id, name);
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      } finally {
                        if (mounted && dialogContext.mounted) {
                          setDialogState(() => _savingName = false);
                          setState(() => _savingName = false);
                        }
                      }
                    },
              child: _savingName
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(Conversation conversation, String userId, String role) async {
    setState(() => _savingRole = true);
    try {
      await context.read<ChatStore>().updateGroupMemberRole(conversation.id, userId, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(role == 'admin' ? 'Администратор назначен' : 'Роль изменена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingRole = false);
    }
  }

  Future<void> _showAddMemberDialog(Conversation conversation) async {
    var loading = true;
    var requestedUsers = false;
    var users = <AppUser>[];
    String? error;
    final existingIds = conversation.participants.map((user) => user.id).toSet();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> loadUsers() async {
            try {
              final loaded = await context.read<ApiService>().getUsers();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                users = loaded.where((user) => !existingIds.contains(user.id)).toList();
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
            title: const Text('Добавить участника'),
            content: SizedBox(
              width: 420,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : error != null
                      ? Text(error!, style: const TextStyle(color: Colors.red))
                      : users.isEmpty
                          ? const Text('Нет пользователей для добавления')
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 340),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: users.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final user = users[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text(user.title.isNotEmpty ? user.title[0].toUpperCase() : '?'),
                                    ),
                                    title: Text(user.title),
                                    subtitle: Text('@${user.username}'),
                                    trailing: const Icon(Icons.add),
                                    onTap: _savingMembers
                                        ? null
                                        : () async {
                                            setState(() => _savingMembers = true);
                                            try {
                                              await context.read<ChatStore>().addGroupMember(
                                                    conversation.id,
                                                    user.id,
                                                  );
                                              if (!dialogContext.mounted) return;
                                              Navigator.of(dialogContext).pop();
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Участник добавлен')),
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Ошибка: $e')),
                                              );
                                            } finally {
                                              if (mounted) setState(() => _savingMembers = false);
                                            }
                                          },
                                  );
                                },
                              ),
                            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeMember(Conversation conversation, AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('${user.title} потеряет доступ к этой группе.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _savingMembers = true);
    try {
      await context.read<ChatStore>().removeGroupMember(conversation.id, user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Участник удален')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingMembers = false);
    }
  }

  Future<void> _leaveGroup(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content: const Text('Группа исчезнет из вашего списка чатов.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _leavingGroup = true);
    try {
      await context.read<ChatStore>().leaveGroup(conversation.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(content: Text('Вы вышли из группы')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _leavingGroup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChatStore>();
    final api = context.read<ApiService>();
    final conversation = _conversation(store);

    if (conversation == null) {
      return const Scaffold(
        body: Center(child: Text('Группа не найдена')),
      );
    }

    final isAdmin = conversation.isAdmin(api.userId);
    final title = conversation.name ?? 'Группа';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Группа'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?'),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${conversation.participants.length} участников',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 14),
                if (isAdmin)
                  OutlinedButton.icon(
                    onPressed: _savingName ? null : () => _renameGroup(conversation),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Изменить название'),
                  ),
                if (isAdmin) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _savingMembers ? null : () => _showAddMemberDialog(conversation),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Добавить участника'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Участники',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...conversation.participants.map((user) {
            final role = conversation.roleOf(user.id);
            final canManageUser = isAdmin && user.id != api.userId && !_savingRole && !_savingMembers;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(user.title.isNotEmpty ? user.title[0].toUpperCase() : '?'),
                ),
                title: Text(user.title),
                subtitle: Text('@${user.username}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(role == 'admin' ? 'Админ' : 'Участник'),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (canManageUser)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'remove') {
                            _removeMember(conversation, user);
                          } else {
                            _changeRole(conversation, user.id, value);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'admin',
                            child: Text('Сделать админом'),
                          ),
                          const PopupMenuItem(
                            value: 'member',
                            child: Text('Сделать участником'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Удалить из группы'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _leavingGroup ? null : () => _leaveGroup(conversation),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти из группы'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
