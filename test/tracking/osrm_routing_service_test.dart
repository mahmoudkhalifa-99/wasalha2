import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/core/map/osrm_routing_service.dart';
import 'package:wasalha/core/map/routing_service.dart';

const _start = LatLng(30.55, 31.0);
const _dest = LatLng(30.56, 31.01);

const _okBody = '''
{"code":"Ok","routes":[{"distance":1234.5,"duration":321.0,
 "geometry":{"type":"LineString","coordinates":[[31.0,30.55],[31.005,30.555],[31.01,30.56]]}}]}
''';

Future<RoutingException> _expectFailure(OsrmRoutingService s) async {
  try {
    await s.getRoute(start: _start, destination: _dest);
  } on RoutingException catch (e) {
    return e;
  }
  fail('expected RoutingException');
}

void main() {
  test('بيحلل الرد الناجح (lon,lat → LatLng) والمسافة والزمن', () async {
    late Uri requested;
    final s = OsrmRoutingService(
      client: MockClient((req) async {
        requested = req.url;
        return http.Response(_okBody, 200);
      }),
    );
    final r = await s.getRoute(start: _start, destination: _dest);
    expect(r.distanceMeters, 1234.5);
    expect(r.durationSeconds, 321.0);
    expect(r.points.length, 3);
    expect(r.points.first.latitude, 30.55);
    expect(r.points.first.longitude, 31.0);
    expect(requested.path, contains('31.0,30.55;31.01,30.56'));
  });

  test('HTTP 429 = rateLimited', () async {
    final s = OsrmRoutingService(
        client: MockClient((_) async => http.Response('', 429)));
    expect((await _expectFailure(s)).kind, RoutingFailure.rateLimited);
  });

  test('HTTP 500 = server', () async {
    final s = OsrmRoutingService(
        client: MockClient((_) async => http.Response('', 500)));
    expect((await _expectFailure(s)).kind, RoutingFailure.server);
  });

  test('code != Ok أو routes فاضية = noRoute', () async {
    final s = OsrmRoutingService(
        client: MockClient(
            (_) async => http.Response('{"code":"NoRoute","routes":[]}', 200)));
    expect((await _expectFailure(s)).kind, RoutingFailure.noRoute);
  });

  test('JSON تالف = server (من غير crash)', () async {
    final s = OsrmRoutingService(
        client: MockClient((_) async => http.Response('not json', 200)));
    expect((await _expectFailure(s)).kind, RoutingFailure.server);
  });

  test('انقطاع النت (SocketException) = network ويُعتبر connectivity', () async {
    final s = OsrmRoutingService(
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    final e = await _expectFailure(s);
    expect(e.kind, RoutingFailure.network);
    expect(e.isConnectivity, isTrue);
  });

  test('انتهاء المهلة = timeout', () async {
    final s = OsrmRoutingService(
      timeout: const Duration(milliseconds: 20),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(_okBody, 200);
      }),
    );
    final e = await _expectFailure(s);
    expect(e.kind, RoutingFailure.timeout);
    expect(e.isConnectivity, isTrue);
  });

  test('بيبعت User-Agent يعرّف التطبيق (شرط سيرفر OSRM العام)', () async {
    late Map<String, String> headers;
    final s = OsrmRoutingService(
      client: MockClient((req) async {
        headers = req.headers;
        return http.Response(_okBody, 200);
      }),
    );
    await s.getRoute(start: _start, destination: _dest);
    expect(headers['User-Agent'], contains('Wasalha'));
  });

  test('geometry ناقصة = server (من غير crash)', () async {
    final s = OsrmRoutingService(
        client: MockClient((_) async => http.Response(
            '{"code":"Ok","routes":[{"distance":1,"duration":1,"geometry":{}}]}',
            200)));
    expect((await _expectFailure(s)).kind, RoutingFailure.server);
  });

  test('مسار بنقطة واحدة فقط = noRoute', () async {
    final s = OsrmRoutingService(
        client: MockClient((_) async => http.Response(
            '{"code":"Ok","routes":[{"distance":1,"duration":1,'
            '"geometry":{"coordinates":[[31.0,30.55]]}}]}',
            200)));
    expect((await _expectFailure(s)).kind, RoutingFailure.noRoute);
  });
}
