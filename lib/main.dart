import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/chat_store.dart';
import 'services/encryption_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notification_service.dart';
import 'app_config.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('⏳ [WorkManager] Запуск фоновой проверки: $task');

      // Инициализируем уведомления в этом изоляте
      final notifications = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await notifications.initialize(const InitializationSettings(android: androidSettings));

      // Читаем токен
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'accessToken') ?? 
                    await storage.read(key: 'jwt_token');

      if (token == null) {
        print('⏳ [WorkManager] Нет токена, пропускаем');
        return true;
      }

      // Запрос к серверу
      final base = AppConfig.baseUrl.endsWith('/')
          ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
          : AppConfig.baseUrl;

      final response = await http.get(
        Uri.parse('$base/api/conversations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        print('⏳ [WorkManager] Ошибка API: ${response.statusCode}');
        return true;
      }

      final List convs = jsonDecode(response.body);
      int totalUnread = 0;
      String? lastSender;
      String? lastText;

      for (final c in convs) {
        final unread = (c['unreadCount'] as int?) ?? 0;
        if (unread > 0) {
          totalUnread += unread;
          lastSender ??= (c['name'] ?? c['id'])?.toString();
          final lm = c['lastMessage'];
          if (lm != null && lm is Map) {
            lastText ??= lm['text']?.toString();
          }
        }
      }

      // Проверяем, были ли уже уведомлены с прошлого раза
      final prefs = await SharedPreferences.getInstance();
      final lastNotifiedCount = prefs.getInt('wm_last_notified_count') ?? 0;

      print('⏳ [WorkManager] Непрочитано: $totalUnread, последнее уведомление: $lastNotifiedCount');

      if (totalUnread > 0 && totalUnread != lastNotifiedCount) {
        final title = totalUnread == 1
            ? (lastSender ?? 'Новое сообщение')
            : 'Новые сообщения';
        final body = totalUnread == 1
            ? (lastText ?? '')
            : '$totalUnread непрочитанных сообщений';

        await notifications.show(
          DateTime.now().millisecond,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'diplom_messenger_channel',
              'Сообщения',
              channelDescription: 'Уведомления о новых сообщениях',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
        await prefs.setInt('wm_last_notified_count', totalUnread);
        print('⏳ [WorkManager] Уведомление отправлено: $title');
      }
    } catch (e, st) {
      print('❌ [WorkManager] Ошибка: $e\n$st');
    }

    return true;
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
        isInDebugMode: true, // true чтобы видеть логи и ускорить первую проверку
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
