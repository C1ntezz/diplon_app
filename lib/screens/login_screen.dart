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
  bool loading = false;

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💬 Messenger', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                TextField(controller: u, decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 12),
                TextField(controller: p, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : () async {
                      setState(() => loading = true);
                      try {
                        final data = await api.login(u.text.trim(), p.text.trim());
                        await api.saveSession(
                          token: data['token'].toString(),
                          userId: data['userId'].toString(),
                          username: data['username'].toString(),
                          displayName: (data['displayName'] ?? data['username']).toString(),
                        );

                        context.read<SocketService>().connect(token: api.token!);
                        await context.read<ChatStore>().init();

                        if (!mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const ChatListScreen()),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка: ')));
                      } finally {
                        if (mounted) setState(() => loading = false);
                      }
                    },
                    child: loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Login'),
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
