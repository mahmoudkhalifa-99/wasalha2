// إعدادات Firebase — نفس مشروع نسخة الويب (sada-51292).
//
// مهم: القيم الخاصة بأندرويد (appId) لازم تتاخد من ملف google-services.json
// بتاع تطبيق الأندرويد (com.wasalah.app) من Firebase Console، أو ببساطة تشغّل:
//     flutterfire configure --project=sada-51292
// وده هيستبدل الملف ده تلقائياً. القيم تحت للمشروع نفسه وتشتغل كبداية،
// لكن appId الحقيقي للأندرويد مختلف عن الويب.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDlfpN0JCsmpCKdTyb4ZX_QN0sZbypIv48',
    appId: '1:821734316791:web:a41030678e2ecaa168d1f2',
    messagingSenderId: '821734316791',
    projectId: 'sada-51292',
    authDomain: 'sada-51292.firebaseapp.com',
    databaseURL: 'https://sada-51292-default-rtdb.firebaseio.com',
    storageBucket: 'sada-51292.firebasestorage.app',
    measurementId: 'G-XZMSDBYW43',
  );

  // تطبيق الأندرويد المسجّل في Firebase: com.wasalah.app
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDlfpN0JCsmpCKdTyb4ZX_QN0sZbypIv48',
    appId: '1:821734316791:android:aa1ab6b3f528af7868d1f2',
    messagingSenderId: '821734316791',
    projectId: 'sada-51292',
    storageBucket: 'sada-51292.firebasestorage.app',
  );
}
