import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wasalha/features/verification/domain/image_quality.dart';
import 'package:wasalha/features/verification/domain/verification_enums.dart';

/// صورة اختبار: شطرنج بمربعات [cell] بين لونين رماديين.
Uint8List _checker(int w, int h, {int a = 80, int b = 170, int cell = 20}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = ((x ~/ cell) + (y ~/ cell)) % 2 == 0 ? a : b;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

Uint8List _flat(int w, int h, int v) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(v, v, v));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('صورة واضحة ومتوازنة: PASS', () {
    final r = analyzeImageQualitySync(_checker(1200, 760));
    expect(r.failures, isEmpty, reason: '${r.toMap()}');
    expect(r.passed, isTrue);
    expect(r.result, CheckResult.pass);
  });

  test('صورة مهزوزة (لون واحد): BLURRY', () {
    final r = analyzeImageQualitySync(_flat(1200, 760, 128));
    expect(r.failures, contains('BLURRY'));
    expect(r.passed, isFalse);
  });

  test('دقة منخفضة: LOW_RESOLUTION', () {
    final r = analyzeImageQualitySync(_checker(400, 300, cell: 10));
    expect(r.failures, contains('LOW_RESOLUTION'));
  });

  test('الصورة الشخصية عتبة الدقة أقل', () {
    final bytes = _checker(700, 520);
    expect(analyzeImageQualitySync(bytes).failures, contains('LOW_RESOLUTION'));
    expect(analyzeImageQualitySync(bytes, thresholds: QualityThresholds.selfie).failures,
        isNot(contains('LOW_RESOLUTION')));
  });

  test('مظلمة جدًا: TOO_DARK', () {
    final r = analyzeImageQualitySync(_checker(1200, 760, a: 5, b: 40));
    expect(r.failures, contains('TOO_DARK'));
  });

  test('شديدة السطوع: TOO_BRIGHT', () {
    final r = analyzeImageQualitySync(_checker(1200, 760, a: 215, b: 245));
    expect(r.failures, contains('TOO_BRIGHT'));
  });

  test('انعكاس (مساحات محروقة كبيرة): GLARE', () {
    final r = analyzeImageQualitySync(_checker(1200, 760, a: 80, b: 255));
    expect(r.failures, contains('GLARE'));
  });

  test('نسبة أبعاد غير مناسبة لبطاقة: تنبيه ASPECT_OFF فقط (مش رفض)', () {
    final bytes = _checker(1200, 1200);
    final r = analyzeImageQualitySync(bytes, expectCardAspect: true);
    expect(r.warnings, contains('ASPECT_OFF'));
    expect(r.passed, isTrue);
    expect(r.result, CheckResult.warn);
    expect(analyzeImageQualitySync(bytes).warnings, isNot(contains('ASPECT_OFF')));
  });

  test('بطاقة بنسبة صحيحة: بدون ASPECT_OFF', () {
    final r = analyzeImageQualitySync(_checker(1200, 757), expectCardAspect: true);
    expect(r.warnings, isNot(contains('ASPECT_OFF')));
  });

  test('ملف مش صورة: DECODE_FAILED', () {
    final r = analyzeImageQualitySync(Uint8List.fromList([1, 2, 3, 4]));
    expect(r.failures, contains('DECODE_FAILED'));
    expect(r.passed, isFalse);
  });

  test('رسالة إعادة التصوير الموحدة', () {
    expect(kRetakeMessage, 'الصورة غير واضحة، يرجى إعادة التصوير.');
  });

  test('toMap بيحمل النتيجة والأسباب (بيتخزن مع المستند)', () {
    final m = analyzeImageQualitySync(_flat(1200, 760, 128)).toMap();
    expect(m['result'], 'FAIL');
    expect(m['failures'], contains('BLURRY'));
  });
}
