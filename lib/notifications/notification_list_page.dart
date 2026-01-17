// lib/notifications/notification_list_page.dart

import 'package:flutter/material.dart';
import 'notification_repository.dart';
import 'notification_model.dart';

class NotificationListPage extends StatelessWidget {
  const NotificationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('所有通知')),
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
              return ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(n.title),
                subtitle: Text(n.body),
                onTap: () {
                  if (!n.read) {
                    NotificationRepository.markAsRead(n.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
