import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'verification_enums.dart';

/// نتيجة فحص جودة صورة. ده فحص جودة تصوير فقط (دقة/وضوح/إضاءة/انعكاس).
/// مش فحص أصالة ولا كشف تزوير. العتبات تقديرية ولازم تتضبط على كاميرات حقيقية.
class QualityReport {
  final int width;
  final int height;
  final double sharpness; // تباين Laplacian (أعلى = أوضح)
  final double brightness; // 0..255
  final double glareRatio; // نسبة البكسلات المحروقة
  final double darkRatio;
  final double aspectRatio;
  final List<String> failures; // أسباب تمنع الإرسال
  final List<String> warnings; // مؤشرات للمراجع، ما بتمنعش

  const QualityReport({
    required this.width,
    required this.height,
    required this.sharpness,
    required this.brightness,
    required this.glareRatio,
    required this.darkRatio,
    required this.aspectRatio,
    required this.failures,
    required this.warnings,
  });

  bool get passed => failures.isEmpty;

  CheckResult get result => failures.isNotEmpty
      ? CheckResult.fail
      : (warnings.isNotEmpty ? CheckResult.warn : CheckResult.pass);

  Map<String, dynamic> toMap() => {
        'w': width,
        'h': height,
        'sharpness': double.parse(sharpness.toStringAsFixed(1)),
        'brightness': double.parse(brightness.toStringAsFixed(1)),
        'glare': double.parse(glareRatio.toStringAsFixed(4)),
        'dark': double.parse(darkRatio.toStringAsFixed(4)),
        'aspect': double.parse(aspectRatio.toStringAsFixed(3)),
        'result': result.value,
        'failures': failures,
        'warnings': warnings,
      };
}

/// عتبات الفحص (تقديرية).
class QualityThresholds {
  final int minLongSide;
  final double blurFail;
  final double blurWarn;
  final double darkFail;
  final double brightFail;
  final double glareFail;
  final double glareWarn;
  final double aspectTolerance;

  const QualityThresholds({
    this.minLongSide = 900,
    this.blurFail = 30,
    this.blurWarn = 60,
    this.darkFail = 50,
    this.brightFail = 215,
    this.glareFail = 0.06,
    this.glareWarn = 0.025,
    this.aspectTolerance = 0.15,
  });

  /// صور شخصية: دقة أقل مقبولة.
  static const selfie = QualityThresholds(minLongSide: 600);
}

/// نسبة أبعاد بطاقة الهوية (ID-1: 85.6 × 54 مم).
const double kCardAspect = 1.586;

/// رسالة الفشل الموحدة للمستخدم.
const String kRetakeMessage = 'الصورة غير واضحة، يرجى إعادة التصوير.';

const Map<String, String> kQualityFailureLabels = {
  'LOW_RESOLUTION': 'دقة الصورة منخفضة',
  'BLURRY': 'الصورة مهزوزة أو غير واضحة',
  'TOO_DARK': 'الصورة مظلمة جدًا',
  'TOO_BRIGHT': 'الصورة شديدة السطوع',
  'GLARE': 'يوجد انعكاس ضوء على المستند',
  'DECODE_FAILED': 'تعذر قراءة الصورة',
};

class _Args {
  final Uint8List bytes;
  final bool expectCardAspect;
  final QualityThresholds t;
  const _Args(this.bytes, this.expectCardAspect, this.t);
}

/// تحليل متزامن (للاختبارات ولأي سياق بدون UI).
QualityReport analyzeImageQualitySync(
  Uint8List bytes, {
  bool expectCardAspect = false,
  QualityThresholds thresholds = const QualityThresholds(),
}) {
  // مكتبة image ممكن ترمي استثناء (مش بترجّع null بس) مع ملف تالف/قصير جدًا،
  // مثلاً RangeError من فاحص PSD. أي فشل في القراءة = DECODE_FAILED.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return const QualityReport(
        width: 0,
        height: 0,
        sharpness: 0,
        brightness: 0,
        glareRatio: 0,
        darkRatio: 0,
        aspectRatio: 0,
        failures: ['DECODE_FAILED'],
        warnings: []);
  }
  final w = decoded.width;
  final h = decoded.height;
  final failures = <String>[];
  final warnings = <String>[];

  if (math.max(w, h) < thresholds.minLongSide) failures.add('LOW_RESOLUTION');

  // نصغّر لـ 480 عرض: أسرع وبيثبّت مقياس الوضوح.
  final small = w > 480 ? img.copyResize(decoded, width: 480) : decoded;
  final sw = small.width;
  final sh = small.height;
  final gray = Float64List(sw * sh);
  var sum = 0.0;
  var glare = 0;
  var dark = 0;
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      final p = small.getPixel(x, y);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      gray[y * sw + x] = l;
      sum += l;
      if (l >= 250) glare++;
      if (l <= 25) dark++;
    }
  }
  final n = sw * sh;
  final mean = sum / n;

  // تباين Laplacian: مقياس معروف للوضوح.
  var lapSum = 0.0;
  var lapSq = 0.0;
  var cnt = 0;
  for (var y = 1; y < sh - 1; y++) {
    for (var x = 1; x < sw - 1; x++) {
      final i = y * sw + x;
      final lap = 4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - sw] - gray[i + sw];
      lapSum += lap;
      lapSq += lap * lap;
      cnt++;
    }
  }
  final lapMean = cnt == 0 ? 0 : lapSum / cnt;
  final sharp = cnt == 0 ? 0.0 : (lapSq / cnt - lapMean * lapMean).toDouble();

  final glareRatio = glare / n;
  final darkRatio = dark / n;

  if (sharp < thresholds.blurFail) {
    failures.add('BLURRY');
  } else if (sharp < thresholds.blurWarn) {
    warnings.add('BLUR_BORDERLINE');
  }
  if (mean < thresholds.darkFail) {
    failures.add('TOO_DARK');
  } else if (mean < thresholds.darkFail + 20) {
    warnings.add('DARK_BORDERLINE');
  }
  if (mean > thresholds.brightFail) {
    failures.add('TOO_BRIGHT');
  } else if (mean > thresholds.brightFail - 25) {
    warnings.add('BRIGHT_BORDERLINE');
  }
  if (glareRatio > thresholds.glareFail) {
    failures.add('GLARE');
  } else if (glareRatio > thresholds.glareWarn) {
    warnings.add('GLARE_BORDERLINE');
  }

  final aspect = w >= h ? w / h : h / w;
  if (expectCardAspect &&
      (aspect - kCardAspect).abs() / kCardAspect > thresholds.aspectTolerance) {
    warnings.add('ASPECT_OFF');
  }

  return QualityReport(
    width: w,
    height: h,
    sharpness: sharp,
    brightness: mean,
    glareRatio: glareRatio,
    darkRatio: darkRatio,
    aspectRatio: aspect,
    failures: failures,
    warnings: warnings,
  );
}

QualityReport _run(_Args a) => analyzeImageQualitySync(a.bytes,
    expectCardAspect: a.expectCardAspect, thresholds: a.t);

/// نفس التحليل بس في Isolate عشان الواجهة ما تهنجش.
Future<QualityReport> analyzeImageQuality(
  Uint8List bytes, {
  bool expectCardAspect = false,
  QualityThresholds thresholds = const QualityThresholds(),
}) =>
    compute(_run, _Args(bytes, expectCardAspect, thresholds));
