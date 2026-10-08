// Firestore بيعرّف كلاس اسمه Order (Index) بيتعارض مع Order بتاعنا في models.dart.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/models.dart';
import '../models/review.dart';
import 'firebase_service.dart';

/// أقصى طول للتعليق (لازم يطابق firestore.rules).
const int maxReviewCommentLength = 500;

class ReviewService {
  ReviewService._();

  /// يحفظ التقييم في reviews/{orderId} ويحدّث الطلب (rating/feedback/ratedAt) في
  /// نفس الـ batch، فمفيش حالة نص-محفوظ. بيرمي استثناء لو الطلب مالوش كابتن.
  static Future<void> submit({
    required Order order,
    required String customerName,
    required int rating,
    required String comment,
  }) async {
    final driverId = order.driverId;
    if (driverId == null || driverId.isEmpty) {
      throw StateError('order has no driver');
    }
    final text = comment.trim();
    final clean = text.length > maxReviewCommentLength
        ? text.substring(0, maxReviewCommentLength)
        : text;
    final stars = rating < 1 ? 1 : (rating > 5 ? 5 : rating);
    final now = DateTime.now().millisecondsSinceEpoch;

    final review = Review(
      id: order.id,
      orderId: order.id,
      customerId: order.customerId,
      customerName: customerName,
      driverId: driverId,
      driverName: order.driverName ?? '',
      rating: stars,
      comment: clean,
      createdAt: now,
    );

    final batch = db.batch();
    batch.set(db.collection('reviews').doc(order.id), review.toMap());
    batch.update(db.collection('orders').doc(order.id), {
      'rating': stars,
      'feedback': clean,
      'ratedAt': now,
    });
    await batch.commit();
  }

  /// العميل اختار يتخطى التقييم: الطلب مبيرجعش يظهر له كتقييم معلّق.
  static Future<void> skip(Order order) {
    return db.collection('orders').doc(order.id).update({'ratingSkipped': true});
  }
}
