import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/verification/domain/document_requirements.dart';
import 'package:wasalha/features/verification/domain/verification_enums.dart';
import 'package:wasalha/models/models.dart' show VehicleType;

Set<DocType> _types(VehicleType? v) => {for (final r in requiredDocuments(v)) r.type};

void main() {
  group('requiredDocuments(vehicleType)', () {
    const identity = {
      DocType.idFront,
      DocType.idBack,
      DocType.selfieWithId,
      DocType.poseRight,
      DocType.poseLeft,
    };

    test('سيارة: مستندات الهوية + رخصتين + صورة المركبة', () {
      expect(_types(VehicleType.car), {
        ...identity,
        DocType.drivingLicense,
        DocType.vehicleLicense,
        DocType.vehiclePhoto,
      });
    });

    test('غير السيارة: لا تظهر مستندات السيارة كمطلوبة', () {
      expect(_types(VehicleType.toktok), identity);
      expect(_types(VehicleType.motorcycle), identity);
      expect(_types(null), identity);
    });

    test('رخصة القيادة والمركبة لهما انتهاء، واللوحة مطلوبة مع الرقم', () {
      final r = {for (final x in requiredDocuments(VehicleType.car)) x.type: x};
      expect(r[DocType.drivingLicense]!.hasExpiry, isTrue);
      expect(r[DocType.vehicleLicense]!.hasExpiry, isTrue);
      expect(r[DocType.vehiclePhoto]!.hasExpiry, isFalse);
      expect(r[DocType.vehiclePhoto]!.needsNumber, isTrue);
      expect(r[DocType.idFront]!.hasExpiry, isFalse);
    });

    test('vehicleNeedsLicenseData', () {
      expect(vehicleNeedsLicenseData(VehicleType.car), isTrue);
      expect(vehicleNeedsLicenseData(VehicleType.toktok), isFalse);
      expect(vehicleNeedsLicenseData(null), isFalse);
    });
  });

  group('expiryStatus', () {
    final now = DateTime(2026, 10, 4, 12);

    test('صالح', () {
      expect(expiryStatus(DateTime(2027, 1, 1), now), ExpiryStatus.valid);
    });

    test('قرب الانتهاء: أقل من 30 يوم', () {
      expect(expiryStatus(DateTime(2026, 10, 20), now), ExpiryStatus.expiringSoon);
      expect(expiryStatus(DateTime(2026, 11, 2), now), ExpiryStatus.expiringSoon);
      expect(expiryStatus(DateTime(2026, 11, 4), now), ExpiryStatus.valid);
    });

    test('بيعتبر صالحًا طوال يوم الانتهاء ويبقى منتهيًا اليوم التالي', () {
      expect(expiryStatus(DateTime(2026, 10, 4), now), ExpiryStatus.expiringSoon);
      expect(expiryStatus(DateTime(2026, 10, 3), now), ExpiryStatus.expired);
    });
  });

  group('reminderLevel', () {
    final now = DateTime(2026, 10, 4, 12);
    test('بعيد: لا تذكير', () {
      expect(reminderLevel(DateTime(2027, 1, 1), now), isNull);
    });
    test('30 يوم: تذكير', () {
      expect(reminderLevel(DateTime(2026, 10, 25), now), 'REMINDER');
    });
    test('7 أيام: تذكير عاجل', () {
      expect(reminderLevel(DateTime(2026, 10, 10), now), 'URGENT');
      expect(reminderLevel(DateTime(2026, 10, 4), now), 'URGENT');
    });
    test('منتهي: لا تذكير (هو EXPIRED)', () {
      expect(reminderLevel(DateTime(2026, 10, 1), now), isNull);
    });
  });
}
