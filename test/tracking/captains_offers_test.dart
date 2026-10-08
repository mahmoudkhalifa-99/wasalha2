import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/models/tracking_models.dart';
import 'package:wasalha/models/models.dart';
import 'package:wasalha/widgets/captains_offers_map.dart';

Order _order({
  String category = 'TAXI',
  String? restaurantId,
  Map<String, dynamic>? pickup = const {'address': 'x', 'lat': 30.5, 'lng': 31.0},
  Map<String, dynamic>? dropoff = const {'address': 'y', 'lat': 30.6, 'lng': 31.1},
}) =>
    Order.fromMap({
      'id': 'o1',
      'customerId': 'c',
      'category': category,
      'status': 'PENDING',
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (pickup != null) 'pickup': pickup,
      if (dropoff != null) 'dropoff': dropoff,
    });

Offer _offer(String driverId, double price) => Offer.fromMap({
      'id': 'of_$driverId',
      'orderId': 'o1',
      'driverId': driverId,
      'driverName': 'كابتن $driverId',
      'price': price,
    });

GeoFix _fix(double lat, double lng) =>
    GeoFix(position: LatLng(lat, lng), updatedAt: DateTime.now());

void main() {
  group('نقطة المرجع لحساب الأقرب', () {
    test('مشوار: نقطة الاستلام', () {
      expect(offersReferencePoint(_order()), const LatLng(30.5, 31.0));
    });

    test('مطعم من القائمة: موقع المطعم', () {
      final o = _order(category: 'FOOD', restaurantId: 'r1');
      expect(offersReferencePoint(o), const LatLng(30.5, 31.0));
    });

    test('صيدلية: موقع العميل (إحداثيات الاستلام تقريبية)', () {
      final o = _order(category: 'PHARMACY');
      expect(offersReferencePoint(o), const LatLng(30.6, 31.1));
    });

    test('طلب مطعم يدوي (من غير restaurantId): موقع العميل', () {
      final o = _order(category: 'FOOD');
      expect(offersReferencePoint(o), const LatLng(30.6, 31.1));
    });

    test('إحداثيات صفر = غير موجودة', () {
      final o = _order(
        category: 'PARCEL',
        pickup: null,
        dropoff: const {'address': '', 'lat': 0, 'lng': 0},
      );
      expect(offersReferencePoint(o), isNull);
    });
  });

  group('نقطة الاستلام الحقيقية (orderPickupPoint)', () {
    // النقطة الوهمية القديمة اللي كانت بتتخزن للصيدلية والطلب اليدوي.
    const legacyFake = {'address': 'صيدلية', 'lat': 30.2931, 'lng': 30.9863};

    test('مشوار: نقطة الاستلام', () {
      expect(orderPickupPoint(_order()), const LatLng(30.5, 31.0));
    });

    test('مطعم من القائمة: موقع المطعم', () {
      final o = _order(category: 'FOOD', restaurantId: 'r1');
      expect(orderPickupPoint(o), const LatLng(30.5, 31.0));
    });

    test('صيدلية بإحداثيات وهمية قديمة: null (مفيش علامة استلام)', () {
      expect(orderPickupPoint(_order(category: 'PHARMACY', pickup: legacyFake)),
          isNull);
    });

    test('صيدلية بإحداثيات 0 (الطلبات الجديدة): null', () {
      final o = _order(
          category: 'PHARMACY',
          pickup: const {'address': 'صيدلية', 'lat': 0, 'lng': 0});
      expect(orderPickupPoint(o), isNull);
    });

    test('طلب مطعم يدوي بإحداثيات وهمية قديمة: null', () {
      expect(orderPickupPoint(_order(category: 'FOOD', pickup: legacyFake)),
          isNull);
    });
  });

  group('أقرب كابتن', () {
    const ref = LatLng(30.5, 31.0);

    test('بيختار الأقرب فعلًا حتى لو سعره أعلى', () {
      final offers = [_offer('far', 20), _offer('near', 50)];
      final locs = {
        'far': _fix(30.6, 31.0), // ~11 كم
        'near': _fix(30.501, 31.0), // ~110 متر
      };
      expect(nearestOfferDriverId(ref, offers, locs), 'near');
    });

    test('بيتجاهل الكباتن اللي موقعهم مجهول', () {
      final offers = [_offer('a', 20), _offer('b', 30)];
      expect(nearestOfferDriverId(ref, offers, {'b': _fix(30.7, 31.0)}), 'b');
    });

    test('مفيش موقع أو مفيش مرجع = null', () {
      final offers = [_offer('a', 20)];
      expect(nearestOfferDriverId(ref, offers, const {}), isNull);
      expect(nearestOfferDriverId(null, offers, {'a': _fix(30.5, 31.0)}), isNull);
    });

    test('captainDistanceMeters: تقريب معقول', () {
      final d = captainDistanceMeters(ref, _fix(30.501, 31.0))!;
      expect(d, closeTo(111, 3));
      expect(captainDistanceMeters(ref, null), isNull);
    });
  });
}
