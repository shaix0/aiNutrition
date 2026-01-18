// lib/notifications/notification_ui.dart

import 'package:flutter/material.dart';
import 'notification_repository.dart';
import 'notification_list_page.dart';
import 'notification_model.dart';

class NotificationUI {
  static void showTodayNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _TodayNotificationSheet(),
    );
  }
}

class _TodayNotificationSheet extends StatelessWidget {
  const _TodayNotificationSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '今日通知',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 今日通知 ( 最新5筆 )
            StreamBuilder<List<AppNotification>>(
              stream: NotificationRepository.todayNotificationsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final list = snapshot.data!;

                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('今天還沒有通知'),
                  );
                }

                return Column(
                  children: list.take(5).map((n) {
                    return ListTile(
                      leading: const Icon(Icons.notifications_none),
                      title: Text(n.title),
                      subtitle: Text(
                        n.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        NotificationRepository.markAsRead(n.id);
                        // 之後可導向詳情頁
                      },
                    );
                  }).toList(),
                );
              },
            ),

            const Divider(),

            // 顯示全部
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationListPage(),
                    ),
                  );
                },
                child: const Text('顯示全部'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
