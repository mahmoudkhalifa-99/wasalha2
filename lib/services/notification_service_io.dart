// خدمة الإشعارات: إشعارات محلية + FCM + مستمع Firestore للإشعارات المباشرة.
//
// فكرة منع التكرار: كل إشعار له "key" ثابت (مثلاً offer_<id> أو order_<id>)
// ونحوّله لرقم إشعار ثابت. لو وصل نفس الإشعار من أكتر من مسار (Firestore +
// FCM) أندرويد بيستبدله بدل ما يكرره.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/push_config.dart';
import 'firebase_service.dart';

const String _channelId = 'wasalha_high_importance';
const String _channelName = 'إشعارات وصلها';
const String _channelDesc = 'الطلبات وعروض الأسعار والرسائل';

/// معالج رسائل FCM في الخلفية / التطبيق مقفول (لازم تكون top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.init();
  await NotificationService.showFromRemote(message);
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static StreamSubscription? _fcmSub;
  static String? _startedFor;

  static Future<void> init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    _inited = true;
  }

  /// طلب إذن الإشعارات (أندرويد 13+). بيرجع true لو مسموح.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> show({
    required String key,
    required String title,
    required String body,
  }) async {
    try {
      await init();
      // id = 0 + tag = key: نفس طريقة أندرويد في عرض إشعارات FCM الجاهزة،
      // فلو وصل نفس الإشعار من FCM ومن Firestore بيستبدلوا بعض (من غير تكرار).
      await _plugin.show(
        0,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            onlyAlertOnce: true,
            tag: key,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('local notification failed: $e');
    }
  }

  static Future<void> showFromRemote(RemoteMessage m) async {
    final d = m.data;
    final title = d['title'] ?? m.notification?.title ?? 'وصلها';
    final body = d['body'] ?? m.notification?.body ?? '';
    if (body.isEmpty && title == 'وصلها') return;
    await show(
      key: d['key'] ?? m.messageId ?? DateTime.now().toIso8601String(),
      title: title,
      body: body,
    );
  }

  /// بنبدأ نسمع للمستخدم الحالي: FCM وهو شغال + إشعارات Firestore المباشرة.
  static Future<void> startFor(String userId, String roleValue) async {
    await init();
    // بيتنادى مع كل تحديث لوثيقة المستخدم — ما نعيدش التشغيل لنفس المستخدم.
    if (_startedFor == userId && _fcmSub != null) return;
    await stop();
    _startedFor = userId;

    _fcmSub = FirebaseMessaging.onMessage.listen(showFromRemote);

    _firstSnapshot = true;
  }

  static bool _firstSnapshot = true;

  /// AppShell بيمرّر لنا snapshot الإشعارات (مستمع واحد بس للمجموعة دي).
  /// أول snapshot بنتجاهله عشان ما نطلعش إشعارات قديمة.
  static void handleSnapshot(QuerySnapshot<Map<String, dynamic>> snap, String userId) {
    if (_firstSnapshot) {
      _firstSnapshot = false;
      return;
    }
    for (final ch in snap.docChanges) {
      if (ch.type != DocumentChangeType.added) continue;
      final m = ch.doc.data();
      if (m == null || m['read'] == true) continue;
      final target = m['userId'];
      // إشعارات الأدوار (DRIVER...) بتتعامل معاها شاشة الكابتن (أونلاين بس)
      if (target != userId && target != 'ALL') continue;
      if (ch.doc.metadata.hasPendingWrites) continue;
      show(
        key: (m['key'] as String?) ?? 'n_${ch.doc.id}',
        title: (m['title'] as String?) ?? 'وصلها',
        body: (m['body'] as String?) ?? '',
      );
    }
  }

  static Future<void> stop() async {
    await _fcmSub?.cancel();
    _fcmSub = null;
    _startedFor = null;
  }

  /// كتابة إشعار داخل Firestore (بيظهر في شاشة الإشعارات، وبيوصل كـ Push
  /// عن طريق Cloud Function لو متفعّلة). مش بيفشّل العملية الأساسية لو فشل.
  static Future<void> notifyUser({
    required String userId,
    required String title,
    required String body,
    String type = 'INFO',
    String? key,
    String? orderId,
  }) async {
    try {
      await db.collection('notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        if (key != null) 'key': key,
        if (orderId != null) 'orderId': orderId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'read': false,
      });
    } catch (e) {
      debugPrint('notifyUser failed: $e');
    }
    // Push حقيقي والتطبيق مقفول (لو الـ relay متفعّل)
    unawaited(_relay(
      userId: userId,
      title: title,
      body: body,
      key: key,
      orderId: orderId,
    ));
  }

  /// Push جماعي (للمدير/المشغّل): الـ relay بيتأكد إن اللي بيبعت إدارة،
  /// وبيبعت لكل مستخدمي الأدوار المطلوبة (كل الكباتن مش الأونلاين بس).
  static Future<void> broadcastPush({
    required List<String> roles,
    required String title,
    required String body,
    required String key,
  }) async {
    if (pushRelayUrl.isEmpty) return;
    try {
      final idToken = await auth.currentUser?.getIdToken();
      if (idToken == null) return;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(Uri.parse(pushRelayUrl));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'idToken': idToken,
        'broadcast': true,
        'roles': roles,
        'title': title,
        'body': body,
        'key': key,
      }));
      final res = await req.close().timeout(const Duration(seconds: 90));
      await res.drain();
      client.close();
    } catch (e) {
      debugPrint('broadcast push failed: $e');
    }
  }

  static Future<void> _relay({
    required String userId,
    required String title,
    required String body,
    String? key,
    String? orderId,
  }) async {
    if (pushRelayUrl.isEmpty) return;
    try {
      final idToken = await auth.currentUser?.getIdToken();
      if (idToken == null) return;
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(Uri.parse(pushRelayUrl));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'idToken': idToken,
        'userId': userId,
        'title': title,
        'body': body,
        if (key != null) 'key': key,
        if (orderId != null) 'orderId': orderId,
      }));
      final res = await req.close().timeout(const Duration(seconds: 12));
      await res.drain();
      client.close();
    } catch (e) {
      debugPrint('push relay failed: $e');
    }
  }
}
