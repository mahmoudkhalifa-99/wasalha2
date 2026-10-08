import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/models/models.dart';
import 'package:wasalha/models/review.dart';

Review _r(String driver, int rating, {String comment = '', String name = ''}) =>
    Review.fromMap({
      'orderId': 'o_${driver}_$rating$comment',
      'customerId': 'c',
      'customerName': 'عميل',
      'driverId': driver,
      'driverName': name.isEmpty ? 'كابتن $driver' : name,
      'rating': rating,
      'comment': comment,
      'createdAt': 1000,
    }, 'id_${driver}_$rating$comment');

Order _order(Map<String, dynamic> extra) => Order.fromMap({
      'id': 'o1',
      'customerId': 'c',
      'category': 'TAXI',
      'status': 'DELIVERED',
      'driverId': 'd1',
      ...extra,
    });

void main() {
  group('Review.fromMap', () {
    test('بيقرأ الحقول ويقصّ التعليق', () {
      final r = Review.fromMap({
        'orderId': 'o9',
        'driverId': 'd',
        'rating': 4,
        'comment': '  ممتاز  ',
        'createdAt': 5,
      }, 'o9');
      expect(r.rating, 4);
      expect(r.comment, 'ممتاز');
      expect(r.orderId, 'o9');
      expect(r.createdAt, 5);
    });

    test('التقييم بيتحصر بين 1 و 5', () {
      expect(Review.fromMap({'rating': 9}, 'a').rating, 5);
      expect(Review.fromMap({'rating': 0}, 'a').rating, 1);
      expect(Review.fromMap({}, 'a').rating, 1);
    });
  });

  group('driverReviewStats', () {
    test('المتوسط والعدد والتعليقات، والأقل تقييمًا أولًا', () {
      final stats = driverReviewStats([
        _r('a', 5),
        _r('a', 4, comment: 'حلو'),
        _r('b', 2),
        _r('b', 1, comment: 'سيئ'),
        _r('b', 3),
      ]);
      expect(stats.map((s) => s.driverId), ['b', 'a']);
      expect(stats[0].average, closeTo(2.0, 1e-9));
      expect(stats[0].count, 3);
      expect(stats[0].withComments, 1);
      expect(stats[1].average, closeTo(4.5, 1e-9));
    });

    test('بيتجاهل التقييمات من غير كابتن', () {
      expect(driverReviewStats([Review.fromMap({'rating': 3}, 'x')]), isEmpty);
    });

    test('قائمة فاضية', () => expect(driverReviewStats(const []), isEmpty));
  });

  group('needsReview', () {
    test('استلام متأكد ومفيش تقييم = مطلوب', () {
      expect(needsReview(_order({'customerReceived': true})), isTrue);
    });
    test('من غير تأكيد استلام = لأ', () {
      expect(needsReview(_order({})), isFalse);
    });
    test('اتقيّم أو اتخطى = لأ', () {
      expect(needsReview(_order({'customerReceived': true, 'rating': 5})), isFalse);
      expect(
          needsReview(_order({'customerReceived': true, 'ratingSkipped': true})),
          isFalse);
    });
    test('من غير كابتن = لأ', () {
      expect(
          needsReview(_order({'customerReceived': true, 'driverId': null})),
          isFalse);
    });
  });
}
