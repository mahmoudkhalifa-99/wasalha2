import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/captain_accounts/domain/captain_accounts.dart';
import 'package:wasalha/models/models.dart' show OrderStatus;

int ms(int y, int m, int d, [int h = 12]) =>
    DateTime(y, m, d, h).millisecondsSinceEpoch;

TripRow trip(String id, String? driver, OrderStatus st, double price, int at) =>
    TripRow(orderId: id, driverId: driver, status: st, price: price, atMs: at);

void main() {
  group('rangeFor', () {
    final now = DateTime(2026, 10, 5, 14, 30);

    test('هذا الشهر: من أول الشهر لأول الشهر اللي بعده', () {
      final r = rangeFor(PeriodPreset.thisMonth, now);
      expect(r.start, DateTime(2026, 10, 1));
      expect(r.end, DateTime(2026, 11, 1));
    });

    test('الشهر الماضي، وفي يناير بيرجع لديسمبر السنة اللي فاتت', () {
      expect(rangeFor(PeriodPreset.lastMonth, now),
          DateRange(DateTime(2026, 9, 1), DateTime(2026, 10, 1)));
      final jan = DateTime(2026, 1, 10);
      expect(rangeFor(PeriodPreset.lastMonth, jan),
          DateRange(DateTime(2025, 12, 1), DateTime(2026, 1, 1)));
    });

    test('ديسمبر: نهاية "هذا الشهر" هي أول يناير', () {
      expect(rangeFor(PeriodPreset.thisMonth, DateTime(2026, 12, 20)).end,
          DateTime(2027, 1, 1));
    });

    test('آخر 30 يوم: 30 يوم كاملة تشمل النهارده', () {
      final r = rangeFor(PeriodPreset.last30Days, now);
      expect(r.start, DateTime(2026, 9, 6));
      expect(r.end, DateTime(2026, 10, 6));
      expect(r.end.difference(r.start).inDays, 30);
    });

    test('فترة مخصصة: شاملة آخر يوم، وبتتصلّح لو الترتيب معكوس', () {
      final r = rangeFor(PeriodPreset.custom, now,
          customFirstDay: DateTime(2026, 10, 3, 9),
          customLastDay: DateTime(2026, 10, 1, 22));
      expect(r.start, DateTime(2026, 10, 1));
      expect(r.end, DateTime(2026, 10, 4));
    });

    test('حدود containsMs: البداية شاملة والنهاية غير شاملة', () {
      final r = DateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      expect(r.containsMs(r.startMs), isTrue);
      expect(r.containsMs(r.endMs - 1), isTrue);
      expect(r.containsMs(r.endMs), isFalse);
      expect(r.containsMs(r.startMs - 1), isFalse);
    });
  });

  group('buildCaptainStats', () {
    final range = DateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1));

    test('بيعدّ المشاوير المكتملة ويجمع الأجرة لكل كابتن', () {
      final stats = buildCaptainStats([
        trip('1', 'a', OrderStatus.delivered, 50, ms(2026, 10, 2)),
        trip('2', 'a', OrderStatus.delivered, 70, ms(2026, 10, 9)),
        trip('3', 'b', OrderStatus.delivered, 100, ms(2026, 10, 3)),
      ], range);
      final a = stats.firstWhere((s) => s.driverId == 'a');
      final b = stats.firstWhere((s) => s.driverId == 'b');
      expect(a.deliveredCount, 2);
      expect(a.totalFares, 120);
      expect(a.averageFare, 60);
      expect(b.deliveredCount, 1);
      expect(b.totalFares, 100);
    });

    test('الطلبات خارج الفترة وبدون كابتن والغير مكتملة متتحسبش', () {
      final stats = buildCaptainStats([
        trip('1', 'a', OrderStatus.delivered, 50, ms(2026, 9, 30)), // قبل الفترة
        trip('2', 'a', OrderStatus.delivered, 50, ms(2026, 11, 1, 0)), // بعد الفترة (نهاية غير شاملة)
        trip('3', null, OrderStatus.delivered, 50, ms(2026, 10, 5)), // من غير كابتن
        trip('4', '', OrderStatus.delivered, 50, ms(2026, 10, 5)), // كابتن فاضي
        trip('5', 'a', OrderStatus.pending, 50, ms(2026, 10, 5)),
        trip('6', 'a', OrderStatus.assigned, 50, ms(2026, 10, 5)),
        trip('7', 'a', OrderStatus.picked, 50, ms(2026, 10, 5)),
        trip('8', 'a', OrderStatus.inDelivery, 50, ms(2026, 10, 5)),
        trip('9', 'a', OrderStatus.draft, 50, ms(2026, 10, 5)),
      ], range);
      expect(stats, isEmpty);
    });

    test('الإلغاء بعد التعيين بيتعدّ للمتابعة فقط ومش داخل في الأجرة', () {
      final stats = buildCaptainStats([
        trip('1', 'a', OrderStatus.delivered, 40, ms(2026, 10, 2)),
        trip('2', 'a', OrderStatus.cancelled, 999, ms(2026, 10, 3)),
        trip('3', 'c', OrderStatus.cancelled, 60, ms(2026, 10, 4)),
      ], range);
      final a = stats.firstWhere((s) => s.driverId == 'a');
      expect(a.deliveredCount, 1);
      expect(a.totalFares, 40);
      expect(a.cancelledAfterAssign, 1);
      final c = stats.firstWhere((s) => s.driverId == 'c');
      expect(c.deliveredCount, 0);
      expect(c.totalFares, 0);
      expect(c.averageFare, 0); // من غير قسمة على صفر
      expect(c.cancelledAfterAssign, 1);
    });

    test('الترتيب: الأكتر مشاوير أولًا، والمشاوير جوه الكابتن الأحدث أولًا', () {
      final stats = buildCaptainStats([
        trip('1', 'a', OrderStatus.delivered, 10, ms(2026, 10, 2)),
        trip('2', 'b', OrderStatus.delivered, 10, ms(2026, 10, 2)),
        trip('3', 'b', OrderStatus.delivered, 10, ms(2026, 10, 8)),
        trip('4', 'b', OrderStatus.delivered, 10, ms(2026, 10, 5)),
      ], range);
      expect(stats.map((s) => s.driverId), ['b', 'a']);
      expect(stats.first.delivered.map((t) => t.orderId), ['3', '4', '2']);
    });

    test('مفيش طلبات = قائمة فاضية', () {
      expect(buildCaptainStats(const [], range), isEmpty);
    });
  });

  group('feeDue', () {
    test('عدد المشاوير × رسوم المشوار', () {
      expect(feeDue(10, 5), 50);
      expect(feeDue(1, 5), 5);
      expect(feeDue(240, 5), 1200);
    });

    test('رسوم بكسور بتتقرّب لأقرب قرش', () {
      expect(feeDue(3, 2.5), 7.5);
      expect(feeDue(3, 3.333), 10.0); // 9.999 → 10.00
    });

    test('صفر أو سالب = صفر', () {
      expect(feeDue(0, 5), 0);
      expect(feeDue(10, 0), 0);
      expect(feeDue(-2, 5), 0);
      expect(feeDue(10, -1), 0);
    });

    test('الرسوم مش بتعتمد على سعر المشوار', () {
      final range = DateRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      final stats = buildCaptainStats([
        trip('1', 'a', OrderStatus.delivered, 20, ms(2026, 10, 5)),
        trip('2', 'a', OrderStatus.delivered, 500, ms(2026, 10, 6)),
      ], range);
      expect(stats.single.deliveredCount, 2);
      expect(feeDue(stats.single.deliveredCount, kDefaultFeePerTrip), 10);
    });
  });

  group('parseFee', () {
    test('أرقام عادية وعشرية', () {
      expect(parseFee('5'), 5);
      expect(parseFee('2.5'), 2.5);
      expect(parseFee(' 7 '), 7);
    });

    test('أرقام عربية وفاصلة عربية/إنجليزية', () {
      expect(parseFee('٥'), 5);
      expect(parseFee('٢٫٥'), 2.5);
      expect(parseFee('2,5'), 2.5);
      expect(parseFee('5 ج.م'), 5);
    });

    test('بره 0..1000 أو فاضي أو مش رقم = null', () {
      expect(parseFee(''), isNull);
      expect(parseFee('abc'), isNull);
      expect(parseFee('1001'), isNull);
      expect(parseFee('-5'), isNull); // السالب مرفوض (مش بيتحوّل لموجب)
      expect(parseFee('1.2.3'), isNull);
    });

    test('الحدود 0 و1000 مقبولة', () {
      expect(parseFee('0'), 0);
      expect(parseFee('1000'), 1000);
    });
  });

  group('التنسيق', () {
    test('formatMoney: صحيح من غير كسور، وإلا خانتين، وفاصل آلاف', () {
      expect(formatMoney(1250), '1,250');
      expect(formatMoney(1250.5), '1,250.50');
      expect(formatMoney(0), '0');
      expect(formatMoney(41.63), '41.63');
    });

    test('رسوم المشوار الافتراضية = 5 جنيه', () {
      expect(kDefaultFeePerTrip, 5);
    });
  });
}
