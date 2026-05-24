import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/chat_store.dart';
import 'services/encryption_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'app_config.dart';
import 'package:workmanager/workmanager.dart';

// ─── WorkManager fallback (HTTP polling каждые 15 мин) ───
// Срабатывает ТОЛЬКО когда background service (socket) неактивен.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = FlutterLocalNotificationsPlugin();

      // Инициализируем уведомления в WorkManager изоляте
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await notifications.initialize(const InitializationSettings(android: androidSettings));

      // Проверяем, жив ли background service (сокет)
      final lastActive = prefs.getString('bg_socket_last_active') ?? '';
      if (lastActive.isNotEmpty) {
        final lastTime = DateTime.tryParse(lastActive);
        if (lastTime != null) {
          final since = DateTime.now().difference(lastTime);
          // Если сокет был активен менее 16 минут назад → он жив, не мешаем
          if (since < const Duration(minutes: 16)) {
            print('⏳ [WorkManager] Socket is alive (last: $since ago). Skipping.');
            return true;
          }
        }
      }

      print('⏳ [WorkManager] Socket appears dead. HTTP fallback active.');

      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'accessToken') ??
                    await storage.read(key: 'jwt_token');
      if (token == null) return true;

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
      if (response.statusCode != 200) return true;

      final List convs = jsonDecode(response.body);
      int totalUnread = 0;
      String? lastSender;
      String? lastType;

      for (final c in convs) {
        final unread = (c['unreadCount'] as int?) ?? 0;
        if (unread > 0) {
          totalUnread += unread;
          lastSender ??= (c['name'] ?? c['id'])?.toString();
          // Try to get participant name for direct chats
          if (lastSender == null && c['participants'] is List) {
            for (final p in c['participants']) {
              if (p is Map && p['_id'] != null) {
                lastSender = (p['displayName'] ?? p['username'] ?? 'Новое сообщение').toString();
                break;
              }
            }
          }
          final lm = c['lastMessage'];
          if (lm != null && lm is Map) {
            lastType ??= lm['type']?.toString();
          }
        }
      }

      final lastCount = prefs.getInt('wm_last_notified_count') ?? 0;

      if (totalUnread > 0 && totalUnread != lastCount) {
        String body;
        switch (lastType) {
          case 'image': body = '📷 Изображение'; break;
          case 'gif': body = '🎬 GIF'; break;
          case 'voice': body = '🎤 Голосовое'; break;
          case 'file': body = '📎 Файл'; break;
          case 'system': body = ''; break;
          default: body = ''; break;
        }
        if (body.isEmpty && totalUnread > 1) body = '$totalUnread непрочитанных';
        if (body.isEmpty) body = 'Новое сообщение';

        await notifications.show(
          DateTime.now().millisecond,
          totalUnread == 1
              ? (lastSender ?? 'Новое сообщение')
              : 'Новые сообщения',
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'diplom_messenger_channel', 'Сообщения',
              channelDescription: 'Уведомления о новых сообщениях',
              importance: Importance.max, priority: Priority.high,
            ),
          ),
        );
        await prefs.setInt('wm_last_notified_count', totalUnread);
      }
    } catch (e, st) {
      print('❌ [WorkManager] $e\n$st');
    }
    return true;
  });
}

// ─── Main ───
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try { await NotificationService().init(); }
  catch (e, st) { print('❌ [Boot] NotificationService: $e\n$st'); }

  if (!kIsWeb) {
    // WorkManager — инициализируем глобально
    try {
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode, // в релизе ведёт себя стандартно
      );
    } catch (e, st) { print('❌ [Boot] Workmanager: $e\n$st'); }

    // Background service — configure (not start yet, will start after login)
    try {
      await configureBackgroundService();
    } catch (e, st) { print('❌ [Boot] BackgroundService config: $e\n$st'); }
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
              seedColor: Colors.blue, brightness: Brightness.dark,
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
      await api.loadSession();

      if (api.token != null) {
        final socket = context.read<SocketService>();
        socket.connect(token: api.token!);
        await context.read<ChatStore>().init();
        socket.activateConnection();

        // Если уже залогинены — запускаем background service
        if (!kIsWeb) {
          try {
            await startBackgroundService();
          } catch (e) { print('⚠️ [Boot] startBackgroundService: $e'); }
        }
      }
    } catch (e, st) {
      error = '$e';
      print('❌ [Boot] Init: $e\n$st');
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
                const Text('Ошибка инициализации',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
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
