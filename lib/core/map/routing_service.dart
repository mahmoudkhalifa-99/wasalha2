import 'package:latlong2/latlong.dart';

/// نتيجة حساب الطريق.
class RouteResult {
  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    DateTime? computedAt,
  }) : computedAt = computedAt ?? DateTime.now();

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final DateTime computedAt;
}

enum RoutingFailure { network, timeout, rateLimited, noRoute, server }

class RoutingException implements Exception {
  const RoutingException(this.kind, [this.message = '']);
  final RoutingFailure kind;
  final String message;

  /// هل السبب غالبًا انقطاع/ضعف إنترنت؟
  bool get isConnectivity =>
      kind == RoutingFailure.network || kind == RoutingFailure.timeout;

  @override
  String toString() => 'RoutingException($kind${message.isEmpty ? '' : ': $message'})';
}

/// واجهة مجرّدة لمزوّد الطرق. التطبيق يعتمد عليها فقط، فيمكن استبدال
/// OSRM بـ GraphHopper أو Mapbox أو Google بدون تعديل باقي الكود.
abstract class RoutingService {
  /// يرمي [RoutingException] عند الفشل.
  Future<RouteResult> getRoute({
    required LatLng start,
    required LatLng destination,
  });
}
