// lib/notifications/notification_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_model.dart';

class NotificationRepository {
  static final _db = FirebaseFirestore.instance;

  // 未讀數量
  static Stream<int> unreadCountStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  // 今日通知
  static Stream<List<AppNotification>> todayNotificationsStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final startOfToday = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
        )
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map(AppNotification.fromFirestore).toList(),
        );
  }

  // 所有通知
  static Stream<List<AppNotification>> allNotificationsStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map(AppNotification.fromFirestore).toList(),
        );
  }

  // 標記單筆已讀
  static Future<void> markAsRead(String notificationId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }
}
