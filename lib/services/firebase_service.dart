// نسخة Dart من services/firebase.ts
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

FirebaseAuth get auth => FirebaseAuth.instance;
FirebaseFirestore get db => FirebaseFirestore.instance;

/// تهيئة Firebase + إعدادات Firestore (تخزين محلي مفعّل زي نسخة الويب).
Future<void> initFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
}

enum OperationType { create, update, delete, list, get, write }

/// نفس handleFirestoreError: بيسجّل سياق الخطأ ثم يرمي الاستثناء.
Never handleFirestoreError(
    Object error, OperationType operationType, String? path) {
  final u = auth.currentUser;
  final info = {
    'error': error.toString(),
    'authInfo': {
      'userId': u?.uid,
      'email': u?.email,
      'emailVerified': u?.emailVerified,
      'isAnonymous': u?.isAnonymous,
      'providerInfo': (u?.providerData ?? [])
          .map((p) => {'providerId': p.providerId, 'email': p.email})
          .toList(),
    },
    'operationType': operationType.name,
    'path': path,
  };
  // ignore: avoid_print
  print('Firestore Security Error Context: ${jsonEncode(info)}');
  throw Exception(jsonEncode(info));
}

/// نص خطأ مختصر للمستخدم (من غير بيانات الحساب اللي بيضيفها handleFirestoreError).
String friendlyError(Object e) {
  var t = e.toString().replaceFirst('Exception: ', '');
  try {
    final m = jsonDecode(t);
    if (m is Map && m['error'] != null) {
      t = m['error'].toString().replaceFirst('Exception: ', '');
    }
  } catch (_) {
    // النص مش JSON، نستخدمه زي ما هو
  }
  if (t.contains('permission-denied')) {
    t = 'مفيش صلاحية لتنفيذ العملية (راجع قواعد Firestore)';
  } else if (t.contains('firebase_storage/object-not-found') ||
      t.contains('firebase_storage/bucket-not-found') ||
      t.contains('firebase_storage/project-not-found')) {
    // الرسالة الأصلية ("No object exists...") مضللة: في الرفع معناها غالبًا إن
    // الـ bucket نفسه مش موجود/مش مفعّل، مش إن ملف ناقص.
    t = 'تعذّر رفع الصورة: خدمة تخزين الصور (Firebase Storage) غير مفعّلة أو '
        'مش متاحة للمشروع. تواصل مع الإدارة. (firebase_storage/object-not-found)';
  } else if (t.contains('firebase_storage/unauthorized')) {
    t = 'مفيش صلاحية لرفع الصورة (راجع قواعد Storage). (firebase_storage/unauthorized)';
  } else if (t.contains('firebase_storage/unauthenticated')) {
    t = 'سجّل الدخول من جديد وحاول تاني. (firebase_storage/unauthenticated)';
  } else if (t.contains('firebase_storage/retry-limit-exceeded') ||
      t.contains('firebase_storage/canceled')) {
    t = 'الاتصال ضعيف وفشل رفع الصورة، حاول تاني.';
  } else if (t.contains('firebase_storage/quota-exceeded')) {
    t = 'تم تجاوز حصة التخزين المتاحة للمشروع. تواصل مع الإدارة. (firebase_storage/quota-exceeded)';
  }
  return t;
}
