import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// صورة مفكوكة من data URL.
class DecodedImage {
  const DecodedImage(this.mime, this.bytes);
  final String mime;
  final Uint8List bytes;
}

/// يفك `data:image/jpeg;base64,...` ويرجّع النوع والبايتات، أو null لو الشكل غلط
/// أو مش صورة.
DecodedImage? decodeImageDataUrl(String dataUrl) {
  if (!dataUrl.startsWith('data:image/')) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  final header = dataUrl.substring(5, comma); // بعد "data:"
  if (!header.contains(';base64')) return null;
  final mime = header.split(';').first;
  try {
    final bytes = base64Decode(
        dataUrl.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
    if (bytes.isEmpty) return null;
    return DecodedImage(mime, bytes);
  } catch (_) {
    return null;
  }
}

/// رفع الملفات على Firebase Storage.
class StorageService {
  StorageService._();

  /// أكبر حجم (حروف base64) نقبل نخزنه جوه وثيقة الطلب لو الرفع فشل.
  /// حد وثيقة Firestore 1 ميجا، وباقي الوثيقة (أصناف/عناوين/تاريخ) محتاج مساحة.
  static const int maxInlineChars = 700 * 1024;

  /// يرفع صورة روشتة (data URL) على `prescriptions/{uid}/...` ويرجّع رابط التحميل.
  /// بيرمي استثناء لو الصورة غير صالحة أو الرفع فشل/اتأخر.
  static Future<String> uploadPrescription({
    required String uid,
    required String dataUrl,
    FirebaseStorage? storage,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final img = decodeImageDataUrl(dataUrl);
    if (img == null) throw const FormatException('invalid image data URL');
    final ext = img.mime.contains('png') ? 'png' : 'jpg';
    final ref = (storage ?? FirebaseStorage.instance)
        .ref('prescriptions/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext');
    final task = ref.putData(img.bytes, SettableMetadata(contentType: img.mime));
    try {
      await task.timeout(timeout);
    } on TimeoutException {
      await task.cancel();
      rethrow;
    }
    return ref.getDownloadURL();
  }
}
