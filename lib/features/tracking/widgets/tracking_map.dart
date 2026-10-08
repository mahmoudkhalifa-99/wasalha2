import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/map_config.dart';
import '../../../core/map/routing_service.dart';
import '../../../theme/app_colors.dart';
import '../controllers/tracking_controller.dart';
import '../models/tracking_models.dart';
import 'animated_driver_marker.dart';
import 'center_update_scheduler.dart';

/// الخريطة فقط: instance واحد من FlutterMap + MapController طول عمر الـ State.
///
/// ملهاش أي منطق أعمال: بتنفّذ أوامر الكاميرا ([CameraCommand]) اللي بيصدرها
/// الـ [TrackingController]، وبتبلّغه لما المستخدم يحرّك الخريطة بإيده.
/// تحديثات GPS/المسار بتوصل لطبقات صغيرة بـ ValueListenableBuilder
/// (مفيش rebuild للخريطة ولا للتايلز).
class TrackingMap extends StatefulWidget {
  const TrackingMap({
    super.key,
    required this.controller,
    this.pickMode,
    this.onCenterChanged,
    this.routeStyle = MapConfig.routeStyle,
  });

  final TrackingController controller;

  /// true = وضع اختيار الموقع: مركز الخريطة بيتبلّغ عنه عبر [onCenterChanged].
  final ValueListenable<bool>? pickMode;
  final ValueChanged<LatLng>? onCenterChanged;
  final RouteStyle routeStyle;

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<TrackingMap> {
  final MapController _map = MapController();
  final ValueNotifier<bool> _ready = ValueNotifier<bool>(false);
  int _lastCommandId = 0;

  /// تحديثات مركز الخريطة بتروح للـ picker post-frame فقط (مش من جوه
  /// onPositionChanged مباشرة).
  late final CenterUpdateScheduler _centerScheduler = CenterUpdateScheduler(
    onCenter: (c) => widget.onCenterChanged?.call(c),
    isActive: () => widget.pickMode?.value == true,
  );

  TrackingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.camera.addListener(_onCamera);
    widget.pickMode?.addListener(_onPickMode);
  }

  @override
  void didUpdateWidget(covariant TrackingMap old) {
    super.didUpdateWidget(old);
    if (old.pickMode != widget.pickMode) {
      old.pickMode?.removeListener(_onPickMode);
      widget.pickMode?.addListener(_onPickMode);
    }
  }

  @override
  void dispose() {
    _c.camera.removeListener(_onCamera);
    widget.pickMode?.removeListener(_onPickMode);
    _centerScheduler.dispose(); // أي callback مؤجّل بيتجاهل بعد كده
    _ready.dispose();
    _map.dispose();
    super.dispose();
  }

  // ---------------- أوامر الكاميرا ----------------
  void _onCamera() {
    if (!_ready.value) return; // هتتنفّذ أول ما الخريطة تجهز
    final cmd = _c.camera.value;
    if (cmd == null || cmd.id == _lastCommandId) return;
    _lastCommandId = cmd.id;
    _execute(cmd);
  }

