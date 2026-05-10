import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/chat_store.dart';
import '../services/encryption_service.dart';
import 'chat_list_screen.dart';

import 'package:workmanager/workmanager.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final u = TextEditingController();
  final p = TextEditingController();
  final d = TextEditingController(); // Display name for registration
  
  bool loading = false;
  bool isLogin = true; // Toggle between Login and Register modes

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    d.dispose();
    super.dispose();
  }

  /// Показывает диалог выбора: импортировать ключи или создать новые
  Future<bool?> _showKeyDecisionDialog(KeyStatus status) async {
    final isCorrupted = status == KeyStatus.corrupted;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isCorrupted ? Icons.warning_amber_rounded : Icons.vpn_key, 
                 color: isCorrupted ? Colors.orange : Theme.of(ctx).primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isCorrupted ? 'Ключи повреждены' : 'Ключи не найдены',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCorrupted
                ? 'Ключи шифрования повреждены (сброс безопасности устройства). '
                    'Вы можете импортировать резервную копию или создать новые.'
                : 'Для этого аккаунта не найдены ключи шифрования. '
                    'Вы можете импортировать резервную копию или создать новую пару.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Импортировать ключи'),
                onPressed: () => Navigator.of(ctx).pop(false), // false = import
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Создать новые'),
                onPressed: () => Navigator.of(ctx).pop(true), // true = create new
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ При создании новых ключей старые сообщения будет невозможно расшифровать.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Показывает диалог импорта ключей (вставка JSON)
  Future<String?> _showImportDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт ключей'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Вставьте резервную копию ключей (JSON):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"version":2,"userId":"...", ...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceedAfterLogin() async {
    // Регистрируем фоновую задачу
    Workmanager().registerPeriodicTask(
      "diplom_messenger_sync_task",
      "backgroundSync",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatListScreen()),
    );
  }

  Future<void> _handleKeySetup(ApiService api, KeyStatus status) async {
    final encryption = context.read<EncryptionService>();

    while (true) {
      final createNew = await _showKeyDecisionDialog(status);
      if (createNew == null || !mounted) return; // dialog dismissed somehow

      if (createNew) {
        // Создать новые ключи
        await encryption.generateKeys(api);
        await _proceedAfterLogin();
        return;
      } else {
        // Импортировать
        final json = await _showImportDialog();
        if (json == null || json.isEmpty || !mounted) continue; // back to decision

        final success = await encryption.importKeys(json, api);
        if (!mounted) return;

        if (success) {
          await _proceedAfterLogin();
          return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Неверный формат ключей. Попробуйте ещё раз.')),
          );
          // Loop back to decision dialog
        }
      }
    }
  }

  void _submit() async {
    final api = context.read<ApiService>();
    
    final username = u.text.trim();
    final password = p.text.trim();
    final displayName = d.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите логин и пароль')),
      );
      return;
    }

    setState(() => loading = true);
    
    try {
      if (!isLogin) {
        await api.register(
          username, 
          password, 
          displayName: displayName.isNotEmpty ? displayName : null
        );
      }

      final data = await api.login(username, password);
      
      await api.saveSession(
        token: data['accessToken']?.toString() ?? data['token'].toString(),
        refreshToken: data['refreshToken']?.toString() ?? '',
        userId: data['userId'].toString(),
        username: data['username'].toString(),
        displayName: (data['displayName'] ?? data['username']).toString(),
      );

      if (!mounted) return;
      context.read<SocketService>().connect(token: api.token!);
      
      // Проверяем статус ключей (НЕ генерируем автоматически)
      final keyStatus = await context.read<ChatStore>().init();

      if (!mounted) return;

      if (keyStatus == KeyStatus.ready) {
        // Ключи на месте — сразу в чаты
        await _proceedAfterLogin();
      } else {
        // Ключей нет или они битые — показываем диалог
        await _handleKeySetup(api, keyStatus);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLogin ? Icons.lock_outline : Icons.person_add_outlined, 
                  size: 64, 
                  color: Theme.of(context).primaryColor
                ),
                const SizedBox(height: 16),
                Text(
                  isLogin ? 'Вход в систему' : 'Регистрация', 
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 8),
                Text(
                  isLogin 
                    ? 'Введите свои данные для входа' 
                    : 'Создайте аккаунт и безопасный RSA-туннель',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                TextField(
                  controller: u, 
                  decoration: const InputDecoration(
                    labelText: 'Логин',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                
                if (!isLogin) ...[
                  TextField(
                    controller: d, 
                    decoration: const InputDecoration(
                      labelText: 'Отображаемое имя (необязательно)',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: p, 
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    prefixIcon: Icon(Icons.password),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 20, 
                            width: 20, 
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                          )
                        : Text(isLogin ? 'Войти' : 'Зарегистрироваться', style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: loading ? null : () {
                    setState(() {
                      isLogin = !isLogin;
                      if (isLogin) d.clear();
                    });
                  },
                  child: Text(
                    isLogin 
                      ? 'Нет аккаунта? Зарегистрироваться' 
                      : 'Уже есть аккаунт? Войти'
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
