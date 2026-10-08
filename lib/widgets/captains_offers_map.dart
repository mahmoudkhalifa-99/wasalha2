import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:latlong2/latlong.dart' as ll;

import '../core/map/geo_utils.dart' as geo;
import '../features/tracking/models/tracking_models.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'leaflet_map.dart';

bool _realPlace(OrderPlace p) => p.lat != 0 || p.lng != 0;

/// نقطة الاستلام الفعلية (لو الطلب ليه نقطة استلام حقيقية: مشوار أو مطعم من
/// القائمة). الصيدلية والطلب اليدوي بيبقى فيهم إحداثيات تقريبية فمش بنعتمد عليها.
ll.LatLng? orderPickupPoint(Order o) {
  final real = (o.category == OrderCategory.taxi || o.restaurantId != null) &&
      _realPlace(o.pickup);
  return real ? ll.LatLng(o.pickup.lat, o.pickup.lng) : null;
}

ll.LatLng? orderDropoffPoint(Order o) =>
    _realPlace(o.dropoff) ? ll.LatLng(o.dropoff.lat, o.dropoff.lng) : null;

/// النقطة اللي بنقيس منها "الأقرب": مكان الاستلام لو حقيقي (الكابتن بيروحله
/// الأول)، وإلا مكان العميل.
ll.LatLng? offersReferencePoint(Order o) =>
    orderPickupPoint(o) ?? orderDropoffPoint(o);

/// المسافة بالمتر (خط مستقيم تقريبي) بين [ref] وموقع الكابتن، أو null.
double? captainDistanceMeters(ll.LatLng? ref, GeoFix? fix) {
  if (ref == null || fix == null) return null;
  return geo.distanceMeters(ref, fix.position);
}

/// أقرب كابتن (driverId) من بين العروض اللي ليها موقع معروف.
String? nearestOfferDriverId(
    ll.LatLng? ref, Iterable<Offer> offers, Map<String, GeoFix> locs) {
  if (ref == null) return null;
  String? best;
  double? bestD;
  for (final o in offers) {
    final d = captainDistanceMeters(ref, locs[o.driverId]);
    if (d == null) continue;
    if (bestD == null || d < bestD) {
      bestD = d;
      best = o.driverId;
    }
  }
  return best;
}

String _vehicleEmoji(VehicleType v) {
  switch (v) {
    case VehicleType.toktok:
      return '🛺';
    case VehicleType.car:
      return '🚗';
    default:
      return '🛵';
  }
}

Marker _captainMarker(Offer offer, ll.LatLng point, {required bool nearest}) {
  final first = offer.driverName.trim().split(RegExp(r'\s+')).first;
  final color = nearest ? C.emerald600 : C.slate800;
  return Marker(
    point: point,
    width: 120,
    height: 84,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: Text(
            '${first.isEmpty ? "كابتن" : first} • ${offer.price.toInt()} ج',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.s(9, T.w900, C.white),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: C.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Text(_vehicleEmoji(offer.vehicleType),
              style: const TextStyle(fontSize: 17, height: 1)),
        ),
        // مساحة تحت بنفس ارتفاع اللافتة عشان الأيقونة تبقى في نص الماركر بالظبط
        const SizedBox(height: 22),
      ],
    ),
  );
}

/// خريطة بتوضح أماكن الكباتن اللي قدّموا عروض + مكان الاستلام/العميل، عشان
/// العميل يختار أقرب كابتن. المواقع جاية من CaptainLocations (تحديث لحظي).
class CaptainsOffersMap extends StatefulWidget {
  const CaptainsOffersMap({
    super.key,
    required this.order,
    required this.offers,
    required this.locations,
    this.height = 260,
  });

  final Order order;
  final List<Offer> offers;
  final Map<String, GeoFix> locations;
  final double height;

  @override
  State<CaptainsOffersMap> createState() => _CaptainsOffersMapState();
}

class _CaptainsOffersMapState extends State<CaptainsOffersMap> {
  // نقاط ضبط الكاميرا بتتجمّد وبتتغيّر بس لما مجموعة الكباتن (اللي لهم موقع)
  // تتغير — مش مع كل تحديث GPS — عشان العميل يقدر يحرّك الخريطة بحرية.
  List<ll.LatLng> _fitPts = const [];
  String _fitSig = '';

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final locs = widget.locations;
    final ref = offersReferencePoint(order);
    final pickup = orderPickupPoint(order);
    final drop = orderDropoffPoint(order);
    final nearestId = nearestOfferDriverId(ref, widget.offers, locs);

    final withLoc =
        widget.offers.where((o) => locs[o.driverId] != null).toList();
    final missing = widget.offers.length - withLoc.length;

    final markers = <Marker>[
      if (pickup != null) pickupPointMarker(pickup),
      if (drop != null) customerHomeMarker(drop),
      for (final o in withLoc)
        _captainMarker(o, locs[o.driverId]!.position,
            nearest: o.driverId == nearestId),
    ];

    final pts = <ll.LatLng>[
      if (pickup != null) pickup,
      if (drop != null) drop,
      for (final o in withLoc) locs[o.driverId]!.position,
    ];
    final sig = '${pickup?.latitude},${pickup?.longitude}|'
        '${drop?.latitude},${drop?.longitude}|'
        '${withLoc.map((o) => o.driverId).join(',')}';
    if (sig != _fitSig) {
      _fitSig = sig;
      _fitPts = pts;
    }

    final center =
        pts.isNotEmpty ? pts.first : const ll.LatLng(30.556, 31.008);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('أماكن الكباتن حاليًا',
            textAlign: TextAlign.right, style: T.s(13, T.w900, C.slate900)),
        const SizedBox(height: 4),
        Text(
            ref == null
                ? 'اختر الكابتن اللي مناسبك'
                : 'الكابتن الأقرب ليك متعلّم بالأخضر',
            textAlign: TextAlign.right,
            style: T.s(10, T.w700, C.slate400)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              border: Border.all(color: C.emerald50, width: 2),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                WasalhaMap(
                  center: center,
                  zoom: 14,
                  markers: markers,
                  fitPoints: _fitPts.length >= 2 ? _fitPts : null,
                  showControls: true,
                ),
                if (withLoc.isEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: C.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('بنجيب مواقع الكباتن…',
                          textAlign: TextAlign.center,
                          style: T.s(11, T.w800, C.slate600)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (missing > 0 && withLoc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
              missing == 1
                  ? 'موقع كابتن واحد غير متاح حاليًا'
                  : 'مواقع $missing كباتن غير متاحة حاليًا',
              textAlign: TextAlign.right,
              style: T.s(10, T.w700, C.slate400)),
        ],
      ],
    );
  }
}
