// lib/notifications/notification_ui.dart

import 'package:flutter/material.dart';
import 'notification_repository.dart';
import 'notification_list_page.dart';

class NotificationUI {
  /// 顯示今日通知彈窗
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

/// 今日通知底部彈窗
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

            // 今日通知 (最新 5 筆)
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
                    final bgColor = n.read ? Colors.grey[200] : Colors.white;
                    //final iconColor = n.read ? Colors.grey : Colors.redAccent;
                    final titleStyle = TextStyle(
                      color: n.read ? Colors.grey[700] : Colors.black,
                      fontWeight:
                          n.read ? FontWeight.normal : FontWeight.bold,
                    );
                    final subtitleStyle = TextStyle(
                      color: n.read ? Colors.grey[600] : Colors.black87,
                    );

                    return Container(
                      color: bgColor,
                      child: ListTile(
                        leading: Icon(
                          Icons.notifications_none_rounded,
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
                          // 可跳轉詳情頁或其他操作
                        },
                      ),
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
