import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../core/map/map_config.dart';
import '../theme/app_colors.dart';

/// نسخة Flutter من إعداد خريطة Leaflet المستخدم في نسخة الويب:
/// التايلز من MapConfig (مكان واحد للتغيير).
class WasalhaMap extends StatefulWidget {
  final ll.LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<ll.LatLng> routeGeometry; // [lat, lng] نفس الأصل
  final List<ll.LatLng>? fitPoints; // مكافئ MapAutoFit
  final bool showControls;

  /// true: الكاميرا بتتبع [center] (موقع الكابتن) لما مفيش fitPoints،
  /// طالما المستخدم مش بيحرّك الخريطة بإيده.
  final bool followCenter;
  const WasalhaMap({
    super.key,
    required this.center,
    this.zoom = 15,
    this.markers = const [],
    this.routeGeometry = const [],
    this.fitPoints,
    this.showControls = false, // أزرار التكبير: اختيارية ومقفولة افتراضياً
    this.followCenter = false,
  });

  @override
  State<WasalhaMap> createState() => _WasalhaMapState();
}

class _WasalhaMapState extends State<WasalhaMap> {
  final MapController _controller = MapController();
  bool _ready = false;
  bool _userMoved = false;
  String? _fitKey;
  int _tileErrors = 0;
  bool _useFallbackTiles = false;

  // مفتاح الوجهة: بنعيد ضبط الكاميرا بس لما الوجهة تتغير، مش مع كل تحديث
  // لموقع الكابتن — عشان المستخدم يقدر يحرّك الخريطة بحرية.
  String? _keyFor(List<ll.LatLng>? pts) {
    if (pts == null || pts.length < 2) return null;
    return pts
        .skip(1)
        .map((p) =>
            '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}')
        .join('|');
  }

  @override
  void didUpdateWidget(covariant WasalhaMap old) {
    super.didUpdateWidget(old);
    final k = _keyFor(widget.fitPoints);
    if (_ready && k != null && k != _fitKey) _fit();
    if (_ready &&
        widget.followCenter &&
        !_userMoved &&
        (widget.fitPoints == null || widget.fitPoints!.length < 2) &&
        (old.center.latitude != widget.center.latitude ||
            old.center.longitude != widget.center.longitude)) {
      try {
        _controller.move(widget.center, _controller.camera.zoom);
      } catch (_) {}
    }
  }

  void _fit() {
    final pts = widget.fitPoints;
    if (pts == null || pts.length < 2) return;
    _fitKey = _keyFor(pts);
    try {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(50),
          maxZoom: 17,
        ),
      );
    } catch (_) {
      // الخريطة لسه مش جاهزة (fitCamera قبل أول رسم)، هنعيد المحاولة مع التحديث الجاي
    }
  }

  void _recenter() {
    _userMoved = false;
    final pts = widget.fitPoints;
    if (pts != null && pts.length >= 2) {
      _fit();
    } else {
      _controller.move(widget.center, widget.zoom);
    }
  }

  void _zoomBy(double d) {
    final cam = _controller.camera;
    _controller.move(cam.center, (cam.zoom + d).clamp(5.0, 18.0));
  }

  Widget _ctrlButton(IconData icon, VoidCallback onTap) => Material(
        color: C.white,
        elevation: 3,
        shadowColor: const Color(0x33000000),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: C.slate800),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            backgroundColor: const Color(0xFFE9EEF1),
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            minZoom: 5,
            maxZoom: 18,
            onMapReady: () {
              _ready = true;
              _fit();
            },
            onPositionChanged: (cam, hasGesture) {
              if (hasGesture) _userMoved = true;
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              key: ValueKey(_useFallbackTiles),
              urlTemplate: _useFallbackTiles
                  ? MapConfig.fallbackTileUrlTemplate
                  : MapConfig.tileUrlTemplate,
              subdomains:
                  _useFallbackTiles ? const ['a'] : MapConfig.tileSubdomains,
              retinaMode: MapConfig.retinaFor(context),
              maxNativeZoom: 19,
              userAgentPackageName: MapConfig.userAgentPackageName,
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
              // لو التايلز الأساسية فشلت كذا مرة ورا بعض: نحوّل للاحتياطية.
              errorTileCallback: (tile, error, stack) {
                if (_useFallbackTiles) return;
                if (++_tileErrors >= 6) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_useFallbackTiles) {
                      setState(() => _useFallbackTiles = true);
                    }
                  });
                }
              },
            ),
            if (widget.routeGeometry.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: widget.routeGeometry,
                  color: C.emerald600.withOpacity(0.9),
                  strokeWidth: 6,
                  borderColor: C.white,
                  borderStrokeWidth: 2,
                ),
              ]),
            MarkerLayer(markers: widget.markers, rotate: false),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution(MapConfig.attribution),
              ],
            ),
          ],
        ),
        if (widget.showControls)
          Positioned(
            left: 12,
            bottom: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ctrlButton(Icons.add_rounded, () => _zoomBy(1)),
                const SizedBox(height: 8),
                _ctrlButton(Icons.remove_rounded, () => _zoomBy(-1)),
                const SizedBox(height: 8),
                _ctrlButton(Icons.my_location_rounded, _recenter),
              ],
            ),
          ),
      ],
    );
  }
}

/// أيقونة الكابتن (🛵) — مكافئ driverIcon في CustomerDashboard.tsx
Marker driverMarker(ll.LatLng point) {
  return Marker(
    point: point,
    width: 48,
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: C.emerald500.withOpacity(0.20), shape: BoxShape.circle),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.emerald500, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 10)),
            ],
          ),
          child: const Text('🛵', style: TextStyle(fontSize: 16, height: 1)),
        ),
        Positioned(
          bottom: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: C.emerald600,
              shape: BoxShape.circle,
              border: Border.all(color: C.white, width: 2),
            ),
          ),
        ),
      ],
    ),
  );
}

/// أيقونة بيت العميل (🏠) — مكافئ customerHomeIcon
Marker customerHomeMarker(ll.LatLng point) => Marker(
      point: point,
      width: 45,
      height: 45,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.white,
          shape: BoxShape.circle,
          border: Border.all(color: C.blue600, width: 4),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: const Center(child: Text('🏠', style: TextStyle(fontSize: 16))),
      ),
    );

/// أيقونة نقطة الاستلام (🏪) — مكافئ pickupPointIcon
Marker pickupPointMarker(ll.LatLng point) => Marker(
      point: point,
      width: 45,
      height: 45,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.white,
          shape: BoxShape.circle,
          border: Border.all(color: C.rose500, width: 4),
          boxShadow: [Sh_ring],
        ),
        child: const Center(child: Text('🏪', style: TextStyle(fontSize: 16))),
      ),
    );

const Sh_ring = BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8));
