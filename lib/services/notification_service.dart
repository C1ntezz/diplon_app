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
