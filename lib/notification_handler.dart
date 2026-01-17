import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final int timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'data': data,
        'timestamp': timestamp,
        'isRead': isRead,
      };

  factory AppNotification.fromMap(Map map) => AppNotification(
        id: map['id'],
        title: map['title'],
        body: map['body'],
        data: Map<String, dynamic>.from(map['data']),
        timestamp: map['timestamp'],
        isRead: map['isRead'] ?? false,
      );
}

class NotificationHandler {
  static void init(BuildContext context) {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleMessage(context, message);
    });
  }

  static void _handleMessage(
    BuildContext context,
    RemoteMessage message,
  ) {
    final title = message.notification?.title ?? '通知';
    final body = message.notification?.body ?? '';
    final data = message.data;

    // 🔔 前景：顯示站內提示
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleAction(context, data);
            },
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  static void _handleAction(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    switch (data['type']) {
      case 'chat':
        debugPrint('跳轉聊天室 ${data['targetId']}');
        break;
      case 'order':
        debugPrint('跳轉訂單 ${data['targetId']}');
        break;
    }
  }
}
