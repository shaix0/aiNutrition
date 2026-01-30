// lib/notifications/notification_list_page.dart

import 'package:flutter/material.dart';
import 'notification_repository.dart';

class NotificationListPage extends StatelessWidget {
  const NotificationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('所有通知'),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationRepository.markAllAsRead();
            },
            child: const Text(
              '全部標示已讀',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: NotificationRepository.allNotificationsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snapshot.data!;

          if (list.isEmpty) {
            return const Center(child: Text('目前沒有通知'));
          }

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final n = list[index];

              final icon = n.read ? Icons.notifications_rounded : Icons.notifications_none_rounded;
              final bgColor = n.read ? Colors.grey[200] : Colors.white;
              //final iconColor = n.read ? Colors.grey : Colors.redAccent;
              final titleStyle = TextStyle(
                color: n.read ? Colors.grey[700] : Colors.black,
                fontWeight: n.read ? FontWeight.normal : FontWeight.bold,
              );
              final subtitleStyle = TextStyle(
                color: n.read ? Colors.grey[600] : Colors.black87,
              );

              return Container(
                color: bgColor,
                child: ListTile(
                  leading: Icon(
                    icon,
                    color: Colors.grey,
                  ),
                  title: Text(
                    n.title,
                    style: titleStyle,
                  ),
                  subtitle: Text(
                    n.body,
                    style: subtitleStyle,
                  ),
                  onTap: () {
                    if (!n.read) {
                      NotificationRepository.markAsRead(n.id);
                    }
                    // 可跳轉詳情頁
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
