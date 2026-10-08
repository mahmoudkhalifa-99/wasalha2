import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/map/map_config.dart';

/// نتيجة بحث عن موقع (للاستخدام المستقبلي — مفيش Search UI حاليًا).
class LocationSearchResult {
  const LocationSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Abstraction مستقلة عن أي مزوّد. الـ Widgets والـ Controllers بتعتمد عليها بس.
/// تفاصيل المكان الفعلي من الـ Reverse Geocoding (بدون أي ربط بقوائم التطبيق).
class PlaceDetails {
  const PlaceDetails({this.locality, this.area, this.road, this.full});

  /// اسم القرية/الحي/المدينة (مثال: طملاي).
  final String? locality;

  /// المركز/المنطقة الأكبر (مثال: مركز منوف).
  final String? area;
  final String? road;

  /// عنوان مختصر جاهز للعرض.
  final String? full;
}

abstract class GeocodingService {
  /// عنوان مفهوم للنقطة، أو null لو مش متاح/فشل (الفشل مبيرميش استثناء).
  Future<String?> reverseGeocode(LatLng location);

  /// بحث نصي. بيرجّع قائمة فاضية لو مفيش نتائج أو حصل فشل.
  Future<List<LocationSearchResult>> search(String query);
}

/// تنفيذ Nominatim-compatible. **للتجربة فقط**: سيرفر OSM العام ليه سياسة
/// استخدام صارمة (طلب في الثانية كحد أقصى، User-Agent واضح، تخزين مؤقت، ومش
/// للتطبيقات كثيفة الاستخدام). للإنتاج غيّر `GEOCODER_URL` لمزوّد مرخّص أو
/// سيرفر خاص بيك — من غير أي تعديل في الكود.
class NominatimGeocodingService implements GeocodingService {
  NominatimGeocodingService({
    http.Client? client,
    String? baseUrl,
    this.language = 'ar',
    this.timeout = const Duration(seconds: 6),
    this.minInterval = const Duration(seconds: 1),
    this.blockedCooldown = const Duration(seconds: 60),
    this.cacheSize = 64,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl = baseUrl ?? MapConfig.geocoderUrl,
        _clock = clock ?? DateTime.now;

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final String language;
  final Duration timeout;

  /// أقل فاصل بين بداية أي طلبين (سياسة Nominatim: ≤ 1 طلب/ثانية).
  final Duration minInterval;

  /// بعد 429/403 بنوقف الإرسال المدة دي عشان ما نتحظرش.
  final Duration blockedCooldown;
  final int cacheSize;
  final DateTime Function() _clock;

  // LRU بسيط (LinkedHashMap بيحافظ على ترتيب الإدخال).
  final LinkedHashMap<String, String> _reverseCache = LinkedHashMap();
  final LinkedHashMap<String, List<LocationSearchResult>> _searchCache =
      LinkedHashMap();
  final Map<String, Future<String?>> _inflightReverse = {};
  final LinkedHashMap<String, PlaceDetails> _detailsCache = LinkedHashMap();

  Future<void> _tail = Future<void>.value();
  DateTime? _lastStart;
  DateTime? _blockedUntil;

  bool get _isBlocked {
    final b = _blockedUntil;
    return b != null && _clock().isBefore(b);
  }

  /// نقفل الـ client لو إحنا اللي عملناه.
  void close() {
    if (_ownsClient) _client.close();
  }

  // ---------------- reverse ----------------
  @override
  Future<String?> reverseGeocode(LatLng location) {
    final key = _key(location);
    final cached = _reverseCache.remove(key);
    if (cached != null) {
      _reverseCache[key] = cached; // يبقى الأحدث استخدامًا
      return Future<String?>.value(cached);
    }
    if (_isBlocked) return Future<String?>.value(null);
    final running = _inflightReverse[key];
    if (running != null) return running;

    final f = _reverse(location, key).whenComplete(() {
      _inflightReverse.remove(key);
    });
    _inflightReverse[key] = f;
    return f;
  }

  Future<String?> _reverse(LatLng p, String key) async {
    try {
      final uri = _uri('reverse', {
        'format': 'jsonv2',
        'lat': p.latitude.toStringAsFixed(6),
        'lon': p.longitude.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': language,
      });
      final body = await _enqueue(() => _get(uri));
      if (body == null) return null;
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['error'] != null) return null;
      final text = formatAddress(json);
      _put(_detailsCache, key, parseDetails(json, text));
      if (text != null) _put(_reverseCache, key, text);
      return text;
    } catch (e) {
      debugPrint('reverseGeocode failed: $e');
      return null;
    }
  }

  /// اسم المكان الفعلي (قرية/حي + مركز + شارع). بيستخدم نفس الكاش بتاع
  /// [reverseGeocode] فلو النقطة اتطلبت قبل كده مفيش طلب شبكة جديد.
  /// بيرجّع null لو فشل (مبيرميش استثناء).
  Future<PlaceDetails?> reverseDetails(LatLng location) async {
    final key = _key(location);
    var d = _detailsCache[key];
    if (d != null) return d;
    await reverseGeocode(location);
    d = _detailsCache[key];
    return d;
  }

  static PlaceDetails parseDetails(Map<String, dynamic> json, String? full) {
    final a = json['address'];
    String? pick(List<String> keys) {
      if (a is! Map) return null;
      for (final k in keys) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    return PlaceDetails(
      locality: pick(['village', 'hamlet', 'suburb', 'neighbourhood',
        'quarter', 'town', 'city', 'municipality']),
      area: pick(['county', 'state_district', 'city_district', 'city']),
      road: pick(['road', 'pedestrian', 'footway', 'residential', 'path']),
      full: full,
    );
  }

  // ---------------- search ----------------
  @override
  Future<List<LocationSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final key = q.toLowerCase();
    final cached = _searchCache.remove(key);
    if (cached != null) {
      _searchCache[key] = cached;
      return cached;
    }
    if (_isBlocked) return const [];
    try {
      final uri = _uri('search', {
        'q': q,
        'format': 'jsonv2',
        'limit': '5',
        'addressdetails': '0',
        'accept-language': language,
      });
      final body = await _enqueue(() => _get(uri));
      if (body == null) return const [];
      final json = jsonDecode(body);
      if (json is! List) return const [];
      final out = <LocationSearchResult>[];
      for (final item in json) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lon = double.tryParse('${item['lon']}');
        final name = item['display_name'];
        if (lat == null || lon == null || name is! String) continue;
        out.add(LocationSearchResult(name: name, latitude: lat, longitude: lon));
      }
      _put(_searchCache, key, out);
      return out;
    } catch (e) {
      debugPrint('search failed: $e');
      return const [];
    }
  }

