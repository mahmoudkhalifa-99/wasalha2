import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// أكبر حجم لصورة المستند عشان تتخزّن جوه Firestore (حد الوثيقة 1 ميجا شامل
/// باقي الحقول). بنستهدف أقل من ده بهامش أمان.
const int kMaxStoredImageBytes = 700 * 1024;

/// الحد المطلق اللي القواعد (firestore.rules) بتقبله لحقل bytes.
const int kHardMaxStoredImageBytes = 900 * 1024;

/// بيصغّر JPEG (أبعاد/جودة) لحد ما يبقى أقل من [maxBytes]، مع الحفاظ على
/// وضوح كفاية لقراءة بطاقة الرقم القومي. لو الصورة أصلاً أصغر بيرجّعها زي ما هي.
/// دالة top-level عشان تشتغل مع `compute` (خارج الـ UI thread).
Uint8List shrinkJpegForFirestore(Uint8List bytes) =>
    shrinkJpeg(bytes, maxBytes: kMaxStoredImageBytes);

Uint8List shrinkJpeg(
  Uint8List bytes, {
  required int maxBytes,
  int startSide = 1600,
}) {
  // مكتبة image ممكن ترمي استثناء مع ملف تالف (مش بس ترجّع null).
  img.Image? decoded;
  try {
    decoded = img.decodeJpg(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('الصورة مش JPEG صالحة');
  }
  final longSide = math.max(decoded.width, decoded.height);
  if (bytes.length <= maxBytes && longSide <= startSide) return bytes;

  Uint8List? best;
  for (final side in [startSide, 1400, 1200, 1000, 800]) {
    final target = longSide > side
        ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: side)
            : img.copyResize(decoded, height: side))
        : decoded;
    for (final q in [80, 70, 60, 50]) {
      final out = Uint8List.fromList(img.encodeJpg(target, quality: q));
      if (best == null || out.length < best.length) best = out;
      if (out.length <= maxBytes) return out;
    }
  }
  // مفيش تركيبة وصلت للحد: نرجّع أصغر نسخة (والقواعد هترفضها لو عدّت الحد المطلق).
  return best!;
}
