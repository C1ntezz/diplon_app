import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/chat_store.dart';
import 'services/encryption_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiService()),
        Provider(create: (_) => SocketService()),
        Provider(create: (_) => EncryptionService()),
        ChangeNotifierProxyProvider3<ApiService, SocketService, EncryptionService, ChatStore>(
          create: (context) => ChatStore(
            api: context.read<ApiService>(),
            socketService: context.read<SocketService>(),
            encryption: context.read<EncryptionService>(),
          ),
          update: (_, api, socket, encryption, chatStore) => chatStore!,
        ),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Boot(),
      ),
    );
  }
}

class Boot extends StatefulWidget {
  const Boot({super.key});

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = context.read<ApiService>();
    await api.loadSession();

    if (api.token != null) {
      final socket = context.read<SocketService>();
      socket.connect(token: api.token!);
      await context.read<ChatStore>().init();
    }

    setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return api.token == null ? const LoginScreen() : const ChatListScreen();
  }
}
