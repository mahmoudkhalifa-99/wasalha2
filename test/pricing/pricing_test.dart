import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/config_constants.dart';
import 'package:wasalha/models/models.dart';
import 'package:wasalha/pricing.dart';

void main() {
  // (المحسوب, السعر النهائي للعميل, العمولة, مستحق الكابتن)
  const cases = <List<double>>[
    [15, 25, 5, 20],
    [20, 25, 5, 20],
    [25, 25, 5, 20],
    [50, 50, 5, 45],
    [100, 100, 5, 95],
  ];

  group('قواعد التسعير', () {
    for (final c in cases) {
      test('محسوب ${c[0].toInt()} ← نهائي ${c[1].toInt()} / صافي ${c[3].toInt()}',
          () {
        final fare = finalFare(c[0]);
        expect(fare, c[1]);
        expect(platformCommission, c[2]);
        expect(driverEarnings(fare), c[3]);
      });
    }

    test('العمولة ثابتة 5 مش نسبة، والحد الأدنى 25', () {
      expect(platformFeePerTrip, 5);
      expect(minTripFare, 25);
      expect(configDefaultPricing.minPrice, minTripFare);
    });

    test('نفس الحد الأدنى لكل أنواع المركبات (مفيش مضاعف بيقلل عنه)', () {
      for (final m in configDefaultPricing.multipliers.values) {
        // أقل سعر محسوب مهما كان المضاعف بيترفع لـ 25
        expect(finalFare(1 * m), 25);
      }
    });
  });

  group('tripFareOf', () {
    test('طلب مطعم: الصافي بعد استبعاد تمن الأصناف', () {
      final o = Order.fromMap({
        'customerId': 'c',
        'price': 150.0,
        'foodItems': [
          {'id': 'a', 'name': 'x', 'price': 60.0, 'quantity': 2}
        ],
      }, 'o1');
      expect(tripFareOf(o), 30); // 150 - 120
    });
  });
}
