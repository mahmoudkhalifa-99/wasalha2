import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/tracking_models.dart';
import 'driver_location_source.dart';

/// بيتابع مواقع مجموعة كباتن في نفس الوقت (مثلاً كل الكباتن اللي قدّموا عروض
/// على طلب العميل). اشتراك واحد لكل كابتن، وبيتقفل لما الكابتن يختفي من
/// القائمة أو عند dispose().
///
/// القراءة بس من driver_locations/{id}. القواعد بتسمح للعميل يقرأ موقع الكابتن
/// لو الكابتن ضافه في `viewers` (يعني قدّم عرض على طلبه). كابتن مش مسموح
/// بقراءته بيطلع permission-denied، والخطأ ده بيتجاهل لكل كابتن لوحده.
class CaptainLocations {
  CaptainLocations({DriverLocationSource Function(String driverId)? sourceFor})
      : _sourceFor = sourceFor ?? FirestoreDriverLocationSource.new;

  final DriverLocationSource Function(String driverId) _sourceFor;

  /// آخر موقع معروف لكل كابتن (driverId → موقع). كابتن مالوش موقع = مش موجود.
  final ValueNotifier<Map<String, GeoFix>> locations =
      ValueNotifier<Map<String, GeoFix>>(const {});

  final Map<String, StreamSubscription<GeoFix>> _subs = {};
  bool _disposed = false;

  /// يخلّي الاشتراكات مطابقة للقائمة المطلوبة (بيضيف الجديد ويقفل اللي راح).
  void sync(Iterable<String> driverIds) {
    if (_disposed) return;
    final wanted = driverIds.where((e) => e.isNotEmpty).toSet();

    for (final id in _subs.keys.toList()) {
      if (wanted.contains(id)) continue;
      _subs.remove(id)?.cancel();
      if (locations.value.containsKey(id)) {
        locations.value = Map<String, GeoFix>.of(locations.value)..remove(id);
      }
    }

    for (final id in wanted) {
      if (_subs.containsKey(id)) continue;
      _subs[id] = _sourceFor(id).watch().listen(
        (fix) {
          if (_disposed) return;
          locations.value = {...locations.value, id: fix};
        },
        onError: (Object e) {
          // فشل قراءة موقع كابتن واحد ما يأثرش على الباقي.
          debugPrint('captain location error ($id): $e');
        },
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    locations.dispose();
  }
}
