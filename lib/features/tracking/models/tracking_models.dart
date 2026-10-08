import 'package:latlong2/latlong.dart';

/// كل العتبات القابلة للضبط في مكان واحد (مفيش أرقام سحرية جوه الـ Controller
/// أو الـ Widgets). القيم الافتراضية نقطة بداية، مش حقيقة نهائية.
class TrackingConfig {
  const TrackingConfig({
    this.maxAcceptedAccuracyMeters = 50,
    this.liveThreshold = const Duration(seconds: 30),
    this.unavailableThreshold = const Duration(minutes: 10),
    this.pickDebounce = const Duration(milliseconds: 500),
    this.focusZoom = 16,
  });

  /// أي نقطة GPS دقتها أسوأ من القيمة دي (بالمتر) بتتجاهل في الموقع/المسار/
  /// إعادة الحساب/البث. التتبع نفسه بيكمّل ويحتفظ بآخر نقطة صالحة.
  final double maxAcceptedAccuracyMeters;

  /// عمر آخر موقع لحد [liveThreshold] = مباشر (LIVE).
  final Duration liveThreshold;

  /// أكبر من [liveThreshold] = قديم (STALE)، وأكبر من [unavailableThreshold]
  /// = غير متاح (UNAVAILABLE).
  final Duration unavailableThreshold;

  /// مهلة التوقف عن تحريك الخريطة قبل طلب العنوان (Reverse Geocoding).
  final Duration pickDebounce;

  /// Zoom عند التركيز على نقطة واحدة.
  final double focusZoom;
}

/// موقع لحظي (للسائق أو للجهاز).
class GeoFix {
  const GeoFix({
    required this.position,
    required this.updatedAt,
    this.bearing,
    this.accuracy,
  });

  final LatLng position;
  final DateTime updatedAt;

  /// اتجاه الحركة بالدرجات (0–360) لو معروف.
  final double? bearing;

  /// دقة النقطة بالمتر (نصف قطر الخطأ) لو معروفة. null = غير معروفة (مقبولة).
  final double? accuracy;
}

/// حداثة موقع السائق (مستقلة عن [TrackingStatus]).
enum Freshness { live, stale, waiting, unavailable }

/// يحسب [Freshness] من عمر آخر نقطة. دالة نقية (من غير ساعة/Timers) عشان تتختبر.
/// - مفيش نقطة: waiting، أو unavailable لو المصدر نفسه فاشل.
/// - عمر سالب (اختلاف ساعة الأجهزة) بيتعامل معاه كأنه صفر.
Freshness computeFreshness({
  required GeoFix? fix,
  required DateTime now,
  TrackingConfig config = const TrackingConfig(),
  bool sourceFailed = false,
}) {
  if (fix == null) {
    return sourceFailed ? Freshness.unavailable : Freshness.waiting;
  }
  var age = now.difference(fix.updatedAt);
  if (age.isNegative) age = Duration.zero;
  if (age <= config.liveThreshold) return Freshness.live;
  if (age <= config.unavailableThreshold) return Freshness.stale;
  return Freshness.unavailable;
}

extension FreshnessText on Freshness {
  String get label {
    switch (this) {
      case Freshness.live:
        return 'مباشر';
      case Freshness.stale:
        return 'قديم';
      case Freshness.waiting:
        return 'في انتظار الموقع';
      case Freshness.unavailable:
        return 'غير متاح';
    }
  }
}

/// المتبقي من المسار (بيتحسب محليًا مع كل نقطة من غير طلب Routing جديد).
class RouteProgress {
  const RouteProgress({required this.distanceMeters, required this.durationSeconds});
  final double distanceMeters;
  final double durationSeconds;

  @override
  bool operator ==(Object other) =>
      other is RouteProgress &&
      other.distanceMeters == distanceMeters &&
      other.durationSeconds == durationSeconds;

  @override
  int get hashCode => Object.hash(distanceMeters, durationSeconds);
}

enum CameraCommandType {
  /// يظهّر كل النقاط في [CameraCommand.points] مع بعض.
  fitBounds,

  /// يركّز على موقع السائق ([CameraCommand.target]).
  centerOnDriver,

  /// يركّز على موقع الجهاز (وضع العميل).
  centerOnMe,

  /// يركّز على الوجهة/الموقع المحدد.
  centerOnSelectedLocation,
}

/// أمر كاميرا بيصدره الـ Controller، وبينفّذه الـ Widget بـ MapController.
/// [id] بيزيد مع كل أمر، فالـ Widget يعرف الأمر الجديد حتى لو نفس القيم.
class CameraCommand {
  const CameraCommand({
    required this.id,
    required this.type,
    this.points = const [],
    this.target,
    this.zoom,
  });

  final int id;
  final CameraCommandType type;
  final List<LatLng> points;
  final LatLng? target;
  final double? zoom;
}

enum TrackingStatus {
  /// جاري تجهيز الموقع/التتبع.
  starting,

  /// وضع العميل: لسه موقع السائق ما وصلش.
  waitingForDriver,

  /// التتبع شغال.
  live,

  /// وضع السائق: مفيش صلاحية أو GPS مقفول.
  locationBlocked,
}

enum LocationIssue { serviceDisabled, denied, deniedForever, unavailable }

extension LocationIssueText on LocationIssue {
  String get message {
    switch (this) {
      case LocationIssue.serviceDisabled:
        return 'خدمة الموقع (GPS) مقفولة. فعّلها عشان نحدد موقعك.';
      case LocationIssue.denied:
        return 'محتاجين صلاحية الموقع عشان نعرض موقعك على الخريطة.';
      case LocationIssue.deniedForever:
        return 'صلاحية الموقع مرفوضة نهائيًا. فعّلها من إعدادات التطبيق.';
      case LocationIssue.unavailable:
        return 'تعذّر تحديد موقعك حاليًا. حاول تاني بعد شوية.';
    }
  }

  String get actionLabel {
    switch (this) {
      case LocationIssue.serviceDisabled:
        return 'فتح إعدادات الموقع';
      case LocationIssue.deniedForever:
        return 'فتح إعدادات التطبيق';
      case LocationIssue.denied:
      case LocationIssue.unavailable:
        return 'إعادة المحاولة';
    }
  }
}

/// دور الجهاز في الشاشة.
enum TrackingRole {
  /// العميل بيتابع موقع السائق (من Firestore).
  customerWatchingDriver,

  /// الجهاز نفسه هو السائق (بيستخدم الـ GPS ويبث الموقع).
  driverSharing,
}
