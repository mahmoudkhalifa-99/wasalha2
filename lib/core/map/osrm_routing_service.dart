import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'routing_service.dart';

/// تنفيذ [RoutingService] عبر OSRM (مجاني، بدون API key).
/// السيرفر العام project-osrm.org مخصص للاستخدام الخفيف؛ للإنتاج الكثيف
/// الأفضل تستضيف سيرفر OSRM خاص وتمرر عنوانه في [baseUrl].
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({
    http.Client? client,
    this.baseUrl = 'https://router.project-osrm.org',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  @override
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    http.Response res;
    try {
      res = await _client
          .get(uri, headers: const {
            'Accept': 'application/json',
            // سياسة سيرفر OSRM العام: User-Agent واضح يعرّف التطبيق.
            'User-Agent': 'Wasalha/1.0 (com.wasalah.app)',
          })
          .timeout(timeout);
    } on TimeoutException {
      throw const RoutingException(RoutingFailure.timeout);
    } on SocketException catch (e) {
      throw RoutingException(RoutingFailure.network, e.message);
    } on http.ClientException catch (e) {
      throw RoutingException(RoutingFailure.network, e.message);
    } catch (e) {
      throw RoutingException(RoutingFailure.network, e.toString());
    }

    if (res.statusCode == 429) {
      throw const RoutingException(RoutingFailure.rateLimited);
    }
    if (res.statusCode != 200) {
      throw RoutingException(RoutingFailure.server, 'HTTP ${res.statusCode}');
    }

    try {
      final data = jsonDecode(res.body);
      if (data is! Map || data['code'] != 'Ok') {
        throw const RoutingException(RoutingFailure.noRoute);
      }
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        throw const RoutingException(RoutingFailure.noRoute);
      }
      final r = routes.first as Map;
      final coords = (r['geometry'] as Map)['coordinates'] as List;
      final points = <LatLng>[
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (points.length < 2) {
        throw const RoutingException(RoutingFailure.noRoute);
      }
      return RouteResult(
        points: points,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
      );
    } on RoutingException {
      rethrow;
    } catch (e) {
      throw RoutingException(RoutingFailure.server, 'bad response: $e');
    }
  }
}
