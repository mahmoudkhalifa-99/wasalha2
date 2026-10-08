import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/services/geocoding_service.dart';

const _p1 = LatLng(30.5560, 31.0080);
const _p2 = LatLng(30.5600, 31.0120);

const _okBody = '''
{"display_name":"شارع النصر, الحي الأول, شبين الكوم, المنوفية, مصر",
 "address":{"road":"شارع النصر","suburb":"الحي الأول","city":"شبين الكوم","country":"مصر"}}''';

NominatimGeocodingService _svc(
  http.Client client, {
  Duration minInterval = Duration.zero,
  Duration timeout = const Duration(seconds: 2),
  String baseUrl = 'https://geo.test',
  Duration blockedCooldown = const Duration(seconds: 60),
}) =>
    NominatimGeocodingService(
      client: client,
      baseUrl: baseUrl,
      minInterval: minInterval,
      timeout: timeout,
      blockedCooldown: blockedCooldown,
    );

http.Response _json(String body, [int code = 200]) =>
    http.Response.bytes(utf8.encode(body), code,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('reverseGeocode', () {
    test('بيرجّع عنوان قصير (شارع، حي، مدينة) ويبعت User-Agent ولغة عربي', () async {
      late http.Request req;
      final s = _svc(MockClient((r) async {
        req = r;
        return _json(_okBody);
      }));
      expect(await s.reverseGeocode(_p1), 'شارع النصر، الحي الأول، شبين الكوم');
      expect(req.url.path, '/reverse');
      expect(req.url.queryParameters['lat'], '30.556000');
      expect(req.url.queryParameters['lon'], '31.008000');
      expect(req.url.queryParameters['accept-language'], 'ar');
      expect(req.headers['User-Agent'], contains('Wasalha'));
    });

    test('الكاش: نفس الموقع مرتين = طلب واحد', () async {
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        return _json(_okBody);
      }));
      await s.reverseGeocode(_p1);
      await s.reverseGeocode(_p1);
      expect(calls, 1);
    });

    test('طلبين متزامنين لنفس الموقع = طلب شبكة واحد', () async {
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _json(_okBody);
      }));
      final r = await Future.wait([s.reverseGeocode(_p1), s.reverseGeocode(_p1)]);
      expect(calls, 1);
      expect(r[0], r[1]);
    });

    test('حد الطلبات: الفاصل بين بدايات طلبين مختلفين ≥ minInterval', () async {
      final starts = <DateTime>[];
      final s = _svc(
        MockClient((_) async {
          starts.add(DateTime.now());
          return _json(_okBody);
        }),
        minInterval: const Duration(milliseconds: 120),
      );
      await Future.wait([s.reverseGeocode(_p1), s.reverseGeocode(_p2)]);
      expect(starts.length, 2);
      // هامش صغير لدقة الـ Timer.
      expect(starts[1].difference(starts[0]).inMilliseconds, greaterThanOrEqualTo(100));
    });

    test('فشل الشبكة / 500 / JSON تالف / error في الرد = null (من غير استثناء)', () async {
      expect(
        await _svc(MockClient((_) async => throw http.ClientException('down')))
            .reverseGeocode(_p1),
        isNull,
      );
      expect(await _svc(MockClient((_) async => _json('x', 500))).reverseGeocode(_p1),
          isNull);
      expect(await _svc(MockClient((_) async => _json('{not json'))).reverseGeocode(_p1),
          isNull);
      expect(
        await _svc(MockClient((_) async => _json('{"error":"Unable to geocode"}')))
            .reverseGeocode(_p1),
        isNull,
      );
    });

    test('Timeout = null', () async {
      final never = Completer<http.Response>();
      final s = _svc(MockClient((_) => never.future),
          timeout: const Duration(milliseconds: 40));
      expect(await s.reverseGeocode(_p1), isNull);
    });

    test('الفشل مبيتخزّنش في الكاش: المحاولة التالية بتعيد الطلب', () async {
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        return calls == 1 ? _json('x', 500) : _json(_okBody);
      }));
      expect(await s.reverseGeocode(_p1), isNull);
      expect(await s.reverseGeocode(_p1), isNotNull);
      expect(calls, 2);
    });

    test('429: بيوقف الإرسال فترة الـ cooldown (مفيش ضرب على السيرفر)', () async {
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        return _json('slow down', 429);
      }));
      expect(await s.reverseGeocode(_p1), isNull);
      expect(await s.reverseGeocode(_p2), isNull);
      expect(await s.reverseGeocode(_p1), isNull);
      expect(calls, 1);
    });

    test('GEOCODER_URL: بيحافظ على المسار وعلى باراميترات الـ key', () async {
      late Uri url;
      final s = _svc(
        MockClient((r) async {
          url = r.url;
          return _json(_okBody);
        }),
        baseUrl: 'https://maps.example.com/geo/?key=SECRET',
      );
      await s.reverseGeocode(_p1);
      expect(url.host, 'maps.example.com');
      expect(url.path, '/geo/reverse');
      expect(url.queryParameters['key'], 'SECRET');
      expect(url.queryParameters['format'], 'jsonv2');
    });
  });

  group('formatAddress', () {
    test('بيتجاهل الأجزاء الناقصة والمكررة', () {
      expect(
        NominatimGeocodingService.formatAddress({
          'address': {'road': 'شارع أ', 'city': 'شارع أ'},
        }),
        'شارع أ',
      );
    });

    test('من غير address: أول 3 أجزاء من display_name', () {
      expect(
        NominatimGeocodingService.formatAddress({'display_name': 'أ, ب, ج, د, هـ'}),
        'أ، ب، ج',
      );
    });

    test('مفيش بيانات = null', () {
      expect(NominatimGeocodingService.formatAddress({}), isNull);
    });
  });

  group('search', () {
    test('بيحلل النتائج ويتجاهل العناصر التالفة', () async {
      final s = _svc(MockClient((_) async => _json(jsonEncode([
            {'display_name': 'مكان 1', 'lat': '30.5', 'lon': '31.0'},
            {'display_name': 'ناقص'},
            {'display_name': 'مكان 2', 'lat': '30.6', 'lon': '31.1'},
          ]))));
      final r = await s.search('مكان');
      expect(r.map((e) => e.name), ['مكان 1', 'مكان 2']);
      expect(r.first.latLng, const LatLng(30.5, 31.0));
    });

    test('نص قصير جدًا: مفيش طلب شبكة', () async {
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        return _json('[]');
      }));
      expect(await s.search(' a '), isEmpty);
      expect(calls, 0);
    });

    test('فشل = قائمة فاضية، والنتيجة المكررة من الكاش', () async {
      expect(
        await _svc(MockClient((_) async => throw http.ClientException('x')))
            .search('مدينة'),
        isEmpty,
      );
      var calls = 0;
      final s = _svc(MockClient((_) async {
        calls++;
        return _json('[{"display_name":"م","lat":"1","lon":"2"}]');
      }));
      await s.search('مدينة');
      await s.search('مدينة');
      expect(calls, 1);
    });
  });
}
