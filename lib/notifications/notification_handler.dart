// lib/notifications/notification_handler.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationHandler {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// 初始化（App 啟動時呼叫）
  static Future<void> init() async {
    await _initLocalNotification();
    _initFCMListener();
  }

  /// 本地通知初始化（前台顯示用）
  static Future<void> _initLocalNotification() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _localNotifications.initialize(settings);
  }

  /// FCM 前 / 後台監聽
  static void _initFCMListener() {
    /// 🔔 前台 → 手動顯示系統通知
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    /// 點擊系統通知打開 App
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // 不強制導頁，讓使用者自己點鈴鐺
    });
  }

  /// 取得 FCM Token
  static Future<String?> getFcmToken() async {
    return await FirebaseMessaging.instance.getToken();
  }
}
