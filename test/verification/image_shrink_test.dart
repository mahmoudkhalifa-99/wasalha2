import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wasalha/features/verification/domain/image_shrink.dart';

Uint8List _noisyJpeg(int w, int h, {int quality = 92}) {
  final rnd = math.Random(7);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: quality));
}

void main() {
  test('صورة كبيرة بتتصغّر لأقل من الحد وتفضل JPEG صالحة', () {
    final big = _noisyJpeg(2400, 1600);
    expect(big.length, greaterThan(kMaxStoredImageBytes));
    final out = shrinkJpegForFirestore(big);
    expect(out.length, lessThanOrEqualTo(kMaxStoredImageBytes));
    final d = img.decodeJpg(out);
    expect(d, isNotNull);
    expect(math.max(d!.width, d.height), lessThanOrEqualTo(1600));
  });

  test('صورة صغيرة أصلاً بترجع زي ما هي بنفس البايتات', () {
    final small = _noisyJpeg(400, 300, quality: 60);
    expect(small.length, lessThan(kMaxStoredImageBytes));
    expect(identical(shrinkJpegForFirestore(small), small), isTrue);
  });

  test('ملف مش JPEG: بيرمي FormatException', () {
    expect(() => shrinkJpegForFirestore(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()));
  });
}
