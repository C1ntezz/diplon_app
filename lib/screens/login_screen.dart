import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/chat_store.dart';
import 'chat_list_screen.dart';

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
        // Регистрация
        await api.register(
          username, 
          password, 
          displayName: displayName.isNotEmpty ? displayName : null
        );
      }

      // После успешной регистрации сразу делаем логин, либо просто логинимся
      final data = await api.login(username, password);
      
      await api.saveSession(
        token: data['token'].toString(),
        userId: data['userId'].toString(),
        username: data['username'].toString(),
        displayName: (data['displayName'] ?? data['username']).toString(),
      );

      if (!mounted) return;
      context.read<SocketService>().connect(token: api.token!);
      
      // Инициализация хранилища (здесь же происходит генерация ключей RSA-2048 через fast_rsa!)
      await context.read<ChatStore>().init();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
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
                      // Очищаем поля при переключении
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
