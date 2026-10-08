import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/push_config.dart';
import 'firebase_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Browser background push is handled by Firebase Messaging's web service worker.
}

class NotificationService {
  NotificationService._();

  static StreamSubscription<RemoteMessage>? _fcmSub;
  static String? _startedFor;
  static bool _firstSnapshot = true;

  static Future<void> init() async {}

  static Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Web notification permission failed: $e');
      return false;
    }
  }

  static Future<void> show({
    required String key,
    required String title,
    required String body,
  }) async {
    // On Web, foreground/background browser notifications are owned by FCM.
  }

  static Future<void> showFromRemote(RemoteMessage message) async {
    // Browser FCM service worker displays notification messages.
  }

  static Future<void> startFor(String userId, String roleValue) async {
    if (_startedFor == userId && _fcmSub != null) return;
    await stop();
    _startedFor = userId;
    try {
      _fcmSub = FirebaseMessaging.onMessage.listen(showFromRemote);
    } catch (e) {
      debugPrint('Web FCM listener failed: $e');
    }
    _firstSnapshot = true;
  }

  static void handleSnapshot(
      QuerySnapshot<Map<String, dynamic>> snap, String userId) {
    if (_firstSnapshot) {
      _firstSnapshot = false;
      return;
    }
    // The notification center itself reads Firestore. No local notification
    // is generated here on Web; browser push is handled by FCM.
  }

  static Future<void> stop() async {
    await _fcmSub?.cancel();
    _fcmSub = null;
    _startedFor = null;
  }

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
    unawaited(_relay(
      userId: userId,
      title: title,
      body: body,
      key: key,
      orderId: orderId,
    ));
  }

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
      final response = await _postRelay({
        'idToken': idToken,
        'broadcast': true,
        'roles': roles,
        'title': title,
        'body': body,
        'key': key,
      });
      debugPrint('Web push relay: ${response.statusCode}');
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
      final response = await _postRelay({
        'idToken': idToken,
        'userId': userId,
        'title': title,
        'body': body,
        if (key != null) 'key': key,
        if (orderId != null) 'orderId': orderId,
      });
      debugPrint('Web push relay: ${response.statusCode}');
    } catch (e) {
      debugPrint('push relay failed: $e');
    }
  }

  static Future<http.Response> _postRelay(Map<String, dynamic> payload) {
    return http.post(
      Uri.parse(pushRelayUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 20));
  }
}
