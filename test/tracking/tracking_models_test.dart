import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/models/selected_location.dart';
import 'package:wasalha/features/tracking/models/tracking_models.dart';

GeoFix _fixAt(DateTime t) => GeoFix(position: const LatLng(30.5, 31.0), updatedAt: t);

void main() {
  final now = DateTime(2026, 1, 1, 12, 0, 0);

  group('computeFreshness', () {
    test('مفيش نقطة = WAITING، ولو المصدر فاشل = UNAVAILABLE', () {
      expect(computeFreshness(fix: null, now: now), Freshness.waiting);
      expect(computeFreshness(fix: null, now: now, sourceFailed: true),
          Freshness.unavailable);
    });

    test('LIVE لحد 30 ثانية (الحد نفسه لسه LIVE)', () {
      expect(computeFreshness(fix: _fixAt(now), now: now), Freshness.live);
      expect(
        computeFreshness(
            fix: _fixAt(now.subtract(const Duration(seconds: 30))), now: now),
        Freshness.live,
      );
    });

    test('STALE بعد 30 ثانية ولحد 10 دقايق', () {
      expect(
        computeFreshness(
            fix: _fixAt(now.subtract(const Duration(seconds: 31))), now: now),
        Freshness.stale,
      );
      expect(
        computeFreshness(
            fix: _fixAt(now.subtract(const Duration(minutes: 10))), now: now),
        Freshness.stale,
      );
    });

    test('UNAVAILABLE بعد 10 دقايق', () {
      expect(
        computeFreshness(
            fix: _fixAt(now.subtract(const Duration(minutes: 10, seconds: 1))),
            now: now),
        Freshness.unavailable,
      );
    });

    test('فرق ساعة الأجهزة (نقطة من "المستقبل") مبيعتبرهاش قديمة', () {
      expect(
        computeFreshness(
            fix: _fixAt(now.add(const Duration(minutes: 5))), now: now),
        Freshness.live,
      );
    });

    test('العتبات قابلة للضبط من TrackingConfig', () {
      const cfg = TrackingConfig(
        liveThreshold: Duration(seconds: 5),
        unavailableThreshold: Duration(seconds: 20),
      );
      final f = _fixAt(now.subtract(const Duration(seconds: 10)));
      expect(computeFreshness(fix: f, now: now, config: cfg), Freshness.stale);
      expect(
        computeFreshness(
            fix: _fixAt(now.subtract(const Duration(seconds: 21))),
            now: now,
            config: cfg),
        Freshness.unavailable,
      );
    });
  });

  test('القيم الافتراضية في TrackingConfig', () {
    const cfg = TrackingConfig();
    expect(cfg.maxAcceptedAccuracyMeters, 50);
    expect(cfg.liveThreshold, const Duration(seconds: 30));
    expect(cfg.unavailableThreshold, const Duration(minutes: 10));
    expect(cfg.pickDebounce, const Duration(milliseconds: 500));
  });

  test('SelectedLocation: المساواة و latLng', () {
    const a = SelectedLocation(latitude: 30.5, longitude: 31.0, address: 'x');
    const b = SelectedLocation(latitude: 30.5, longitude: 31.0, address: 'x');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.latLng, const LatLng(30.5, 31.0));
    expect(
      a == const SelectedLocation(latitude: 30.5, longitude: 31.0, address: 'y'),
      isFalse,
    );
  });

  test('RouteProgress: المساواة بالقيمة (بتقلل إعادة بناء الواجهة)', () {
    const a = RouteProgress(distanceMeters: 100, durationSeconds: 10);
    const b = RouteProgress(distanceMeters: 100, durationSeconds: 10);
    expect(a, b);
    expect(
      a == const RouteProgress(distanceMeters: 101, durationSeconds: 10),
      isFalse,
    );
  });
}
