// lib/notifications/notification_bell.dart

import 'package:flutter/material.dart';
import 'notification_repository.dart';

class NotificationBell extends StatelessWidget {
  final VoidCallback onPressed;

  const NotificationBell({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationRepository.unreadCountStream(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: onPressed,
            ),

            // 未讀紅點
            if (unread > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
