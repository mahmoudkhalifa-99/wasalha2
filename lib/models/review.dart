import 'models.dart' show Order, toMillis;

/// تقييم عميل لكابتن بعد استلام الطلب. المستند: reviews/{orderId} (تقييم واحد لكل طلب).
class Review {
  final String id; // = orderId
  final String orderId;
  final String customerId;
  final String customerName;
  final String driverId;
  final String driverName;
  final int rating; // 1..5
  final String comment;
  final int createdAt;

  const Review({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.driverId,
    required this.driverName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory Review.fromMap(Map<String, dynamic> m, String id) {
    final r = m['rating'];
    final n = r is num ? r.round() : 0;
    return Review(
      id: id,
      orderId: (m['orderId'] as String?) ?? id,
      customerId: (m['customerId'] as String?) ?? '',
      customerName: (m['customerName'] as String?) ?? '',
      driverId: (m['driverId'] as String?) ?? '',
      driverName: (m['driverName'] as String?) ?? '',
      rating: n < 1 ? 1 : (n > 5 ? 5 : n),
      comment: ((m['comment'] as String?) ?? '').trim(),
      createdAt: toMillis(m['createdAt']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'orderId': orderId,
        'customerId': customerId,
        'customerName': customerName,
        'driverId': driverId,
        'driverName': driverName,
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt,
      };
}

/// ملخص تقييمات كابتن واحد.
class DriverReviewStats {
  final String driverId;
  final String driverName;
  final int count;
  final double average;
  final int withComments;

  const DriverReviewStats({
    required this.driverId,
    required this.driverName,
    required this.count,
    required this.average,
    required this.withComments,
  });
}

/// متوسط التقييمات لكل كابتن، الأقل تقييمًا أولًا (عشان الإدارة تشوف المشاكل الأول).
List<DriverReviewStats> driverReviewStats(Iterable<Review> reviews) {
  final sum = <String, int>{};
  final cnt = <String, int>{};
  final withC = <String, int>{};
  final names = <String, String>{};
  for (final r in reviews) {
    if (r.driverId.isEmpty) continue;
    sum[r.driverId] = (sum[r.driverId] ?? 0) + r.rating;
    cnt[r.driverId] = (cnt[r.driverId] ?? 0) + 1;
    if (r.comment.isNotEmpty) withC[r.driverId] = (withC[r.driverId] ?? 0) + 1;
    if (r.driverName.isNotEmpty) names[r.driverId] = r.driverName;
  }
  final out = [
    for (final id in cnt.keys)
      DriverReviewStats(
        driverId: id,
        driverName: names[id] ?? '',
        count: cnt[id]!,
        average: sum[id]! / cnt[id]!,
        withComments: withC[id] ?? 0,
      ),
  ];
  out.sort((a, b) {
    final c = a.average.compareTo(b.average);
    return c != 0 ? c : b.count.compareTo(a.count);
  });
  return out;
}

/// الطلب ده لسه مستني تقييم من العميل: الاستلام متأكد، فيه كابتن، ولا اتقيّم ولا اتخطى.
bool needsReview(Order o) =>
    o.customerReceived &&
    o.rating == null &&
    !o.ratingSkipped &&
    (o.driverId?.isNotEmpty ?? false);