  // ---------------- مشترك ----------------
  Uri _uri(String endpoint, Map<String, String> params) {
    final base = Uri.parse(baseUrl);
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$path/$endpoint',
      queryParameters: {...base.queryParameters, ...params},
    );
  }

  /// طلب واحد في كل مرة وبفاصل [minInterval] بين بدايات الطلبات.
  Future<T> _enqueue<T>(Future<T> Function() job) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      final last = _lastStart;
      if (last != null) {
        final wait = minInterval - _clock().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastStart = _clock();
      try {
        completer.complete(await job());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<String?> _get(Uri uri) async {
    final res = await _client.get(uri, headers: {
      'User-Agent': MapConfig.httpUserAgent,
      'Accept': 'application/json',
      'Accept-Language': language,
    }).timeout(timeout);
    if (res.statusCode == 429 || res.statusCode == 403 || res.statusCode == 509) {
      _blockedUntil = _clock().add(blockedCooldown);
      return null;
    }
    if (res.statusCode != 200) return null;
    return utf8.decode(res.bodyBytes);
  }

  /// مفتاح الكاش: 5 خانات عشرية (~1 متر).
  static String _key(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  void _put<V>(LinkedHashMap<String, V> cache, String key, V value) {
    cache.remove(key);
    cache[key] = value;
    while (cache.length > cacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  /// يكوّن عنوان قصير (شارع، حي، مدينة) من رد Nominatim، أو أول 3 أجزاء من
  /// display_name لو التفاصيل مش موجودة.
  static String? formatAddress(Map<String, dynamic> json) {
    final a = json['address'];
    if (a is Map) {
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final parts = <String>[];
      void add(String? v) {
        if (v != null && !parts.contains(v)) parts.add(v);
      }

      add(pick(['road', 'pedestrian', 'footway', 'residential', 'path']));
      add(pick(['neighbourhood', 'suburb', 'quarter', 'city_district', 'village', 'hamlet']));
      add(pick(['city', 'town', 'municipality', 'county', 'state_district']));
      if (parts.isNotEmpty) return parts.take(3).join('، ');
    }
    final dn = json['display_name'];
    if (dn is String && dn.trim().isNotEmpty) {
      final parts = dn.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      return parts.take(3).join('، ');
    }
    return null;
  }
}
