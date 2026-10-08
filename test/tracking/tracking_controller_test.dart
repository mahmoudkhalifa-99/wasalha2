import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/core/map/routing_service.dart';
import 'package:wasalha/features/tracking/controllers/tracking_controller.dart';
import 'package:wasalha/features/tracking/models/tracking_models.dart';
import 'package:wasalha/features/tracking/services/driver_location_source.dart';
import 'package:wasalha/features/tracking/services/location_service.dart';

class FakeLocation implements LocationService {
  FakeLocation({this.issue});
  LocationIssue? issue;
  LatLng? current = const LatLng(30.55, 31.0);
  double? currentAccuracy;
  final StreamController<GeoFix> ctrl = StreamController<GeoFix>.broadcast();
  int watchCalls = 0;

  @override
  Future<LocationIssue?> ensureReady() async => issue;

  @override
  Future<LatLng?> currentLatLng() async => current;

  @override
  Future<GeoFix?> currentFix() async => current == null
      ? null
      : GeoFix(
          position: current!,
          updatedAt: DateTime.now(),
          accuracy: currentAccuracy,
        );

  @override
  Stream<GeoFix> watch({int distanceFilter = 5}) {
    watchCalls++;
    return ctrl.stream;
  }

  @override
  Future<void> openSettings(LocationIssue issue) async {}
}

class FakeRouting implements RoutingService {
  int calls = 0;
  RoutingException? failWith;

  @override
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    calls++;
    final f = failWith;
    if (f != null) throw f;
    return RouteResult(
      points: [start, destination],
      distanceMeters: 1000,
      durationSeconds: 120,
    );
  }
}

class FakeSource implements DriverLocationSource {
  final StreamController<GeoFix> ctrl = StreamController<GeoFix>.broadcast();
  @override
  Stream<GeoFix> watch() => ctrl.stream;
}

/// Routing بيستنى الاختبار يكمّل الرد يدويًا (لمحاكاة رد بطيء).
class GatedRouting implements RoutingService {
  final List<Completer<RouteResult>> pending = [];
  final List<LatLng> starts = []; // نقطة بداية كل طلب (بترجع بيها الردود)
  int calls = 0;

  @override
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng destination,
  }) {
    calls++;
    starts.add(start);
    final c = Completer<RouteResult>();
    pending.add(c);
    return c.future;
  }
}

// لو اتبعت [from] المسار بيبدأ من نقطة السائق (زي OSRM الحقيقي) فمبيبقاش
// "خارج المسار" بعد الرد؛ من غيره بيرجع المسار الثابت القديم.
RouteResult _route({LatLng? from}) => RouteResult(
      points: [from ?? const LatLng(30.55, 31.0), const LatLng(30.56, 31.01)],
      distanceMeters: 1000,
      durationSeconds: 120,
    );

GeoFix fix(double lat, double lng, {double? accuracy}) => GeoFix(
      position: LatLng(lat, lng),
      updatedAt: DateTime.now(),
      accuracy: accuracy,
    );

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

const _customer = LatLng(30.56, 31.01);

