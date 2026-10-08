// نسخة Dart من utils.ts
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// سيرفرات OSRM (من غير مفتاح). بنسأل الاتنين مع بعض وناخد أول رد سليم،
/// لأن السيرفر العام الواحد بطيء/بيرفض أحيانًا فكان الخط بيرجع مستقيم.
const List<String> _osrmBases = [
  'https://router.project-osrm.org/route/v1/driving',
  'https://routing.openstreetmap.de/routed-car/route/v1/driving',
];

/// معلومات إضافية عن آخر محاولة جلب مسار (بدون ما نغيّر شكل الرد).
class RouteFetchInfo {
  /// true لو أي سيرفر رجّع 429 (ضغط زائد) في المحاولة دي.
  bool rateLimited = false;
}

/// تباعد تصاعدي لإعادة محاولة جلب المسار بعد الفشل: 10 ث ← 20 ← 40 ← 80 ← 160 (حد أقصى).
/// 429 بيزوّد مرحلة. أول نجاح بيصفّر العدّاد.
class RouteBackoff {
  RouteBackoff({
    this.base = const Duration(seconds: 10),
    this.maxExponent = 4,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration base;
  final int maxExponent;
  final DateTime Function() _clock;

  int _failures = 0;
  DateTime? _retryAt;

  int get failures => _failures;

  /// لسه جوه فترة الانتظار بعد فشل؟
  bool get blocked {
    final at = _retryAt;
    return at != null && _clock().isBefore(at);
  }

  /// الوقت المتبقي لحد المحاولة الجاية (صفر لو مفيش انتظار).
  Duration get remaining {
    final at = _retryAt;
    if (at == null) return Duration.zero;
    final d = at.difference(_clock());
    return d.isNegative ? Duration.zero : d;
  }

  /// يسجّل فشل ويرجّع مدة الانتظار قبل المحاولة الجاية.
  Duration fail({bool rateLimited = false}) {
    _failures++;
    final e = _failures + (rateLimited ? 1 : 0) - 1;
    final exp = e < 0 ? 0 : (e > maxExponent ? maxExponent : e);
    final wait = base * (1 << exp);
    _retryAt = _clock().add(wait);
    return wait;
  }

  void succeed() {
    _failures = 0;
    _retryAt = null;
  }

  /// تصفير كامل (مثلاً لما الوجهة تتغير).
  void reset() => succeed();
}

Future<List<List<double>>?> _osrmGeometry(
    String base, double lat1, double lon1, double lat2, double lon2,
    RouteFetchInfo? info) async {
  try {
    final url = Uri.parse(
        '$base/$lon1,$lat1;$lon2,$lat2?overview=full&geometries=geojson');
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) info?.rateLimited = true;
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is Map &&
        data['code'] == 'Ok' &&
        (data['routes'] as List).isNotEmpty &&
        data['routes'][0]['geometry']?['coordinates'] != null) {
      final coords = data['routes'][0]['geometry']['coordinates'] as List;
      final pts = coords
          .map<List<double>>((c) =>
              [(c[1] as num).toDouble(), (c[0] as num).toDouble()])
          .toList();
      return pts.length >= 2 ? pts : null;
    }
  } catch (_) {}
  return null;
}

/// مسار السير على الطرق. لو كل السيرفرات فشلت بيرجع خط مستقيم من نقطتين
/// (استخدم [isStraightFallback] عشان متستبدلش مسار حقيقي قديم بيه).
Future<List<List<double>>> getRouteGeometry(
    double lat1, double lon1, double lat2, double lon2,
    {RouteFetchInfo? info}) async {
  if (lat1 == 0 || lon1 == 0 || lat2 == 0 || lon2 == 0) return [];
  final completer = Completer<List<List<double>>?>();
  var pending = _osrmBases.length;
  for (final b in _osrmBases) {
    _osrmGeometry(b, lat1, lon1, lat2, lon2, info).then((r) {
      if (completer.isCompleted) return;
      if (r != null) {
        completer.complete(r);
      } else if (--pending == 0) {
        completer.complete(null);
      }
    });
  }
  final res = await completer.future;
  if (res != null) return res;
  return [
    [lat1, lon1],
    [lat2, lon2]
  ];
}

/// المسار اللي رجع هو الخط المستقيم الاحتياطي (مش طريق حقيقي).
bool isStraightFallback(List<List<double>> g) => g.length <= 2;

class RoadDistance {
  final double distance; // كم
  final int duration; // دقيقة
  const RoadDistance(this.distance, this.duration);
}

// كاش بسيط للمسافات (نفس الزوج تاني = فوري بدل انتظار OSRM العام لحد 2.5 ث).
// بيتخزّن بس الرد الحقيقي من OSRM، مش التقدير الاحتياطي.
final Map<String, RoadDistance> _roadDistCache = {};

/// حساب المسافة الفعلية والزمن التقديري للطرق
Future<RoadDistance> getRoadDistance(
    double lat1, double lon1, double lat2, double lon2) async {
  if (lat1 == 0 || lon1 == 0 || lat2 == 0 || lon2 == 0) {
    return const RoadDistance(0, 0);
  }
  final key = '${lat1.toStringAsFixed(4)},${lon1.toStringAsFixed(4)}|'
      '${lat2.toStringAsFixed(4)},${lon2.toStringAsFixed(4)}';
  final cached = _roadDistCache[key];
  if (cached != null) return cached;
  try {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$lon1,$lat1;$lon2,$lat2?overview=false');
    final response =
        await http.get(url).timeout(const Duration(milliseconds: 2500));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
        final r = data['routes'][0];
        final res = RoadDistance(
          double.parse(((r['distance'] as num) / 1000).toStringAsFixed(1)),
          ((r['duration'] as num) / 60).ceil(),
        );
        if (_roadDistCache.length > 200) _roadDistCache.clear();
        return _roadDistCache[key] = res;
      }
    }
  } catch (_) {
    // Fallback quietly to calculated straight distance
  }
  final straight = calculateDistance(lat1, lon1, lat2, lon2);
  return RoadDistance(
    double.parse((straight * 1.3).toStringAsFixed(1)),
    (straight * 3).ceil(),
  );
}

double calculateDistance(
    double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLon = (lon2 - lon1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * (math.pi / 180)) *
          math.cos(lat2 * (math.pi / 180)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return double.parse((r * c).toStringAsFixed(1));
}

/// ضغط الصور لتقليل استهلاك الذاكرة وحجم المستندات في Firestore
/// (نفس المنطق: أقصى أبعاد 800x800، JPEG بجودة 60%).
Future<String> compressImage(String base64Str,
    {int maxWidth = 800, int maxHeight = 800}) async {
  if (base64Str.isEmpty || !base64Str.startsWith('data:image')) {
    return base64Str;
  }
  try {
    final comma = base64Str.indexOf(',');
    final Uint8List bytes = base64Decode(base64Str.substring(comma + 1));
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Str;

    var width = decoded.width.toDouble();
    var height = decoded.height.toDouble();
    if (width > height) {
      if (width > maxWidth) {
        height *= maxWidth / width;
        width = maxWidth.toDouble();
      }
    } else {
      if (height > maxHeight) {
        width *= maxHeight / height;
        height = maxHeight.toDouble();
      }
    }
    final resized = img.copyResize(decoded,
        width: width.round(), height: height.round());
    final jpg = img.encodeJpg(resized, quality: 60);
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return base64Str;
  }
}
