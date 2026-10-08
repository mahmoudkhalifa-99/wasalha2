import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/controllers/location_picker_controller.dart';
import 'package:wasalha/features/tracking/services/geocoding_service.dart';

/// Geocoder للاختبار: بنتحكم يدويًا في توقيت الرد (أو بيرد/يفشل فورًا).
class FakeGeocoder implements GeocodingService {
  final List<LatLng> calls = [];
  final List<Completer<String?>> pending = [];
  bool throwError = false;
  bool respondImmediately = false;
  String? immediateResult;

  @override
  Future<String?> reverseGeocode(LatLng location) {
    calls.add(location);
    if (throwError) return Future<String?>.error(Exception('geocoder down'));
    if (respondImmediately) return Future<String?>.value(immediateResult);
    final c = Completer<String?>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<List<LocationSearchResult>> search(String query) async => const [];
}

const _a = LatLng(30.5560, 31.0080);
const _b = LatLng(30.5600, 31.0120);
const _debounce = Duration(milliseconds: 30);
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late FakeGeocoder geo;
  late LocationPickerController p;

  setUp(() {
    geo = FakeGeocoder();
    p = LocationPickerController(geocoder: geo, debounce: _debounce);
  });

  tearDown(() => p.dispose());

  test('أثناء حركة الخريطة: مفيش أي طلب geocoding', () async {
    p.onCenterChanged(_a);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    p.onCenterChanged(_b);
    expect(geo.calls, isEmpty);
    expect(p.state.value.phase, PickPhase.moving);
    expect(p.canConfirm, isFalse); // لسه بتتحرك
  });

  test('الـ debounce: عدة حركات متتالية = طلب واحد بآخر مركز', () async {
    for (var i = 0; i < 5; i++) {
      p.onCenterChanged(LatLng(30.55 + i * 0.001, 31.0));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await settle();
    expect(geo.calls.length, 1);
    expect(geo.calls.single, LatLng(30.55 + 4 * 0.001, 31.0));
  });

  test('بعد التوقف: resolving ثم resolved بالعنوان', () async {
    p.onCenterChanged(_a);
    await settle();
    expect(p.state.value.phase, PickPhase.resolving);
    expect(p.canConfirm, isTrue); // الزر بيتفعّل حتى لو العنوان لسه بيتحدد
    geo.pending.single.complete('شارع النصر، شبين الكوم');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(p.state.value.phase, PickPhase.resolved);
    expect(p.state.value.address, 'شارع النصر، شبين الكوم');
    expect(p.state.value.center, _a);
  });

  test('رد قديم بعد تحريك الخريطة: بيتجاهل ومبيستبدلش الموقع الحالي', () async {
    p.onCenterChanged(_a);
    await settle();
    expect(geo.calls, [_a]); // الطلب الأول معلّق

    p.onCenterChanged(_b); // المستخدم حرّك تاني أثناء الانتظار
    await settle();
    expect(geo.calls, [_a, _b]);

    geo.pending[0].complete('عنوان قديم (A)');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(p.state.value.address, isNull); // اتجاهل
    expect(p.state.value.center, _b);
    expect(p.state.value.phase, PickPhase.resolving);

    geo.pending[1].complete('عنوان جديد (B)');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(p.state.value.address, 'عنوان جديد (B)');
    expect(p.state.value.phase, PickPhase.resolved);
  });

  test('رد قديم بيوصل أثناء حركة الخريطة (قبل ما تقف): برضه بيتجاهل', () async {
    p.onCenterChanged(_a);
    await settle();
    p.onCenterChanged(_b); // phase = moving
    geo.pending[0].complete('قديم');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(p.state.value.phase, PickPhase.moving);
    expect(p.state.value.address, isNull);
  });

  test('فشل Reverse Geocoding: الاختيار بيكمّل بعنوان بديل والإحداثيات', () async {
    geo.throwError = true;
    p.onCenterChanged(_a);
    await settle();
    expect(p.state.value.phase, PickPhase.resolved);
    expect(p.state.value.addressFailed, isTrue);
    expect(p.canConfirm, isTrue);

    final sel = p.confirm()!;
    expect(sel.address, 'موقع محدد على الخريطة');
    expect(sel.latitude, _a.latitude);
    expect(sel.longitude, _a.longitude);
  });

  test('عنوان null/فاضي = نفس البديل', () async {
    geo.respondImmediately = true;
    geo.immediateResult = '   ';
    p.onCenterChanged(_a);
    await settle();
    expect(p.state.value.addressFailed, isTrue);
    expect(p.confirm()!.address, LocationPickerController.fallbackAddress);
  });

  test('confirm بعد ما العنوان يجهز: بيرجّع SelectedLocation كامل', () async {
    p.onCenterChanged(_a);
    await settle();
    geo.pending.single.complete('شارع الجمهورية');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final sel = p.confirm()!;
    expect(sel.latLng, _a);
    expect(sel.address, 'شارع الجمهورية');
  });

  test('confirm أثناء الحركة أو قبل أي مركز = null', () async {
    expect(p.confirm(), isNull);
    p.onCenterChanged(_a);
    expect(p.confirm(), isNull); // moving
  });

  test('confirm أثناء resolving: بعنوان بديل، والرد المتأخر مبيغيّرش حاجة', () async {
    p.onCenterChanged(_a);
    await settle();
    final sel = p.confirm()!;
    expect(sel.address, 'موقع محدد على الخريطة');

    final before = p.state.value;
    geo.pending.single.complete('وصل متأخر');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(identical(p.state.value, before), isTrue);
  });

  test('نفس المركز مرتين: مفيش إعادة تشغيل للـ debounce ولا state جديدة', () async {
    p.onCenterChanged(_a);
    final s1 = p.state.value;
    p.onCenterChanged(_a);
    expect(identical(p.state.value, s1), isTrue);
  });

  test('المسافة من موقعي: بتتحسب ومعاها كل تحديث', () async {
    final withOrigin = LocationPickerController(
      geocoder: geo,
      debounce: _debounce,
      origin: () => const LatLng(30.55, 31.0),
    );
    withOrigin.onCenterChanged(const LatLng(30.56, 31.0)); // ~1112 م شمال
    expect(withOrigin.state.value.distanceFromOriginMeters, closeTo(1112, 5));
    withOrigin.dispose();
  });

  test('بدون موقعي: المسافة null', () {
    p.onCenterChanged(_a);
    expect(p.state.value.distanceFromOriginMeters, isNull);
  });

  test('reset: بيلغي الطلب المعلّق وبيرجّع الحالة فاضية', () async {
    p.onCenterChanged(_a);
    p.reset();
    await settle();
    expect(geo.calls, isEmpty);
    expect(p.state.value.phase, PickPhase.idle);
    expect(p.state.value.center, isNull);
  });

  test('dispose أثناء انتظار الرد: من غير استثناءات', () async {
    final q = LocationPickerController(geocoder: geo, debounce: _debounce);
    q.onCenterChanged(_a);
    await settle();
    q.dispose();
    geo.pending.last.complete('بعد الإغلاق');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
