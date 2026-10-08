// مفتاح تشغيل/إيقاف التطبيق كله — بيتحكم فيه السوبر أدمن بس.
// الوثيقة: config/app = { enabled: bool, message: string, updatedAt, updatedBy }
// لو الوثيقة مش موجودة = التطبيق شغال.
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

class AppStatus {
  final bool enabled;
  final String message;
  const AppStatus({this.enabled = true, this.message = ''});

  static const on = AppStatus();

  static const defaultMessage =
      'التطبيق متوقف مؤقتاً للصيانة والتحديث. هنرجع لك في أقرب وقت، شكراً لصبرك.';
}

class AppStatusService {
  static DocumentReference<Map<String, dynamic>> get _ref =>
      db.collection('config').doc('app');

  /// بيتابع الحالة لحظياً. أي خطأ (مثلاً أوفلاين) = نعتبر التطبيق شغال
  /// عشان انقطاع النت ما يوقفش المستخدمين.
  static Stream<AppStatus> watch() {
    return _ref.snapshots().map((snap) {
      final d = snap.data();
      if (d == null) return AppStatus.on;
      return AppStatus(
        enabled: d['enabled'] != false,
        message: (d['message'] as String?)?.trim() ?? '',
      );
    }).handleError((_) {});
  }

  static Future<void> set({
    required bool enabled,
    required String message,
    required String adminId,
  }) {
    return _ref.set({
      'enabled': enabled,
      'message': message.trim(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'updatedBy': adminId,
    });
  }
}
