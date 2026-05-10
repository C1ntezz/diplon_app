import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _notifications.initialize(initSettings);

    // Создаём канал для foreground service (flutter_background_service)
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'diplom_messenger_bg',
          'Фоновый сервис',
          description: 'Уведомление о работе фонового сервиса',
          importance: Importance.min, // Низкий приоритет чтобы не раздражать
        ),
      );
    }
    
    // Запрашиваем права на отправку уведомлений (Android 13+)
    await Permission.notification.request();
  }

  Future<void> showNewMessageNotification(String senderName, String message) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'diplom_messenger_channel', 
      'Сообщения',
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.max,
      priority: Priority.high,
      autoCancel: true,
      ticker: 'Новое сообщение',
    );
    
    const details = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      DateTime.now().millisecond, 
      senderName, 
      message, 
      details,
    );
  }
}
