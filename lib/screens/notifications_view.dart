import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

class _NotificationItem {
  final String id;
  final String title;
  final String body;
  final String type; // INFO | SUCCESS | WARNING | ALERT
  final int createdAt;
  final bool read;
  const _NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.read,
  });
}

/// نسخة Flutter من pages/NotificationsView.tsx.
/// ملاحظة: بدلنا آلية Web Push (VAPID + Service Worker) بالمكافئ الأصلي على
/// أندرويد وهو Firebase Cloud Messaging عبر firebase_messaging مباشرة — نفس
/// الأثر النهائي (حفظ fcmToken في Firestore) لكن بالطريقة الأصلية الصحيحة
/// لتطبيق native بدل هاك الويب.
class NotificationsView extends StatefulWidget {
  final AppUser user;
  final VoidCallback onBack;
  const NotificationsView({super.key, required this.user, required this.onBack});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  List<_NotificationItem> _notifications = [];
  bool _loading = true;
  bool _isActivating = false;
  AuthorizationStatus _permissionStatus = AuthorizationStatus.notDetermined;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();

    _sub = db
        .collection('notifications')
        .where('userId', whereIn: [widget.user.id, 'ALL', widget.user.role.value])
        .snapshots()
        .listen((snap) {
      final docs = snap.docs.map((d) {
        final m = stripFirestore(d.data()) as Map<String, dynamic>;
        return _NotificationItem(
          id: d.id,
          title: m['title'] as String? ?? '',
          body: m['body'] as String? ?? '',
          type: m['type'] as String? ?? 'INFO',
          createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
          read: m['read'] == true,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _notifications = docs;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refreshPermissionStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (mounted) setState(() => _permissionStatus = settings.authorizationStatus);
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isActivating = true);
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (mounted) setState(() => _permissionStatus = settings.authorizationStatus);

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await db.collection('users').doc(widget.user.id).update({
            'fcmToken': token,
            'notificationsEnabled': true,
            'lastTokenUpdate': DateTime.now().millisecondsSinceEpoch,
          });
          if (mounted) {
            showAppAlert(context,
                'تم تفعيل إشعارات الهاتف بنجاح! ستصلك التنبيهات حتى والتطبيق مغلق.');
          }
        }
      } else {
        if (mounted) {
          showAppAlert(
              context, 'يجب السماح بالإشعارات من إعدادات الهاتف لتلقي التنبيهات.');
        }
      }
    } catch (error) {
      debugPrint('Notification Error: $error');
      if (mounted) showAppAlert(context, 'فشل تفعيل الإشعارات، يرجى المحاولة لاحقاً.');
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final batch = db.batch();
    for (final n in _notifications.where((n) => !n.read)) {
      batch.update(db.collection('notifications').doc(n.id), {'read': true});
    }
    await batch.commit();
  }

  ({IconData icon, Color bg, Color fg}) _iconFor(_NotificationItem n) {
    if (n.read) {
      return (icon: _typeIcon(n.type), bg: C.slate100, fg: C.slate400);
    }
    return (icon: _typeIcon(n.type), bg: C.emerald50, fg: C.emerald600);
  }

  IconData _typeIcon(String type) {
    if (type == 'SUCCESS') return LucideIcons.checkCircle;
    if (type == 'ALERT') return LucideIcons.bell;
    if (type == 'ADMIN_MESSAGE') return LucideIcons.megaphone;
    return LucideIcons.info;
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.read);
    final granted = _permissionStatus == AuthorizationStatus.authorized ||
        _permissionStatus == AuthorizationStatus.provisional;

    return Container(
      color: C.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (hasUnread)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: GestureDetector(
                                onTap: _markAllAsRead,
                                child: Text('قراءة الكل',
                                    style: T.s(10, T.w900, C.brandPrimary,
                                        letterSpacing: 1.2)),
                              ),
                            ),
                          PressScale(
                            scale: 0.9,
                            onTap: widget.onBack,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: C.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: C.slate100),
                                boxShadow: Sh.sm(),
                              ),
                              child: const Icon(LucideIcons.chevronRight,
                                  size: 20, color: C.slate700),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('مركز التنبيهات',
                              style: T.s(30, T.w900, C.slate900,
                                  letterSpacing: -0.6)),
                          const SizedBox(height: 4),
                          Text('تنبيهات النظام والرسائل',
                              style: T.s(10, T.w700, C.slate400,
                                  letterSpacing: 1.4)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (!granted) _activationCard() else _grantedBanner(),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(child: Spinner(size: 40, color: C.emerald500)),
                    )
                  else if (_notifications.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 128),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: C.slate100, width: 4, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(64),
                      ),
                      child: Column(
                        children: [
                          Icon(LucideIcons.sparkles,
                              size: 48, color: C.slate300.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text('لا توجد تنبيهات جديدة حالياً',
                              style: T.s(13, T.w700, C.slate300)),
                        ],
                      ),
                    )
                  else
                    for (final n in _notifications) _notificationRow(n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _activationCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: C.slate900,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: C.white.withOpacity(0.05)),
        boxShadow: Sh.xxl(),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              top: 0, right: 0,
              child: Blob(size: 128, color: C.emerald500.withOpacity(0.10))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('فعّل تنبيهات الهاتف',
                            style: T.s(20, T.w900, C.white)),
                        const SizedBox(height: 4),
                        Text('لتصلك العروض والرسائل فوراً كرسالة نصية على هاتفك',
                            textAlign: TextAlign.right,
                            style: T.s(10, T.w700, C.white.withOpacity(0.6))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: C.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.white.withOpacity(0.1)),
                    ),
                    child: const Icon(LucideIcons.smartphone,
                        size: 32, color: Color(0xFF34D399)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PressScale(
                onTap: _isActivating ? null : _requestNotificationPermission,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.emerald600,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Sh.xl(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _isActivating
                          ? const Spinner(size: 20)
                          : const Icon(LucideIcons.volume2,
                              size: 20, color: C.white),
                      const SizedBox(width: 12),
                      Text('تفعيل الإشعارات الآن',
                          style: T.s(14, T.w900, C.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grantedBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.emerald50,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: C.emerald100, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.shieldCheck, size: 20, color: C.emerald600),
          const SizedBox(width: 12),
          Text('إشعارات النظام المباشرة مفعلة بنجاح',
              style: T.s(10, T.w900, C.emerald700, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  Widget _notificationRow(_NotificationItem n) {
    final style = _iconFor(n);
    final timeStr = intl.DateFormat('hh:mm a', 'ar').format(
        DateTime.fromMillisecondsSinceEpoch(n.createdAt));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: n.read ? C.white.withOpacity(0.5) : C.white,
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: n.read ? C.slate100 : C.white, width: 2),
        boxShadow: n.read ? null : Sh.xl(color: C.slate200.withOpacity(0.5)),
      ),
      child: Opacity(
        opacity: n.read ? 0.6 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (!n.read)
              const Positioned(
                top: -12,
                left: -12,
                child: PingDot(size: 10, color: C.emerald500),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(n.title,
                          textAlign: TextAlign.right,
                          style: T.s(14, T.w900, C.slate800, height: 1.2)),
                      const SizedBox(height: 4),
                      Text(n.body,
                          textAlign: TextAlign.right,
                          style: T.s(12, T.w700, C.slate500.withOpacity(0.8),
                              height: 1.6)),
                      const SizedBox(height: 8),
                      Text(timeStr,
                          style: T.s(9, T.w900, C.slate300,
                              letterSpacing: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(style.icon, size: 24, color: style.fg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
