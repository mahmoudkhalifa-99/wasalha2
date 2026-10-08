import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/geo_utils.dart';
import '../models/selected_location.dart';
import '../services/geocoding_service.dart';

enum PickPhase {
  /// لسه مفيش مركز.
  idle,

  /// الخريطة بتتحرك (مفيش أي طلب geocoding دلوقتي).
  moving,

  /// الخريطة وقفت، والعنوان قيد الطلب.
  resolving,

  /// العنوان جاهز، أو فشل (address == null).
  resolved,
}

class PickState {
  const PickState({
    this.phase = PickPhase.idle,
    this.center,
    this.address,
    this.distanceFromOriginMeters,
  });

  final PickPhase phase;
  final LatLng? center;

  /// null لو لسه ما اتحددش أو الـ Reverse Geocoding فشل.
  final String? address;

  /// المسافة من موقعي الحالي (لو معروف).
  final double? distanceFromOriginMeters;

  bool get addressFailed => phase == PickPhase.resolved && address == null;
}

/// منطق "اختيار موقع بـ Pin ثابت في المنتصف":
///
///   الخريطة بتتحرك → إلغاء الـ debounce السابق → وقفت → انتظار [debounce]
///   → أخد مركز الخريطة → Reverse Geocoding → تحديث المعاينة.
///
/// أي حركة جديدة أثناء انتظار الـ geocoding بتزوّد رقم النسخة، فأي رد قديم
/// بيتجاهل ومبيقدرش يستبدل الموقع الحالي.
class LocationPickerController {
  LocationPickerController({
    required this.geocoder,
    this.origin,
    this.debounce = const Duration(milliseconds: 500),
  });

  static const String fallbackAddress = 'موقع محدد على الخريطة';

  final GeocodingService geocoder;

  /// موقعي الحالي (لحساب المسافة).
  final LatLng? Function()? origin;
  final Duration debounce;

  final ValueNotifier<PickState> state = ValueNotifier<PickState>(const PickState());

  Timer? _timer;
  int _version = 0;
  bool _disposed = false;

  /// الزر بيتفعّل بعد ما الخريطة توقف (حتى لو العنوان لسه بيتحدد).
  bool get canConfirm {
    final p = state.value.phase;
    return p == PickPhase.resolving || p == PickPhase.resolved;
  }

  double? _dist(LatLng c) {
    final o = origin?.call();
    return o == null ? null : distanceMeters(o, c);
  }

  /// بيتنادى مع كل تغيّر في مركز الخريطة.
  void onCenterChanged(LatLng c) {
    if (_disposed) return;
    if (state.value.center == c) return; // مفيش حركة فعلية
    _version++;
    _timer?.cancel();
    state.value = PickState(
      phase: PickPhase.moving,
      center: c,
      distanceFromOriginMeters: _dist(c),
    );
    _timer = Timer(debounce, _resolve);
  }

  Future<void> _resolve() async {
    final c = state.value.center;
    if (c == null || _disposed) return;
    final v = _version;
    state.value = PickState(
      phase: PickPhase.resolving,
      center: c,
      distanceFromOriginMeters: _dist(c),
    );
    String? addr;
    try {
      addr = await geocoder.reverseGeocode(c);
    } catch (_) {
      addr = null; // الفشل مبيمنعش الاختيار
    }
    if (_disposed || v != _version) return; // رد قديم → اتجاهل
    final a = addr?.trim();
    state.value = PickState(
      phase: PickPhase.resolved,
      center: c,
      address: (a == null || a.isEmpty) ? null : a,
      distanceFromOriginMeters: _dist(c),
    );
  }

  /// يعتمد الموقع الحالي (مركز الخريطة). لو العنوان مش جاهز/فشل: النص البديل.
  /// بيلغي أي طلب معلّق عشان رد متأخر ما يغيّرش حاجة بعد الاعتماد.
  SelectedLocation? confirm() {
    final s = state.value;
    final c = s.center;
    if (c == null || !canConfirm) return null;
    _timer?.cancel();
    _version++;
    return SelectedLocation(
      latitude: c.latitude,
      longitude: c.longitude,
      address: s.address ?? fallbackAddress,
    );
  }

  /// عند الخروج من وضع الاختيار.
  void reset() {
    _timer?.cancel();
    _version++;
    if (!_disposed) state.value = const PickState();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    state.dispose();
  }
}
