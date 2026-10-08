
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/tracking_models.dart';

/// بيترمي من [LocationService.watch] لما الموقع يبقى مش متاح أثناء التتبع.
class LocationIssueException implements Exception {
  const LocationIssueException(this.issue);
  final LocationIssue issue;
  @override
  String toString() => 'LocationIssueException($issue)';
}

/// كل منطق الموقع هنا (مفيش أي منطق GPS جوه الـ Widgets).
abstract class LocationService {
  /// يتحقق من GPS والصلاحية (ويطلبها لو لزم). يرجّع null لو كله تمام.
  Future<LocationIssue?> ensureReady();

  /// الموقع الحالي لمرة واحدة، أو null لو مش متاح.
  Future<LatLng?> currentLatLng();

  /// نفس [currentLatLng] لكن مع الدقة ووقت النقطة (عشان فلتر الدقة وحالة STALE).
  Future<GeoFix?> currentFix();

  /// بث تحديثات الموقع. اشتراك واحد فقط لكل Controller.
  Stream<GeoFix> watch({int distanceFilter = 5});

  /// يفتح الإعدادات المناسبة للمشكلة.
  Future<void> openSettings(LocationIssue issue);
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationIssue?> ensureReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationIssue.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationIssue.deniedForever;
      }
      if (permission == LocationPermission.denied) {
        return LocationIssue.denied;
      }
      return null;
    } catch (_) {
      return LocationIssue.unavailable;
    }
  }

  @override
  Future<LatLng?> currentLatLng() async {
    try {
      // getCurrentPosition (مش Stream مؤقت): بيلغي نفسه عند الـ timeout
      // ومبيسيبش اشتراك GPS ثاني شغال جنب اشتراك التتبع.
      final p = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
        // ignore: deprecated_member_use
        timeLimit: const Duration(seconds: 12),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return LatLng(last.latitude, last.longitude);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<GeoFix?> currentFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
        // ignore: deprecated_member_use
        timeLimit: const Duration(seconds: 12),
      );
      return _toFix(p, useDeviceTimestamp: false);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        // آخر موقع معروف ممكن يكون قديم: بنحتفظ بوقته الحقيقي عشان يظهر STALE.
        if (last != null) return _toFix(last, useDeviceTimestamp: true);
      } catch (_) {}
      return null;
    }
  }

  GeoFix _toFix(Position p, {required bool useDeviceTimestamp}) {
    return GeoFix(
      position: LatLng(p.latitude, p.longitude),
      // آخر موقع معروف: وقته الحقيقي (عشان يظهر STALE). نقطة جديدة: الآن.
      updatedAt: useDeviceTimestamp ? p.timestamp : DateTime.now(),
      accuracy: p.accuracy,
    );
  }

  @override
  Stream<GeoFix> watch({int distanceFilter = 5}) async* {
    try {
      await for (final p in Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
        ),
      )) {
        yield GeoFix(
          position: LatLng(p.latitude, p.longitude),
          updatedAt: DateTime.now(),
          // الاتجاه بيبقى غير موثوق لما الجهاز واقف.
          bearing: p.speed > 1.0 && p.heading >= 0 ? p.heading : null,
          accuracy: p.accuracy,
        );
      }
    } on LocationServiceDisabledException {
      throw const LocationIssueException(LocationIssue.serviceDisabled);
    } on PermissionDeniedException {
      throw const LocationIssueException(LocationIssue.denied);
    }
  }

  @override
  Future<void> openSettings(LocationIssue issue) async {
    try {
      if (issue == LocationIssue.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
}
