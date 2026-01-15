import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

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