  void _execute(CameraCommand cmd) {
    try {
      switch (cmd.type) {
        case CameraCommandType.fitBounds:
          if (cmd.points.length >= 2) {
            _map.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(cmd.points),
              padding: _fitPadding(),
              maxZoom: MapConfig.fitMaxZoom,
            ));
          } else if (cmd.points.length == 1) {
            _map.move(cmd.points.first, cmd.zoom ?? 16);
          }
        case CameraCommandType.centerOnDriver:
        case CameraCommandType.centerOnMe:
        case CameraCommandType.centerOnSelectedLocation:
          final t = cmd.target;
          if (t != null) _map.move(t, cmd.zoom ?? 16);
      }
    } catch (e) {
      debugPrint('camera command failed: $e');
    }
  }

  /// هوامش fitBounds متناسبة مع حجم الشاشة (عشان الشاشات الصغيرة ما يطلعش
  /// منها مساحة سالبة)، والأسفل أكبر عشان الـ Bottom Sheet.
  EdgeInsets _fitPadding() {
    final size = MediaQuery.sizeOf(context);
    final side = math.min(MapConfig.fitSidePadding, size.width * 0.12);
    final top = math.min(MapConfig.fitTopPadding, size.height * 0.16);
    final bottom = math.min(MapConfig.fitBottomPadding, size.height * 0.34);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  // ---------------- وضع الاختيار ----------------
  void _onPickMode() {
    if (widget.pickMode?.value != true) {
      _centerScheduler.reset(); // خروج من الوضع
      return;
    }
    _centerScheduler.reset(); // دخول: أول مركز يتبعت حتى لو نفس القديم
    if (!_ready.value) return; // هيتبعت من onMapReady
    try {
      _centerScheduler.update(_map.camera.center);
    } catch (_) {}
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // hasGesture = المستخدم حرّك بإيده (مش أمر برمجي).
    if (hasGesture) _c.userMovedCamera();
    if (widget.pickMode?.value == true) {
      _centerScheduler.update(camera.center); // post-frame، مش متزامن
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.routeStyle;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _c.customerLocation ?? MapConfig.defaultCenter,
            initialZoom: MapConfig.defaultZoom,
            minZoom: MapConfig.minZoom,
            maxZoom: MapConfig.maxZoom,
            onMapReady: () {
              // microtask: نتجنب تعديل ValueNotifier أثناء مرحلة البناء.
              Future<void>.microtask(() {
                if (!mounted) return;
                _ready.value = true;
                _onCamera();
                _onPickMode();
              });
            },
            onPositionChanged: _onPositionChanged,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: MapConfig.tileUrlTemplate,
              subdomains: MapConfig.tileSubdomains,
              retinaMode: MapConfig.retinaFor(context),
              maxNativeZoom: 19,
              userAgentPackageName: MapConfig.userAgentPackageName,
            ),
            ValueListenableBuilder<RouteResult?>(
              valueListenable: _c.route,
              builder: (context, r, _) {
                if (r == null || r.points.length < 2) {
                  return const SizedBox.shrink();
                }
                return PolylineLayer(polylines: [
                  Polyline(
                    points: r.points,
                    color: style.color.withAlpha((style.opacity.clamp(0.0, 1.0) * 255).round()),
                    strokeWidth: style.width,
                    borderColor: style.borderColor,
                    borderStrokeWidth: style.borderWidth,
                    pattern: style.dotted
                        ? const StrokePattern.dotted()
                        : const StrokePattern.solid(),
                  ),
                ]);
              },
            ),
            ValueListenableBuilder<LatLng?>(
              valueListenable: _c.destination,
              builder: (context, cu, _) {
                if (cu == null) return const SizedBox.shrink();
                return MarkerLayer(rotate: false, markers: [
                  Marker(
                    point: cu,
                    width: 48,
                    height: 52,
                    // أعلى النقطة: سن الدبوس هو اللي على الإحداثية.
                    alignment: Alignment.topCenter,
                    child: const CustomerPinIcon(),
                  ),
                ]);
              },
            ),
            if (!_c.isDriverMode)
              ValueListenableBuilder<LatLng?>(
                valueListenable: _c.me,
                builder: (context, p, _) {
                  if (p == null) return const SizedBox.shrink();
                  return MarkerLayer(rotate: false, markers: [
                    Marker(
                      point: p,
                      width: 24,
                      height: 24,
                      child: const _MyLocationDot(),
                    ),
                  ]);
                },
              ),
            ValueListenableBuilder<GeoFix?>(
              valueListenable: _c.driver,
              builder: (context, fix, _) =>
                  ValueListenableBuilder<Freshness>(
                valueListenable: _c.freshness,
                builder: (context, f, _) => AnimatedDriverMarkerLayer(
                  fix: fix,
                  dimmed: f != Freshness.live,
                ),
              ),
            ),
          ],
        ),
        // Loading Map: لحد ما الخريطة تجهز.
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: _ready,
            builder: (context, ready, _) {
              if (ready) return const SizedBox.shrink();
              return const ColoredBox(
                color: C.slate100,
                child: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ماركر العميل/الوجهة: دبوس واضح ومختلف عن ماركر السائق.
class CustomerPinIcon extends StatelessWidget {
  const CustomerPinIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on_rounded,
      size: 48,
      color: C.rose600,
      shadows: [Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3))],
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.blue600,
        shape: BoxShape.circle,
        border: Border.all(color: C.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
