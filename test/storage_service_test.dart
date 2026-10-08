import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/services/storage_service.dart';

void main() {
  group('decodeImageDataUrl', () {
    test('صورة صالحة', () {
      final url = 'data:image/jpeg;base64,${base64Encode([1, 2, 3, 4])}';
      final img = decodeImageDataUrl(url);
      expect(img, isNotNull);
      expect(img!.mime, 'image/jpeg');
      expect(img.bytes, [1, 2, 3, 4]);
    });

    test('بيتجاهل المسافات وأسطر جديدة في الـ base64', () {
      final b64 = base64Encode(List<int>.generate(60, (i) => i));
      final url = 'data:image/png;base64,${b64.substring(0, 20)}\n${b64.substring(20)}';
      expect(decodeImageDataUrl(url)!.bytes.length, 60);
    });

    test('مش صورة / شكل غلط / فاضي = null', () {
      expect(decodeImageDataUrl('https://x.com/a.jpg'), isNull);
      expect(decodeImageDataUrl('data:text/plain;base64,AAAA'), isNull);
      expect(decodeImageDataUrl('data:image/jpeg,AAAA'), isNull);
      expect(decodeImageDataUrl('data:image/jpeg;base64,'), isNull);
      expect(decodeImageDataUrl('data:image/jpeg;base64,@@@'), isNull);
    });
  });
}
