// حذف حساب المستخدم من جوه التطبيق (متطلب Google Play).
//
// بيتمسح: حساب الدخول (Firebase Auth) + وثيقة المستخدم + موقع الكابتن الحي.
// بيفضل (سجلات مالية/قانونية): الطلبات القديمة، التقييمات، المعاملات، وملف توثيق
// الكابتن (القواعد بتمنع حذفه، والمسح منه من الكونسول حسب السياسة القانونية).
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/models.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

class AccountDeletion {
  /// بيتفعّل وقت الحذف عشان AppShell ما يعيدش إنشاء وثيقة المستخدم
  /// اللي لسه ماسحينها (بيعتبرها حساب ناقص ويعمله وثيقة جديدة).
  static bool inProgress = false;

  static bool get usesPassword =>
      auth.currentUser?.providerData.any((p) => p.providerId == 'password') ??
      false;

  /// عنده طلب شغال (عميل أو كابتن)؟ ما ينفعش يحذف حسابه وفيه طلب لسه ماخلصش.
  static Future<bool> hasActiveOrders(AppUser u) async {
    const finished = {'DELIVERED', 'CANCELLED', 'DRAFT'};
    Future<bool> check(String field) async {
      final snap =
          await db.collection('orders').where(field, isEqualTo: u.id).get();
      return snap.docs
          .any((d) => !finished.contains((d.data()['status'] ?? '').toString()));
    }

    if (u.role == UserRole.driver) return check('driverId');
    return check('customerId');
  }

  /// [password] مطلوب لحسابات الإيميل/الباسورد. حسابات جوجل بتطلب تأكيد جوجل.
  /// بيرمي FirebaseAuthException أو GoogleSignInCancelledException.
  static Future<void> delete(AppUser u, {String? password}) async {
    final user = auth.currentUser;
    if (user == null || user.uid != u.id) {
      throw fb.FirebaseAuthException(code: 'no-current-user');
    }
    if (u.role == UserRole.admin) {
      throw fb.FirebaseAuthException(
          code: 'admin-not-deletable',
          message: 'حساب السوبر أدمن ما ينفعش يتحذف من التطبيق');
    }

    // 1) إعادة تأكيد الهوية الأول (لو فشلت ما اتمسحش أي حاجة)
    if (usesPassword) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw fb.FirebaseAuthException(code: 'wrong-password');
      }
      await user.reauthenticateWithCredential(
          fb.EmailAuthProvider.credential(email: email, password: password));
    } else {
      await reauthenticateWithGoogle();
    }

    inProgress = true;
    try {
      // 2) بيانات Firestore (الموقع الحي ممكن مايكونش موجود)
      try {
        await db.collection('driver_locations').doc(u.id).delete();
      } catch (e) {
        debugPrint('delete driver_locations skipped: $e');
      }
      await db.collection('users').doc(u.id).delete();

      // 3) حساب الدخول نفسه — بعده الـ SDK بيعمل signOut تلقائي
      await user.delete();
    } finally {
      inProgress = false;
    }
  }
}
