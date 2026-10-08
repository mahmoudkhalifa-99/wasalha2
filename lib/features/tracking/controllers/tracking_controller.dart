import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/geo_utils.dart';
import '../../../core/map/routing_service.dart';
import '../models/tracking_models.dart';
import '../services/driver_location_source.dart';
import '../services/location_service.dart';

/// منسّق التتبع. كل حالة معروضة في [ValueNotifier] مستقل، فالـ Widgets
/// بتسمع للجزء اللي محتاجاه بس — الخريطة نفسها ما بتتعملهاش rebuild مع كل GPS.
///
/// الوضعين:
///  • العميل: [driverSource] != null → موقع السائق جاي من المصدر.
///  • السائق: [driverSource] == null → الجهاز هو السائق (GPS) ولو فيه
///    [publisher] بيبث الموقع.
class TrackingController {
  TrackingController({
    required this.location,
    required this.routing,
    this.driverSource,
    this.publisher,
    LatLng? customerLocation,
    this.config = const TrackingConfig(),
    this.minRouteInterval = const Duration(seconds: 10),
    this.rerouteDistanceMeters = 75,
    this.offRouteMeters = 60,
    this.maxRouteAge = const Duration(minutes: 3),
    this.staleRouteMinMoveMeters = 20,
    this.tick = const Duration(seconds: 10),
    this.retryBackoffBase = const Duration(seconds: 10),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        destination = ValueNotifier<LatLng?>(customerLocation);

  final LocationService location;
  final RoutingService routing;
  final DriverLocationSource? driverSource;
  final DriverLocationPublisher? publisher;

  /// عتبات التتبع (دقة GPS، حداثة الموقع، debounce الاختيار…).
  final TrackingConfig config;

  /// الوجهة الحالية (موقع العميل أو الموقع المعتمد من الخريطة).
  final ValueNotifier<LatLng?> destination;
  LatLng? get customerLocation => destination.value;

  /// أقل فاصل بين طلبين لـ Routing API.
  final Duration minRouteInterval;

  /// إعادة حساب المسار لما السائق يتحرك المسافة دي من نقطة آخر حساب.
  final double rerouteDistanceMeters;

  /// أو لما يبعد عن خط المسار بالمسافة دي.
  final double offRouteMeters;

  /// المسار الأقدم من كده بيتعاد حسابه (لو السائق اتحرك [staleRouteMinMoveMeters]
  /// على الأقل — السائق الواقف مبيستهلكش طلبات).
  final Duration maxRouteAge;
  final double staleRouteMinMoveMeters;

  /// فاصل مؤقّت المحاولات (إعادة المحاولة بعد فشل / إعادة الاشتراك).
  final Duration tick;

  /// أساس الـ backoff التصاعدي بعد فشل Routing / اشتراك السائق
  /// (×2 لكل فشل متتالي، بحد أقصى ×16؛ و429 بيزوّد مرحلة).
  final Duration retryBackoffBase;

  final DateTime Function() _clock;

  bool get isDriverMode => driverSource == null;

  // ---------------- الحالة (كل واحدة مستقلة) ----------------
  final ValueNotifier<TrackingStatus> status =
      ValueNotifier<TrackingStatus>(TrackingStatus.starting);
  final ValueNotifier<GeoFix?> driver = ValueNotifier<GeoFix?>(null);
  final ValueNotifier<LatLng?> me = ValueNotifier<LatLng?>(null);
  final ValueNotifier<RouteResult?> route = ValueNotifier<RouteResult?>(null);
  final ValueNotifier<LocationIssue?> locationIssue =
      ValueNotifier<LocationIssue?>(null);

  /// false لما آخر طلب شبكة فشل بسبب الاتصال. بيرجع true أول نجاح.
  final ValueNotifier<bool> networkOk = ValueNotifier<bool>(true);

  /// true لما حساب المسار فشل (نحتفظ بآخر مسار معروف إن وُجد).
  final ValueNotifier<bool> routeUnavailable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> routeLoading = ValueNotifier<bool>(false);

  /// حداثة موقع السائق: LIVE / STALE / WAITING / UNAVAILABLE.
  final ValueNotifier<Freshness> freshness =
      ValueNotifier<Freshness>(Freshness.waiting);

  /// المسافة/الوقت المتبقيين، بيتحدثوا محليًا مع حركة السائق.
  final ValueNotifier<RouteProgress?> progress =
      ValueNotifier<RouteProgress?>(null);

  /// true لما آخر نقطة GPS دقتها أسوأ من الحد المسموح (بنحتفظ بآخر نقطة صالحة).
  final ValueNotifier<bool> gpsAccuracyLow = ValueNotifier<bool>(false);

  /// أوامر الكاميرا (بينفّذها الـ Widget بـ MapController).
  final ValueNotifier<CameraCommand?> camera =
      ValueNotifier<CameraCommand?>(null);

  // ---------------- داخلي ----------------
  StreamSubscription<GeoFix>? _posSub;
  StreamSubscription<GeoFix>? _driverSub;
  Timer? _ticker;
  Timer? _pendingTimer;

  bool _started = false;
  bool _disposed = false;
  bool _locationStarting = false;
  bool _inFlight = false;
  bool _routeFailed = false;
  bool _driverNeedsResubscribe = false;
  bool _posDead = false; // اشتراك GPS اتقفل (خطأ) ومحتاج إعادة اشتراك
  int _routeFailures = 0;
  DateTime? _routeRetryAt;
  int _driverFailures = 0;
  DateTime? _driverRetryAt;
  DateTime? _lastRequestAt;
  DateTime? _routeComputedAt;
  LatLng? _routeOrigin;
  int _cameraSeq = 0;
  bool _userControlsCamera = false;
  bool _autoCameraDone = false;

  /// مسافة خط مستقيم بين السائق والعميل (للعرض التقريبي لو المسار مش متاح).
  double? get straightDistanceMeters {
    final d = driver.value?.position;
    final c = destination.value;
    if (d == null || c == null) return null;
    return distanceMeters(d, c);
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _ticker = Timer.periodic(tick, (_) => _onTick());
    if (!isDriverMode) {
      status.value = TrackingStatus.waitingForDriver;
      _listenDriver();
    }
    _refreshFreshness();
    await _startLocation();
  }

  /// يعيد محاولة تحديد الموقع (بعد رفض صلاحية أو قفل GPS).
  Future<void> retryLocation() => _startLocation();

  /// لزر "موقعي": يرجّع الموقع الحالي (ويحاول يجهّز الصلاحية لو ناقصة).
  Future<LatLng?> locateMe() async {
    if (_disposed) return null;
    if (locationIssue.value != null || _posSub == null) {
      await _startLocation();
    }
    if (_disposed) return null;
    if (me.value == null) {
      final cur = await location.currentFix();
      if (_disposed) return null;
      if (cur != null) _applyMyFix(cur, publish: false);
    }
    return me.value;
  }

  Future<void> openLocationSettings() async {
    final issue = locationIssue.value;
    if (issue == null) return;
    if (issue == LocationIssue.denied || issue == LocationIssue.unavailable) {
      await retryLocation();
    } else {
      await location.openSettings(issue);
    }
  }

  // ---------------- الموقع ----------------
  Future<void> _startLocation() async {
    if (_locationStarting || _disposed) return;
    _locationStarting = true;
    try {
      final issue = await location.ensureReady();
      if (_disposed) return;
      _setIssue(issue);
      if (issue != null) {
        await _posSub?.cancel();
        _posSub = null;
        _posDead = true; // الـ tick يعيد المحاولة لو المشكلة GPS مقفول/مؤقتة
        if (isDriverMode) status.value = TrackingStatus.locationBlocked;
        return;
      }
      if (isDriverMode && status.value == TrackingStatus.locationBlocked) {
        status.value = TrackingStatus.starting;
      }
      // اشتراك واحد فقط: بنلغي القديم قبل ما نعمل جديد.
      await _posSub?.cancel();
      if (_disposed) return;
      _posSub = location.watch().listen(
        _applyMyFix,
        onError: (Object e) {
          debugPrint('location stream error: $e');
          if (_disposed) return;
          _posDead = true; // cancelOnError: الاشتراك اتقفل — الـ tick يعيده
          _setIssue(
              e is LocationIssueException ? e.issue : LocationIssue.unavailable);
          if (isDriverMode) status.value = TrackingStatus.locationBlocked;
        },
        cancelOnError: true,
      );
      _posDead = false;
      final cur = await location.currentFix();
      if (_disposed) return;
      if (cur != null && me.value == null) {
        // أول نقطة للعرض بس: ممكن تكون last-known قديمة، فما بنبثهاش لـ Firestore.
        _applyMyFix(cur, publish: false);
      }
    } finally {
      _locationStarting = false;
    }
  }

  bool _isAccurate(GeoFix f) {
    final a = f.accuracy;
    return a == null || a <= config.maxAcceptedAccuracyMeters;
  }

  void _setIssue(LocationIssue? issue) {
    if (_disposed) return;
    locationIssue.value = issue;
    _refreshFreshness();
  }

  void _applyMyFix(GeoFix f, {bool publish = true}) {
    if (_disposed) return;
    // وصول نقطة = الـ GPS شغال، حتى لو دقتها ضعيفة.
    if (locationIssue.value != null) _setIssue(null);
    if (!_isAccurate(f)) {
      // نتجاهلها في الموقع/المسار/البث ونحتفظ بآخر نقطة صالحة (التتبع مبيقفش).
      if (!gpsAccuracyLow.value) gpsAccuracyLow.value = true;
      return;
    }
    if (gpsAccuracyLow.value) gpsAccuracyLow.value = false;
    me.value = f.position;
    if (isDriverMode) {
      _onDriverFix(f);
      if (publish) publisher?.publish(f);
    } else {
      _autoCamera(); // وضع العميل بدون وجهة: نركّز على موقعي مرة واحدة
    }
  }

  // ---------------- السائق ----------------
  void _listenDriver() {
    final src = driverSource;
    if (src == null || _disposed) return;
    _driverSub?.cancel();
    _driverNeedsResubscribe = false;
    _driverSub = src.watch().listen(
      _onDriverFix,
      onError: (Object e) {
        debugPrint('driver stream error: $e');
        _driverFailures++;
        _driverRetryAt = _clock().add(_backoff(_driverFailures));
        _driverNeedsResubscribe = true; // هنعيد الاشتراك في أول tick بعد الـ backoff
        _refreshFreshness();
      },
      cancelOnError: true,
    );
  }

  void _onDriverFix(GeoFix f) {
    if (_disposed) return;
    _driverFailures = 0;
    _driverRetryAt = null;
    final prev = driver.value;
    double? bearing = f.bearing;
    if (bearing == null &&
        prev != null &&
        distanceMeters(prev.position, f.position) >= 3) {
      bearing = bearingDegrees(prev.position, f.position);
    }
    bearing ??= prev?.bearing;
    driver.value = GeoFix(
      position: f.position,
      updatedAt: f.updatedAt,
      bearing: bearing,
      accuracy: f.accuracy,
    );
    status.value = TrackingStatus.live;
    _refreshFreshness();
    _autoCamera();
    _maybeReroute();
    _updateProgress();
  }

  /// يحدّث [freshness] من عمر آخر نقطة (بيتنادى مع كل نقطة ومع كل tick).
  void _refreshFreshness() {
    if (_disposed) return;
    final f = computeFreshness(
      fix: driver.value,
      now: _clock(),
      config: config,
      sourceFailed:
          _driverFailures > 0 || (isDriverMode && locationIssue.value != null),
    );
    if (f != freshness.value) freshness.value = f;
  }

  /// المسافة/الوقت المتبقيين من المسار الحالي، من غير Routing API.
  void _updateProgress() {
    if (_disposed) return;
    final r = route.value;
    final d = driver.value;
    if (r == null) {
      if (progress.value != null) progress.value = null;
      return;
    }
    final frac = (d == null || r.points.length < 2)
        ? 1.0
        : remainingRouteFraction(d.position, r.points);
    progress.value = RouteProgress(
      distanceMeters: r.distanceMeters * frac,
      durationSeconds: r.durationSeconds * frac,
    );
  }

  // ---------------- المسار ----------------
  void _onTick() {
    if (_disposed) return;
    final now = _clock();
    _refreshFreshness();
    if (_driverNeedsResubscribe) {
      final at = _driverRetryAt;
      if (at == null || !now.isBefore(at)) _listenDriver();
    }
    // GPS اتقفل بسبب خطأ مؤقت أو GPS مقفول: نعيد الاشتراك تلقائيًا.
    // (الصلاحية المرفوضة محتاجة المستخدم، فمش بنكرر طلبها كل tick.)
    if (_posDead && !_locationStarting) {
      final i = locationIssue.value;
      if (i == LocationIssue.unavailable || i == LocationIssue.serviceDisabled) {
        _startLocation();
      }
    }
    if (_routeFailed) _maybeReroute(force: true);
  }

  Duration _backoff(int failures, {int extra = 0}) {
    final e = failures + extra - 1;
    final capped = e < 0 ? 0 : (e > 4 ? 4 : e);
    return retryBackoffBase * (1 << capped);
  }

  void _maybeReroute({bool force = false}) {
    if (_disposed) return;
    final d = driver.value;
    final dest = destination.value;
    if (d == null || dest == null) return;

    final current = route.value;
    var need = force || current == null;
    if (!need) {
      final origin = _routeOrigin;
      final moved =
          origin == null ? double.infinity : distanceMeters(origin, d.position);
      final off =
          distanceToPolylineMeters(d.position, current.points) > offRouteMeters;
      final at = _routeComputedAt;
      final aged = at != null &&
          _clock().difference(at) >= maxRouteAge &&
          moved >= staleRouteMinMoveMeters;
      need = moved >= rerouteDistanceMeters || off || aged;
    }
    if (!need || _inFlight) return;
    final retryAt = _routeRetryAt;
    if (retryAt != null && _clock().isBefore(retryAt)) return; // backoff

    // Throttle: لو لسه بدري، نأجّل لطلب واحد في آخر الفترة.
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = _clock().difference(last);
      if (elapsed < minRouteInterval) {
        _pendingTimer ??= Timer(minRouteInterval - elapsed, () {
          _pendingTimer = null;
          _maybeReroute(force: force);
        });
        return;
      }
    }
    _requestRoute(d.position, dest);
  }

  Future<void> _requestRoute(LatLng from, LatLng to) async {
    _inFlight = true;
    _lastRequestAt = _clock();
    routeLoading.value = true;
    var succeeded = false;
    var discarded = false;
    try {
      final res = await routing.getRoute(start: from, destination: to);
      if (_disposed) return;
      if (destination.value != to) {
        // الوجهة اتغيّرت أثناء الانتظار: الرد ده لمسار قديم — نتجاهله.
        discarded = true;
      } else {
        _routeOrigin = from;
        _routeComputedAt = _clock();
        route.value = res;
        networkOk.value = true;
        routeUnavailable.value = false;
        _routeFailed = false;
        _routeFailures = 0;
        _routeRetryAt = null;
        succeeded = true;
        _updateProgress();
      }
    } on RoutingException catch (e) {
      debugPrint('routing failed: $e');
      if (_disposed) return;
      if (destination.value != to) {
        discarded = true;
      } else {
        if (e.isConnectivity) networkOk.value = false;
        routeUnavailable.value = true; // آخر مسار معروف يفضل معروض
        _routeFailed = true;
        _routeFailures++;
        _routeRetryAt = _clock().add(_backoff(_routeFailures,
            extra: e.kind == RoutingFailure.rateLimited ? 1 : 0));
      }
    } catch (e) {
      debugPrint('routing unexpected error: $e');
      if (_disposed) return;
      if (destination.value != to) {
        discarded = true;
      } else {
        routeUnavailable.value = true;
        _routeFailed = true;
        _routeFailures++;
        _routeRetryAt = _clock().add(_backoff(_routeFailures));
      }
    } finally {
      _inFlight = false;
      if (!_disposed) routeLoading.value = false;
    }
    if (_disposed) return;
    // الوجهة اتغيّرت: نطلب مسار الوجهة الجديدة فورًا.
    if (discarded) {
      _maybeReroute(force: true);
      return;
    }
    // السائق ممكن يكون اتحرك أثناء انتظار الرد: الرد اتحسب من نقطة قديمة.
    // نفحص تاني بعد ما _inFlight اتقفل (الـ throttle بيحكم التوقيت).
    if (succeeded) _maybeReroute();
  }

  /// يعتمد وجهة جديدة (أو null لإزالتها). ده الوقت الوحيد اللي اختيار موقع
  /// جديد بيتحوّل فيه لطلب Routing.
  void setDestination(LatLng? p, {bool moveCamera = true}) {
    if (_disposed) return;
    destination.value = p;
    route.value = null;
    progress.value = null;
    _routeOrigin = null;
    _routeComputedAt = null;
    _routeFailed = false;
    _routeFailures = 0;
    _routeRetryAt = null;
    _lastRequestAt = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    routeUnavailable.value = false;
    if (moveCamera) fitAll(); // المستخدم هو اللي غيّر الوجهة: تحريك الكاميرا مقصود
    _maybeReroute(force: true);
  }

  // ---------------- الكاميرا (أوامر فقط — التنفيذ في الـ Widget) ----------------
  /// الـ Widget بينادي عليها لما المستخدم يحرّك الخريطة بإيده. من بعدها ما فيش
  /// تحريك أوتوماتيك للكاميرا.
  void userMovedCamera() => _userControlsCamera = true;
  bool get userControlsCamera => _userControlsCamera;

  void _emit(CameraCommandType type,
      {List<LatLng> points = const [], LatLng? target, double? zoom}) {
    if (_disposed) return;
    camera.value = CameraCommand(
      id: ++_cameraSeq,
      type: type,
      points: points,
      target: target,
      zoom: zoom,
    );
  }

  /// ضبط الكاميرا أوتوماتيك مرة واحدة فقط، ومش بعد ما المستخدم يمسك الخريطة.
  void _autoCamera() {
    if (_userControlsCamera || _autoCameraDone) return;
    final d = driver.value?.position;
    final cu = destination.value;
    final m = me.value;
    if (d != null && cu != null) {
      _emit(CameraCommandType.fitBounds, points: [d, cu]);
      _autoCameraDone = true;
    } else if (cu == null && d != null) {
      _emit(CameraCommandType.centerOnDriver, target: d, zoom: config.focusZoom);
      _autoCameraDone = true;
    } else if (cu == null && m != null) {
      _emit(CameraCommandType.centerOnMe, target: m, zoom: config.focusZoom);
      _autoCameraDone = true;
    }
  }

  /// "عرض الطريق كاملًا": السائق + الوجهة (+ موقعي لو ناقص).
  void fitAll() {
    final pts = <LatLng>[];
    void add(LatLng? p) {
      if (p != null && !pts.contains(p)) pts.add(p);
    }

    add(driver.value?.position);
    add(destination.value);
    if (pts.length < 2) add(me.value);
    if (pts.length >= 2) {
      _emit(CameraCommandType.fitBounds, points: pts);
    } else if (pts.length == 1) {
      final p = pts.first;
      final type = driver.value?.position == p
          ? CameraCommandType.centerOnDriver
          : (destination.value == p
              ? CameraCommandType.centerOnSelectedLocation
              : CameraCommandType.centerOnMe);
      _emit(type, target: p, zoom: config.focusZoom);
    }
  }

  /// زر "موقعي": GPS الحالي ثم تركيز الكاميرا (على السائق في وضع السائق).
  Future<void> focusMyLocation() async {
    final p = await locateMe();
    if (_disposed || p == null) return;
    _emit(
      isDriverMode ? CameraCommandType.centerOnDriver : CameraCommandType.centerOnMe,
      target: p,
      zoom: config.focusZoom,
    );
  }

  /// تركيز على الوجهة/الموقع المحدد.
  void focusDestination() {
    final p = destination.value;
    if (p == null) return;
    _emit(CameraCommandType.centerOnSelectedLocation,
        target: p, zoom: config.focusZoom);
  }

  // ---------------- التنظيف ----------------
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _pendingTimer?.cancel();
    _posSub?.cancel();
    _driverSub?.cancel();
    publisher?.close();
    _ticker = null;
    _pendingTimer = null;
    _posSub = null;
    _driverSub = null;
    status.dispose();
    driver.dispose();
    me.dispose();
    route.dispose();
    locationIssue.dispose();
    networkOk.dispose();
    routeUnavailable.dispose();
    routeLoading.dispose();
    destination.dispose();
    freshness.dispose();
    progress.dispose();
    gpsAccuracyLow.dispose();
    camera.dispose();
  }
}