void main() {
  late FakeLocation location;
  late FakeRouting routing;
  late FakeSource source;
  late TrackingController c;

  setUp(() {
    location = FakeLocation();
    routing = FakeRouting();
    source = FakeSource();
    c = TrackingController(
      location: location,
      routing: routing,
      driverSource: source,
      customerLocation: _customer,
      minRouteInterval: Duration.zero,
      retryBackoffBase: Duration.zero, // عشان اختبارات التعافي ما تستناش
    );
  });

  tearDown(() => c.dispose());

  test('بيحسب المسار مرة واحدة ولا يعيد الطلب مع تحركات صغيرة', () async {
    await c.start();
    for (var i = 0; i < 5; i++) {
      source.ctrl.add(fix(30.55 + i * 0.00002, 31.0)); // ~2 متر كل مرة
      await pump();
    }
    expect(routing.calls, 1);
    expect(c.route.value, isNotNull);
    expect(c.status.value, TrackingStatus.live);
  });

  test('بيعيد حساب المسار بعد تحرك أكبر من 75 متر', () async {
    await c.start();
    source.ctrl.add(fix(30.55, 31.0));
    await pump();
    source.ctrl.add(fix(30.552, 31.0)); // ~222 متر
    await pump();
    expect(routing.calls, 2);
  });

  test('بيعيد الحساب لما السائق يخرج عن خط المسار (حتى لو تحرك أقل من 75 متر)',
      () async {
    await c.start();
    source.ctrl.add(fix(30.55, 31.0));
    await pump();
    // المسار خط قطري ناحية الشمال الشرقي. التحرك ناحية الجنوب الشرقي ~70 متر
    // (أقل من 75) لكنه عمودي تقريبًا على الخط → بعد ~69 متر عنه (> 60).
    source.ctrl.add(fix(30.55 - 0.00035, 31.0 + 0.0006));
    await pump();
    expect(routing.calls, 2);
  });

  test('فشل الشبكة: بنحتفظ بآخر مسار ونعلّم الاتصال مقطوع، وبيرجع بعد النجاح',
      () async {
    await c.start();
    source.ctrl.add(fix(30.55, 31.0));
    await pump();
    final firstRoute = c.route.value;
    expect(firstRoute, isNotNull);

    routing.failWith = const RoutingException(RoutingFailure.network);
    source.ctrl.add(fix(30.553, 31.0));
    await pump();
    expect(c.networkOk.value, isFalse);
    expect(c.routeUnavailable.value, isTrue);
    expect(identical(c.route.value, firstRoute), isTrue);

    routing.failWith = null;
    source.ctrl.add(fix(30.556, 31.0));
    await pump();
    expect(c.networkOk.value, isTrue);
    expect(c.routeUnavailable.value, isFalse);
    expect(identical(c.route.value, firstRoute), isFalse);
  });

  test('وضع السائق: صلاحية مرفوضة نهائيًا = locationBlocked ومفيش stream', () async {
    final driverLoc = FakeLocation(issue: LocationIssue.deniedForever);
    final d = TrackingController(
      location: driverLoc,
      routing: routing,
      customerLocation: _customer,
    );
    await d.start();
    expect(d.locationIssue.value, LocationIssue.deniedForever);
    expect(d.status.value, TrackingStatus.locationBlocked);
    expect(driverLoc.watchCalls, 0);
    d.dispose();
  });

  test('وضع السائق: موقع الجهاز يتحول لموقع السائق ويتحسب المسار', () async {
    final driverLoc = FakeLocation();
    final d = TrackingController(
      location: driverLoc,
      routing: routing,
      customerLocation: _customer,
      minRouteInterval: Duration.zero,
    );
    await d.start();
    await pump();
    expect(d.isDriverMode, isTrue);
    expect(d.driver.value, isNotNull);
    expect(d.status.value, TrackingStatus.live);
    expect(routing.calls, 1);
    d.dispose();
  });

  test('retryLocation ما بيفتحش أكتر من stream واحد', () async {
    await c.start();
    await c.retryLocation();
    await c.retryLocation();
    expect(location.ctrl.hasListener, isTrue);
    expect(location.watchCalls, 3); // كل استدعاء بيلغي القديم قبل الجديد
  });

  test('dispose بيقفل كل الاشتراكات', () async {
    await c.start();
    expect(source.ctrl.hasListener, isTrue);
    expect(location.ctrl.hasListener, isTrue);
    c.dispose();
    await pump();
    expect(source.ctrl.hasListener, isFalse);
    expect(location.ctrl.hasListener, isFalse);
  });

  test('بعد فشل Routing (429): backoff بيمنع الضرب على الـ API مع كل نقطة GPS',
      () async {
    final r = FakeRouting()
      ..failWith = const RoutingException(RoutingFailure.rateLimited);
    final b = TrackingController(
      location: FakeLocation(),
      routing: r,
      driverSource: source,
      customerLocation: _customer,
      minRouteInterval: Duration.zero, // الـ backoff الافتراضي (10s+) شغال
    );
    await b.start();
    for (var i = 0; i < 5; i++) {
      source.ctrl.add(fix(30.55 + i * 0.002, 31.0)); // ~222 متر كل مرة
      await pump();
    }
    expect(r.calls, 1);
    expect(b.routeUnavailable.value, isTrue);
    b.dispose();
  });

  test('السائق اتحرك أثناء انتظار الرد: إعادة حساب واحدة بعد وصول الرد', () async {
    final g = GatedRouting();
    final b = TrackingController(
      location: FakeLocation(),
      routing: g,
      driverSource: source,
      customerLocation: _customer,
      minRouteInterval: Duration.zero,
    );
    await b.start();
    source.ctrl.add(fix(30.55, 31.0));
    await pump();
    expect(g.calls, 1);
    source.ctrl.add(fix(30.553, 31.0)); // ~333 متر والطلب الأول لسه معلّق
    await pump();
    expect(g.calls, 1); // طلب واحد في الجو
    g.pending[0].complete(_route(from: g.starts[0]));
    await pump();
    expect(g.calls, 2); // الرد قديم → اتطلب مسار جديد من الموقع الحالي
    // المسار الجديد بيبدأ من موقع السائق الحالي → مفيش خروج عن المسار ولا إعادة
    g.pending[1].complete(_route(from: g.starts[1]));
    await pump();
    expect(g.calls, 2);
    b.dispose();
  });

  test('خطأ مؤقت في GPS: بيعيد الاشتراك تلقائيًا في الـ tick', () async {
    final loc = FakeLocation();
    final b = TrackingController(
      location: loc,
      routing: routing,
      customerLocation: _customer,
      tick: const Duration(milliseconds: 30),
    );
    await b.start();
    expect(loc.watchCalls, 1);
    loc.ctrl.addError(Exception('boom'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(loc.watchCalls, greaterThanOrEqualTo(2));
    expect(loc.ctrl.hasListener, isTrue);
    expect(b.locationIssue.value, isNull);
    b.dispose();
  });

  test('صلاحية مرفوضة: الـ tick ما بيكررش طلب الصلاحية ولا بيفتح stream', () async {
    final loc = FakeLocation(issue: LocationIssue.denied);
    final b = TrackingController(
      location: loc,
      routing: routing,
      customerLocation: _customer,
      tick: const Duration(milliseconds: 30),
    );
    await b.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(loc.watchCalls, 0);
    expect(b.locationIssue.value, LocationIssue.denied);
    b.dispose();
  });

  // ======================= فلتر دقة GPS =======================
  group('GPS accuracy', () {
    test('نقطة دقتها سيئة: بتتجاهل، التتبع مبيقفش، والنقطة الصالحة بتتقبل',
        () async {
      location.current = null; // مفيش أول نقطة، عشان نلاحظ الفلتر بوضوح
      await c.start();
      expect(c.me.value, isNull);

      location.ctrl.add(fix(30.5, 31.0, accuracy: 120)); // أسوأ من 50 م
      await pump();
      expect(c.me.value, isNull);
      expect(c.gpsAccuracyLow.value, isTrue);
      expect(c.locationIssue.value, isNull); // GPS شغال، بس الدقة ضعيفة
      expect(location.ctrl.hasListener, isTrue); // الاشتراك لسه شغال

      location.ctrl.add(fix(30.51, 31.01, accuracy: 10));
      await pump();
      expect(c.me.value, const LatLng(30.51, 31.01));
      expect(c.gpsAccuracyLow.value, isFalse);

      // نقطة سيئة بعد صالحة: نحتفظ بآخر صالحة.
      location.ctrl.add(fix(30.9, 31.9, accuracy: 300));
      await pump();
      expect(c.me.value, const LatLng(30.51, 31.01));
      expect(c.gpsAccuracyLow.value, isTrue);
    });

    test('الحد قابل للضبط (TrackingConfig.maxAcceptedAccuracyMeters)', () async {
      final b = TrackingController(
        location: location,
        routing: routing,
        customerLocation: _customer,
        config: const TrackingConfig(maxAcceptedAccuracyMeters: 200),
      );
      location.current = null;
      await b.start();
      location.ctrl.add(fix(30.5, 31.0, accuracy: 120)); // مقبولة بحد 200
      await pump();
      expect(b.me.value, const LatLng(30.5, 31.0));
      b.dispose();
    });

    test('وضع السائق: نقطة سيئة مبتدخلش في الموقع ولا طلب Routing', () async {
      location.current = null;
      final b = TrackingController(
        location: location,
        routing: routing,
        customerLocation: _customer, // driverSource == null → وضع السائق
        minRouteInterval: Duration.zero,
      );
      await b.start();
      location.ctrl.add(fix(30.55, 31.0, accuracy: 500));
      await pump();
      expect(b.driver.value, isNull);
      expect(routing.calls, 0);

      location.ctrl.add(fix(30.55, 31.0, accuracy: 8));
      await pump();
      expect(b.driver.value, isNotNull);
      expect(routing.calls, 1);
      b.dispose();
    });

    test('أول نقطة (last-known) دقتها سيئة: متتقبلش', () async {
      location.currentAccuracy = 900;
      await c.start();
      expect(c.me.value, isNull);
      expect(c.gpsAccuracyLow.value, isTrue);
    });
  });

  // ======================= حداثة الموقع =======================
  group('Freshness', () {
    test('LIVE ثم STALE ثم UNAVAILABLE حسب عمر آخر نقطة', () async {
      var now = DateTime(2026, 1, 1, 12);
      final b = TrackingController(
        location: location,
        routing: routing,
        driverSource: source,
        customerLocation: _customer,
        minRouteInterval: Duration.zero,
        tick: const Duration(milliseconds: 20),
        clock: () => now,
      );
      await b.start();
      expect(b.freshness.value, Freshness.waiting);

      source.ctrl.add(GeoFix(position: const LatLng(30.55, 31.0), updatedAt: now));
      await pump();
      expect(b.freshness.value, Freshness.live);

      now = now.add(const Duration(seconds: 31));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(b.freshness.value, Freshness.stale);

      now = now.add(const Duration(minutes: 11));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(b.freshness.value, Freshness.unavailable);

      // نقطة جديدة ترجّعه LIVE.
      source.ctrl.add(GeoFix(position: const LatLng(30.551, 31.0), updatedAt: now));
      await pump();
      expect(b.freshness.value, Freshness.live);
      b.dispose();
    });

    test('فشل مصدر السائق من غير أي نقطة = UNAVAILABLE', () async {
      await c.start();
      expect(c.freshness.value, Freshness.waiting);
      source.ctrl.addError(Exception('permission-denied'));
      await pump();
      expect(c.freshness.value, Freshness.unavailable);
    });
  });

  // ======================= الكاميرا =======================
  group('Camera commands', () {
    test('fitBounds مرة واحدة فقط عند أول سائق + عميل', () async {
      await c.start();
      expect(c.camera.value, isNull);
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      final first = c.camera.value!;
      expect(first.type, CameraCommandType.fitBounds);
      expect(first.points, [const LatLng(30.55, 31.0), _customer]);

      source.ctrl.add(fix(30.552, 31.002));
      await pump();
      expect(c.camera.value!.id, first.id); // مفيش تحريك مع كل GPS
    });

    test('بعد ما المستخدم يحرّك الخريطة: مفيش تحريك أوتوماتيك', () async {
      await c.start();
      c.userMovedCamera();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      expect(c.camera.value, isNull);
      expect(c.userControlsCamera, isTrue);
    });

    test('زر موقعي (وضع العميل): centerOnMe على موقعي الحالي', () async {
      await c.start();
      await c.focusMyLocation();
      final cmd = c.camera.value!;
      expect(cmd.type, CameraCommandType.centerOnMe);
      expect(cmd.target, const LatLng(30.55, 31.0));
      expect(cmd.zoom, c.config.focusZoom);
    });

    test('زر موقعي يشتغل حتى بعد ما المستخدم حرّك الخريطة', () async {
      await c.start();
      c.userMovedCamera();
      await c.focusMyLocation();
      expect(c.camera.value?.type, CameraCommandType.centerOnMe);
    });

    test('زر موقعي (وضع السائق): centerOnDriver', () async {
      final b = TrackingController(
        location: location,
        routing: routing,
        customerLocation: _customer,
      );
      await b.start();
      await b.focusMyLocation();
      expect(b.camera.value!.type, CameraCommandType.centerOnDriver);
      b.dispose();
    });

    test('fitAll: نقاط مميزة، ولو نقطة واحدة بس = تركيز عليها', () async {
      await c.start();
      // مفيش سائق: الوجهة + موقعي.
      c.fitAll();
      expect(c.camera.value!.type, CameraCommandType.fitBounds);
      expect(c.camera.value!.points.length, 2);

      // وضع السائق بدون وجهة: السائق = موقعي → نقطة واحدة بعد إزالة التكرار.
      final b = TrackingController(location: location, routing: routing);
      await b.start();
      b.fitAll();
      expect(b.camera.value!.type, CameraCommandType.centerOnDriver);
      b.dispose();
    });

    test('بدون وجهة: التركيز على موقعي مرة واحدة تلقائيًا', () async {
      final b = TrackingController(
        location: location,
        routing: routing,
        driverSource: source,
      );
      await b.start();
      final cmd = b.camera.value!;
      expect(cmd.type, CameraCommandType.centerOnMe);
      b.dispose();
    });
  });

  // ======================= تغيير الوجهة =======================
  group('Destination', () {
    test('setDestination: مسار الوجهة القديمة بيتجاهل والجديدة بتتطلب', () async {
      final g = GatedRouting();
      final b = TrackingController(
        location: location,
        routing: g,
        driverSource: source,
        customerLocation: _customer,
        minRouteInterval: Duration.zero,
      );
      await b.start();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      expect(g.calls, 1);

      const newDest = LatLng(30.58, 31.03);
      b.setDestination(newDest);
      await pump();
      expect(g.calls, 1); // الأول لسه معلّق (طلب واحد في الجو)

      g.pending[0].complete(_route()); // رد الوجهة القديمة
      await pump();
      expect(b.route.value, isNull); // اتجاهل
      expect(g.calls, 2); // واتطلب مسار الجديدة فورًا

      g.pending[1].complete(_route());
      await pump();
      expect(b.route.value, isNotNull);
      expect(b.destination.value, newDest);
      b.dispose();
    });

    test('setDestination: بيمسح المسار وبيصدر fitBounds', () async {
      await c.start();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      expect(c.route.value, isNotNull);
      final before = c.camera.value!.id;

      c.setDestination(const LatLng(30.6, 31.1));
      expect(c.route.value, isNull);
      expect(c.progress.value, isNull);
      expect(c.camera.value!.id, greaterThan(before));
      expect(c.camera.value!.type, CameraCommandType.fitBounds);
      await pump();
      expect(c.route.value, isNotNull); // اتحسب للوجهة الجديدة
    });

    test('moveCamera:false مبيحرّكش الكاميرا', () async {
      await c.start();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      final before = c.camera.value!.id;
      c.setDestination(const LatLng(30.6, 31.1), moveCamera: false);
      expect(c.camera.value!.id, before);
    });
  });

  // ======================= المسافة والوقت المتبقيين =======================
  group('Route progress', () {
    test('بيتحدث محليًا مع حركة السائق من غير Routing جديد', () async {
      final b = TrackingController(
        location: location,
        routing: routing,
        driverSource: source,
        customerLocation: _customer,
        minRouteInterval: Duration.zero,
        rerouteDistanceMeters: 1e9,
        offRouteMeters: 1e9,
      );
      await b.start();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      expect(routing.calls, 1);
      expect(b.progress.value!.distanceMeters, closeTo(1000, 1));
      expect(b.progress.value!.durationSeconds, closeTo(120, 0.5));

      source.ctrl.add(fix(30.555, 31.005)); // منتصف المسار
      await pump();
      expect(routing.calls, 1);
      expect(b.progress.value!.distanceMeters, closeTo(500, 15));
      expect(b.progress.value!.durationSeconds, closeTo(60, 2));

      source.ctrl.add(fix(30.56, 31.01)); // وصل
      await pump();
      expect(b.progress.value!.distanceMeters, closeTo(0, 5));
      b.dispose();
    });

    test('مسار قديم (maxRouteAge): بيتعاد حسابه بس لو السائق اتحرك', () async {
      var now = DateTime(2026, 1, 1, 12);
      final b = TrackingController(
        location: location,
        routing: routing,
        driverSource: source,
        customerLocation: _customer,
        minRouteInterval: Duration.zero,
        rerouteDistanceMeters: 1e9,
        offRouteMeters: 1e9,
        maxRouteAge: const Duration(minutes: 3),
        staleRouteMinMoveMeters: 20,
        clock: () => now,
      );
      await b.start();
      source.ctrl.add(fix(30.55, 31.0));
      await pump();
      expect(routing.calls, 1);

      now = now.add(const Duration(minutes: 4));
      source.ctrl.add(fix(30.55, 31.0)); // واقف في مكانه: مفيش سبب
      await pump();
      expect(routing.calls, 1);

      source.ctrl.add(fix(30.5503, 31.0)); // اتحرك ~33 م والمسار قديم
      await pump();
      expect(routing.calls, 2);
      b.dispose();
    });
  });

  test('نقطة مكررة (نفس الموقع): مفيش Routing جديد ولا أمر كاميرا جديد', () async {
    await c.start();
    source.ctrl.add(fix(30.55, 31.0));
    await pump();
    final cam = c.camera.value!.id;
    expect(routing.calls, 1);
    for (var i = 0; i < 5; i++) {
      source.ctrl.add(fix(30.55, 31.0));
    }
    await pump();
    expect(routing.calls, 1);
    expect(c.camera.value!.id, cam);
  });
}
