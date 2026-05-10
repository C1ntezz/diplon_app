import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/chat_store.dart';
import 'services/encryption_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notification_service.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("⏳ [WorkManager] Выполнение фоновой задачи: $task");
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await NotificationService().init();
  } catch (e, st) {
    print('❌ [Boot] NotificationService init failed: $e\n$st');
  }
  
  // Workmanager не поддерживается в Flutter Web.
  if (!kIsWeb) {
    try {
      Workmanager().initialize(
        callbackDispatcher, 
        isInDebugMode: false
      );
    } catch (e, st) {
      print('❌ [Boot] Workmanager init failed: $e\n$st');
    }
  }

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
        ChangeNotifierProvider(create: (_) => ThemeService()..load()),
        ChangeNotifierProxyProvider3<ApiService, SocketService, EncryptionService, ChatStore>(
          create: (context) => ChatStore(
            api: context.read<ApiService>(),
            socketService: context.read<SocketService>(),
            encryption: context.read<EncryptionService>(),
          ),
          update: (_, api, socket, encryption, chatStore) => chatStore!,
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeService.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const Boot(),
        ),
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
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final api = context.read<ApiService>();
      print('🔍 [Boot] Loading session...');
      await api.loadSession();
      print('🔍 [Boot] Session loaded, token: ${api.token != null ? "present" : "null"}');

      if (api.token != null) {
        final socket = context.read<SocketService>();
        print('🔍 [Boot] Connecting socket...');
        socket.connect(token: api.token!);
        await context.read<ChatStore>().init();
        print('🔍 [Boot] ChatStore initialized');
      }
    } catch (e, st) {
      print('❌ [Boot] Init error: $e\n$st');
      error = '$e';
    }

    setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Ошибка инициализации', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() { error = null; ready = false; });
                    _init();
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return api.token == null ? const LoginScreen() : const ChatListScreen();
  }
}
