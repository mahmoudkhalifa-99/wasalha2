import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/geo_utils.dart';
import '../../../theme/app_colors.dart';
import '../models/tracking_models.dart';

/// طبقة ماركر السائق: بتحرّك الماركر بسلاسة بين آخر نقطتين (Tween) وبتدوّره
/// حسب الاتجاه — من غير ما تلمس الخريطة أو التايلز.
///
/// بتتحط جوه `ValueListenableBuilder` على `controller.driver`، فالـ rebuild
/// بيحصل على الطبقة دي بس.
class AnimatedDriverMarkerLayer extends StatefulWidget {
  const AnimatedDriverMarkerLayer({
    super.key,
    required this.fix,
    this.dimmed = false,
    this.duration = const Duration(milliseconds: 900),
  });

  final GeoFix? fix;

  /// true لما الموقع قديم/غير متاح: الماركر بيظهر رمادي بدل الأخضر.
  final bool dimmed;
  final Duration duration;

  @override
  State<AnimatedDriverMarkerLayer> createState() =>
      _AnimatedDriverMarkerLayerState();
}

class _AnimatedDriverMarkerLayerState extends State<AnimatedDriverMarkerLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  LatLng? _from;
  LatLng? _to;
  double _fromB = 0;
  double _toB = 0;

  @override
  void initState() {
    super.initState();
    final f = widget.fix;
    if (f != null) {
      _from = _to = f.position;
      _fromB = _toB = f.bearing ?? 0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedDriverMarkerLayer old) {
    super.didUpdateWidget(old);
    final f = widget.fix;
    if (f == null) return;
    final target = f.position;
    if (_to == null) {
      _from = _to = target;
      _fromB = _toB = f.bearing ?? 0;
      return;
    }
    if (_to!.latitude == target.latitude && _to!.longitude == target.longitude) {
      if (f.bearing != null && f.bearing != _toB) _retarget(target, f.bearing!);
      return;
    }
    _retarget(target, f.bearing ?? _currentBearing());
  }

  void _retarget(LatLng target, double bearing) {
    final here = _currentPoint();
    // قفزة كبيرة (مثلاً أول تحديث بعد انقطاع): من غير أنيميشن عشان ما يطيرش
    // الماركر فوق الخريطة.
    if (distanceMeters(here, target) > 2000) {
      _from = _to = target;
      _fromB = _toB = bearing;
      _c.value = 1;
      return;
    }
    _from = here;
    _fromB = _currentBearing();
    _to = target;
    _toB = bearing;
    _c.forward(from: 0);
  }

  double get _t => Curves.easeInOut.transform(_c.value);

  LatLng _currentPoint() {
    final a = _from!;
    final b = _to!;
    if (!_c.isAnimating && _c.value >= 1) return b;
    final t = _t;
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _currentBearing() {
    if (!_c.isAnimating && _c.value >= 1) return _toB;
    // أقصر دوران بين زاويتين (359° → 1° = +2°).
    return lerpBearing(_fromB, _toB, _t);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fix == null || _to == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return MarkerLayer(
          rotate: false,
          markers: [
            Marker(
              point: _currentPoint(),
              width: 52,
              height: 52,
              child: DriverMarkerIcon(
                bearingDegrees: _currentBearing(),
                dimmed: widget.dimmed,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// أيقونة السائق: سيارة داخل دائرة بيضا + مؤشر اتجاه (سهم صغير) بيدور حول
/// الدائرة حسب الاتجاه. السيارة نفسها ثابتة عشان ما تتقلبش.
class DriverMarkerIcon extends StatelessWidget {
  const DriverMarkerIcon({
    super.key,
    required this.bearingDegrees,
    this.dimmed = false,
  });
  final double bearingDegrees;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? C.slate500 : C.emerald600;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withAlpha(46),
              shape: BoxShape.circle,
            ),
          ),
          // مؤشر الاتجاه: بيدور حول مركز الماركر.
          Transform.rotate(
            angle: bearingDegrees * math.pi / 180,
            child: Align(
              alignment: Alignment.topCenter,
              child: Icon(Icons.arrow_drop_up_rounded, size: 28, color: color),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: C.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.directions_car_filled_rounded, size: 19, color: color),
          ),
        ],
      ),
    );
  }
}
