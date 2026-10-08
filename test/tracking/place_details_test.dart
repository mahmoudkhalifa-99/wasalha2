import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/tracking/services/geocoding_service.dart';

void main() {
  test('قرية مش في القوائم: الاسم الفعلي والمركز بيتقروا زي ما هم', () {
    final d = NominatimGeocodingService.parseDetails({
      'address': {
        'road': 'شارع المدرسة',
        'village': 'طملاي',
        'county': 'مركز منوف',
        'state': 'محافظة المنوفية',
      },
    }, 'x');
    expect(d.locality, 'طملاي');
    expect(d.area, 'مركز منوف');
    expect(d.road, 'شارع المدرسة');
  });

  test('من غير address: كله null ومفيش استثناء', () {
    final d = NominatimGeocodingService.parseDetails({}, null);
    expect(d.locality, isNull);
    expect(d.area, isNull);
    expect(d.road, isNull);
  });
}
