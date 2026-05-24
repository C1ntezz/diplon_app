import 'dart:async';
import 'dart:convert';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_config.dart';

/// SharedPreferences keys for inter-isolate communication
const _kAppForeground = 'app_foreground';
const _kActiveConvId = 'active_conv_id';
const _kSocketLastActive = 'bg_socket_last_active';
const _kLastNotifiedMsgId = 'bg_last_notified_msg';

/// Background service entry point — runs in a separate isolate on Android.
@pragma('vm:entry-point')
Future<bool> onBackgroundStart(ServiceInstance service) async {
  // ── Init notifications (resilient) ──
  FlutterLocalNotificationsPlugin? notifications;
  try {
    notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: androidSettings),
    );
    final androidPlugin =
        notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'diplom_messenger_bg',
          'Фоновый сервис',
          description: 'Работа мессенджера в фоне',
          importance: Importance.low,
        ),
      );
    }
  } catch (e) {
    print('❌ [BG] Init notifications error: $e');
  }

  // ── Init storage (resilient) ──
  SharedPreferences? prefs;
  FlutterSecureStorage? ss;
  try {
    prefs = await SharedPreferences.getInstance();
    ss = const FlutterSecureStorage();
  } catch (e) {
    print('❌ [BG] Init storage error: $e');
    return true; // Can't work without storage, but don't crash
  }

  io.Socket? socket;
  Timer? reconnectTimer;
  Timer? heartbeatTimer;

  void _updateActivity() {
    try { prefs?.setString(_kSocketLastActive, DateTime.now().toIso8601String()); } catch (_) {}
  }

  Future<void> _showMessageNotification(Map<String, dynamic> data) async {
    if (notifications == null || prefs == null) return;
    try {
      final msgId = (data['_id'] ?? '').toString();
      final lastNotified = prefs.getString(_kLastNotifiedMsgId) ?? '';

      if (msgId.isNotEmpty && msgId == lastNotified) return;

      // Reload to get latest values from main isolate
      await prefs.reload();

      final appForeground = prefs.getString(_kAppForeground) == 'true';
      final activeConvId = prefs.getString(_kActiveConvId) ?? '';
      final msgConvId = (data['conversationId'] ?? '').toString();

      // Не шлём уведомление только если юзер прямо сейчас смотрит этот чат
      if (appForeground && activeConvId.isNotEmpty && activeConvId == msgConvId) {
        return;
      }

      String senderName = 'Новое сообщение';
      final sender = data['sender'];
      if (sender is Map<String, dynamic>) {
        senderName = (sender['displayName'] ?? sender['username'] ?? 'Новое сообщение').toString();
      }

      final type = (data['type'] ?? 'text').toString();
      String body;
      switch (type) {
        case 'image': body = '📷 Изображение'; break;
        case 'gif':   body = '🎬 GIF'; break;
        case 'voice': body = '🎤 Голосовое сообщение'; break;
        case 'file':  body = '📎 Файл'; break;
        case 'sticker': body = '😶 Стикер'; break;
        case 'system': return;
        default:       body = 'Новое сообщение';
      }

      await notifications.show(
        DateTime.now().millisecond,
        senderName,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'diplom_messenger_channel',
            'Сообщения',
            channelDescription: 'Уведомления о новых сообщениях',
            importance: Importance.max,
            priority: Priority.high,
            autoCancel: true,
          ),
        ),
      );

      if (msgId.isNotEmpty) {
        await prefs.setString(_kLastNotifiedMsgId, msgId);
      }
    } catch (e) {
      print('❌ [BG] Notification error: $e');
    }
  }

  void _connectSocket() {
    if (ss == null || prefs == null) return;
    try {
      socket?.disconnect();

      ss!.read(key: 'accessToken').then((token) async {
        final actualToken = token ?? await ss!.read(key: 'jwt_token');
        if (actualToken == null || actualToken.isEmpty) return;

        print('🔌 [BG] Connecting socket...');

        socket = io.io(
          AppConfig.socketUrl,
          io.OptionBuilder()
              .setTransports(['websocket'])
              .enableAutoConnect()
              .setAuth({'token': actualToken})
              .build(),
        );

        socket!.onConnect((_) {
          print('🔌 [BG] Socket connected: ${socket!.id}');
          _updateActivity();
          reconnectTimer?.cancel();
          reconnectTimer = null;
        });

        socket!.onDisconnect((reason) {
          print('🔌 [BG] Socket disconnected: $reason');
          reconnectTimer?.cancel();
          reconnectTimer = Timer(const Duration(seconds: 10), () {
            print('🔌 [BG] Reconnecting...');
            _connectSocket();
          });
        });

        socket!.onConnectError((err) {
          print('🔌 [BG] Socket connect error: $err');
          reconnectTimer?.cancel();
          reconnectTimer = Timer(const Duration(seconds: 30), () {
            _connectSocket();
          });
        });

        socket!.on('newMessage', (data) {
          _updateActivity();
          try {
            _showMessageNotification(Map<String, dynamic>.from(data));
          } catch (e) {
            print('❌ [BG] Message handler error: $e');
          }
        });

        heartbeatTimer?.cancel();
        heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (socket?.connected == true) _updateActivity();
        });

        socket!.connect();
      }).catchError((e) {
        print('❌ [BG] Token read error: $e');
      });
    } catch (e) {
      print('❌ [BG] Socket setup error: $e');
    }
  }

  // ─── Start socket ───
  _connectSocket();

  // Handle stop signal from main isolate
  service.on('stop').listen((_) async {
    print('🔌 [BG] Service stopping...');
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    socket?.disconnect();
    socket = null;
    service.stopSelf();
  });

  return true;
}

/// Called from main isolate to configure the service.
Future<void> configureBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'diplom_messenger_bg',
      initialNotificationTitle: 'Diplom Messenger',
      initialNotificationContent: 'Сервис обмена сообщениями',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundStart,
      onBackground: onBackgroundStart,
    ),
  );
}

/// Start the background service.
Future<void> startBackgroundService() async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
    print('🔌 [BG] Background service started');
  } else {
    print('🔌 [BG] Background service already running');
    service.invoke('reconnect');
  }
}

/// Stop the background service (on logout).
Future<void> stopBackgroundService() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
}
