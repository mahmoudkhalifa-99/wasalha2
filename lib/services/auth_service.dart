import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_service.dart';

/// المستخدم قفل نافذة اختيار الحساب بنفسه.
class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
  @override
  String toString() => 'GoogleSignInCancelledException';
}

// Web client ID (client_type 3) من google-services.json — بيضمن إن idToken
// يرجع حتى لو الـ plugin ما ولّدش default_web_client_id.
const String _webClientId =
    '821734316791-v4n5r7slachnbfj51nnnbborae0r81jn.apps.googleusercontent.com';

final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: const ['email', 'profile'],
  serverClientId: _webClientId,
);

/// تسجيل الدخول بجوجل على الأندرويد بالطريقة الأصلية (Native).
///
/// بتظهر قايمة حسابات جوجل جوه التطبيق مباشرة من غير ما يفتح المتصفح، فمفيش
/// صفحة firebaseapp.com ولا خطأ "missing initial state" ولا اختيار حساب مرتين.
/// المطلوب: google-services.json محدّث + بصمة SHA-1 مسجلة في Firebase.
Future<UserCredential> signInWithGoogle() async {
  if (kIsWeb) {
    // الويب: نافذة جوجل من Firebase مباشرة (plugin الأندرويد مش مناسب هنا)
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters({'prompt': 'select_account'});
    return auth.signInWithPopup(provider);
  }
  // نخرّج الحساب السابق عشان قايمة الحسابات تظهر كل مرة
  try {
    await _googleSignIn.signOut();
  } catch (e) {
    debugPrint('google signOut before signIn failed: $e');
  }
  final account = await _googleSignIn.signIn();
  if (account == null) throw const GoogleSignInCancelledException();

  final g = await account.authentication;
  // لو idToken رجع null لأي سبب، Firebase بيقبل accessToken لوحده، فنكمل بيه
  // بدل ما نوقف تسجيل الدخول. بنفشل بس لو الاتنين مش موجودين.
  if (g.idToken == null && g.accessToken == null) {
    throw FirebaseAuthException(
      code: 'missing-id-token',
      message: 'جوجل ما رجّعش أي توكن (راجع Web client ID و SHA-1)',
    );
  }
  final credential = GoogleAuthProvider.credential(
    idToken: g.idToken,
    accessToken: g.accessToken,
  );
  return auth.signInWithCredential(credential);
}

/// إعادة تأكيد هوية مستخدم جوجل (مطلوبة قبل العمليات الحساسة زي حذف الحساب).
Future<void> reauthenticateWithGoogle() async {
  final user = auth.currentUser;
  if (user == null) {
    throw FirebaseAuthException(code: 'no-current-user');
  }
  if (kIsWeb) {
    await user.reauthenticateWithPopup(GoogleAuthProvider());
    return;
  }
  try {
    await _googleSignIn.signOut();
  } catch (e) {
    debugPrint('google signOut before reauth failed: $e');
  }
  final account = await _googleSignIn.signIn();
  if (account == null) throw const GoogleSignInCancelledException();
  final g = await account.authentication;
  if (g.idToken == null && g.accessToken == null) {
    throw FirebaseAuthException(code: 'missing-id-token');
  }
  await user.reauthenticateWithCredential(GoogleAuthProvider.credential(
    idToken: g.idToken,
    accessToken: g.accessToken,
  ));
}

/// هل الخطأ ده معناه إن المستخدم لغى شاشة جوجل بنفسه؟
bool isGoogleSignInCancelled(Object error) {
  if (error is GoogleSignInCancelledException) return true;
  if (error is PlatformException) {
    return error.code == 'sign_in_canceled' || error.code == 'canceled';
  }
  if (error is FirebaseAuthException) {
    return error.code == 'web-context-canceled' ||
        error.code == 'canceled' ||
        error.code == 'popup-closed-by-user' ||
        error.code == 'cancelled-popup-request';
  }
  return false;
}

/// كود مختصر للخطأ (للرسالة اللي بتظهر للمستخدم).
String googleSignInErrorCode(Object error) {
  if (error is FirebaseAuthException) return error.code;
  if (error is PlatformException) return error.code;
  return error.runtimeType.toString();
}
