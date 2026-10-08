import '../../../models/models.dart' show VehicleType;
import 'verification_enums.dart';

/// وصف مستند مطلوب.
class DocRequirement {
  final DocType type;

  /// لازم تاريخ انتهاء (رخصة القيادة / رخصة المركبة).
  final bool hasExpiry;

  /// لازم رقم المستند/اللوحة يتسجّل (للمنع من الازدواج).
  final bool needsNumber;

  const DocRequirement(this.type, {this.hasExpiry = false, this.needsNumber = false});
}

/// مستندات الهوية المطلوبة لكل الكباتن بغض النظر عن المركبة.
const List<DocRequirement> kIdentityDocs = [
  DocRequirement(DocType.idFront),
  DocRequirement(DocType.idBack),
  DocRequirement(DocType.selfieWithId),
  // إطارا تحدّي الوضعية: دليل للمراجعة البشرية، مش Liveness آلي.
  DocRequirement(DocType.poseRight),
  DocRequirement(DocType.poseLeft),
];

/// مستندات خاصة بأنواع المركبات. نوع مش موجود هنا = مفيش مستندات مركبة مطلوبة
/// (مش بيتمنع من التوثيق). لإضافة نوع جديد (van/truck/...): أضف key هنا فقط
/// (والنسخة المقابلة في functions/verification.js).
const Map<VehicleType, List<DocRequirement>> kVehicleDocs = {
  VehicleType.car: [
    DocRequirement(DocType.drivingLicense, hasExpiry: true, needsNumber: true),
    DocRequirement(DocType.vehicleLicense, hasExpiry: true),
    DocRequirement(DocType.vehiclePhoto, needsNumber: true), // اللوحة لازم تبان
  ],
};

/// المصدر الوحيد لمتطلبات المستندات. ما تحطش شروط ثابتة في الشاشات.
List<DocRequirement> requiredDocuments(VehicleType? vehicleType) => [
      ...kIdentityDocs,
      if (vehicleType != null) ...?kVehicleDocs[vehicleType],
    ];

/// هل نوع المركبة ده بيحتاج بيانات رخصة/لوحة؟
bool vehicleNeedsLicenseData(VehicleType? t) =>
    t != null && (kVehicleDocs[t]?.isNotEmpty ?? false);

/// مدة "قرب الانتهاء".
const int kExpiringSoonDays = 30;
const int kExpiringUrgentDays = 7;

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

/// صلاحية مستند بتاريخ انتهاء. المستند صالح طوال يوم الانتهاء نفسه.
ExpiryStatus expiryStatus(DateTime expiresAt, DateTime now) {
  final end = _endOfDay(expiresAt);
  if (now.isAfter(end)) return ExpiryStatus.expired;
  if (end.difference(now).inDays < kExpiringSoonDays) {
    return ExpiryStatus.expiringSoon;
  }
  return ExpiryStatus.valid;
}

/// الأيام المتبقية (سالب = منتهي).
int daysUntilExpiry(DateTime expiresAt, DateTime now) {
  final end = _endOfDay(expiresAt);
  if (now.isAfter(end)) return -(now.difference(end).inDays + 1);
  return end.difference(now).inDays;
}

/// نوع التذكير المناسب: null / 'REMINDER' (≤30 يوم) / 'URGENT' (≤7 أيام).
String? reminderLevel(DateTime expiresAt, DateTime now) {
  final days = daysUntilExpiry(expiresAt, now);
  if (days < 0) return null;
  if (days <= kExpiringUrgentDays) return 'URGENT';
  if (days < kExpiringSoonDays) return 'REMINDER';
  return null;
}
