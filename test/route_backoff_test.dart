import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/utils.dart';

void main() {
  group('RouteBackoff', () {
    late DateTime now;
    late RouteBackoff b;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      b = RouteBackoff(clock: () => now);
    });

    test('من غير فشل: مفيش انتظار', () {
      expect(b.blocked, isFalse);
      expect(b.remaining, Duration.zero);
      expect(b.failures, 0);
    });

    test('التباعد بيتضاعف 10، 20، 40، 80، 160 ثم يثبت', () {
      final waits = <int>[];
      for (var i = 0; i < 7; i++) {
        waits.add(b.fail().inSeconds);
        now = now.add(const Duration(minutes: 10)); // نعدّي فترة الانتظار
      }
      expect(waits, [10, 20, 40, 80, 160, 160, 160]);
    });

    test('بيفضل محجوب لحد ما الوقت يعدّي', () {
      b.fail();
      expect(b.blocked, isTrue);
      expect(b.remaining, const Duration(seconds: 10));
      now = now.add(const Duration(seconds: 9));
      expect(b.blocked, isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(b.blocked, isFalse);
    });

    test('429 بيزوّد مرحلة', () {
      expect(b.fail(rateLimited: true), const Duration(seconds: 20));
    });

    test('النجاح والـ reset بيصفّروا العدّاد', () {
      b.fail();
      b.fail();
      b.succeed();
      expect(b.failures, 0);
      expect(b.blocked, isFalse);
      expect(b.fail(), const Duration(seconds: 10));
      b.reset();
      expect(b.blocked, isFalse);
    });
  });
}
