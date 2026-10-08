import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config_constants.dart';
import '../features/tracking/models/selected_location.dart';
import '../features/tracking/models/tracking_models.dart';
import '../features/tracking/screens/tracking_screen.dart';
import '../features/tracking/services/geocoding_service.dart';
import '../features/tracking/services/location_service.dart';
import '../models/models.dart';

/// مكان اتحدد بالـ GPS أو من الخريطة، بإسمه الفعلي (مش بالضرورة موجود في
/// قوائم القرى بتاعة التطبيق).
class PickedPlace {
  const PickedPlace({
    required this.location,
    required this.placeName,
    required this.displayText,
    this.area,
    this.knownMatch,
  });

  final SelectedLocation location;

  /// اسم القرية/الحي الفعلي (مثال: طملاي). لو الـ geocoder فشل: نص عام.
  final String placeName;

  /// المركز/المنطقة لو معروف (مثال: مركز منوف).
  final String? area;

  /// نص العرض الكامل (شارع، قرية، مركز).
  final String displayText;

  /// لو اسم المكان مطابق تمامًا لقرية في القائمة (مطابقة بالاسم فقط، مش
  /// بالأقرب مسافة). null = المكان مش في القائمة، فبيتكتب كما هو.
  final ({District district, Village village})? knownMatch;

  double get latitude => location.latitude;
  double get longitude => location.longitude;
}

String _norm(String s) {
  var t = s.trim();
  t = t.replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '');
  t = t
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  t = t.replaceFirst(RegExp(r'^(قريه|قرية|مركز|مدينه|مدينة|حي|عزبه|عزبة)\s+'), '');
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

({District district, Village village})? _exactKnownVillage(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final n = _norm(name);
  if (n.isEmpty) return null;
  for (final d in menofiaData) {
    for (final v in d.villages) {
      if (_norm(v.name) == n) return (district: d, village: v);
    }
  }
  return null;
}

PickedPlace _build(SelectedLocation sel, PlaceDetails? d) {
  final locality = d?.locality;
  final area = d?.area;
  if (locality == null && (d?.full == null || d!.full!.isEmpty)) {
    // الـ geocoder فشل/مفيش اسم: بنعرض العنوان الجاهز من الاختيار كما هو.
    return PickedPlace(
      location: sel,
      placeName: sel.address,
      displayText: sel.address,
    );
  }
  final parts = <String>[];
  void add(String? v) {
    if (v != null && v.trim().isNotEmpty && !parts.contains(v.trim())) {
      parts.add(v.trim());
    }
  }

  add(d?.road);
  add(locality);
  add(area);
  final text = parts.isNotEmpty ? parts.join('، ') : (d?.full ?? sel.address);
  final name = locality ?? area ?? text;
  return PickedPlace(
    location: sel,
    placeName: name,
    area: area == name ? null : area,
    displayText: text,
    knownMatch: _exactKnownVillage(locality) ?? _exactKnownVillage(area),
  );
}

/// فتح الخريطة بوضع "اختيار موقع" (Pin ثابت في المنتصف). بيرجّع المكان
/// المعتمد بإسمه الفعلي، أو null لو المستخدم رجع من غير اختيار.
Future<PickedPlace?> pickLocationOnMap(BuildContext context) async {
  final geocoder = NominatimGeocodingService();
  try {
    final sel = await Navigator.of(context).push<SelectedLocation>(
      MaterialPageRoute(
        builder: (ctx) => TrackingScreen(
          role: TrackingRole.customerWatchingDriver,
          title: 'اختر الموقع من الخريطة',
          initialMode: TrackingScreenMode.pickLocation,
          allowLocationPicking: false,
          applySelectionAsDestination: false,
          geocodingService: geocoder,
          onLocationSelected: (sel) => Navigator.of(ctx).pop(sel),
        ),
      ),
    );
    if (sel == null) return null;
    // نفس الـ geocoder والكاش: غالبًا مفيش طلب شبكة جديد هنا.
    PlaceDetails? d;
    try {
      d = await geocoder.reverseDetails(sel.latLng);
    } catch (_) {
      d = null;
    }
    return _build(sel, d);
  } finally {
    geocoder.close();
  }
}

/// نتيجة "موقعي الحالي": المكان، أو سبب الفشل بعبارة مفهومة للمستخدم.
class CurrentLocationResult {
  const CurrentLocationResult.ok(this.place) : error = null;
  const CurrentLocationResult.failed(this.error) : place = null;
  final PickedPlace? place;
  final String? error;
}

Future<CurrentLocationResult> fetchCurrentLocation() async {
  const service = GeolocatorLocationService();
  final issue = await service.ensureReady();
  if (issue != null) {
    return const CurrentLocationResult.failed(
        'مش قادر أحدد موقعك. فعّل الـ GPS واسمح للتطبيق بالوصول للموقع.');
  }
  final LatLng? p = await service.currentLatLng();
  if (p == null) {
    return const CurrentLocationResult.failed(
        'تعذّر تحديد موقعك الآن، جرّب تاني أو اختر من الخريطة.');
  }
  // الاسم اختياري: لو فشل بنكمّل بالإحداثيات (الطلب مش بيتعطّل بسببه).
  final geocoder = NominatimGeocodingService();
  PlaceDetails? d;
  try {
    d = await geocoder.reverseDetails(p);
  } catch (_) {
    d = null;
  } finally {
    geocoder.close();
  }
  final sel = SelectedLocation(
    latitude: p.latitude,
    longitude: p.longitude,
    address: (d?.full == null || d!.full!.trim().isEmpty)
        ? 'موقعي الحالي'
        : d.full!,
  );
  return CurrentLocationResult.ok(_build(sel, d));
}
