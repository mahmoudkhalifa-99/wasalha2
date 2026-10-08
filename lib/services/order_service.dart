// نسخة Dart من services/orderService.ts — نفس المنطق بالظبط.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/models.dart';
import 'firebase_service.dart';

/// Strict validation for order status transitions
const Map<OrderStatus, List<OrderStatus>> _validTransitions = {
  OrderStatus.draft: [OrderStatus.pending, OrderStatus.cancelled],
  OrderStatus.pending: [OrderStatus.assigned, OrderStatus.cancelled],
  OrderStatus.assigned: [OrderStatus.picked, OrderStatus.cancelled],
  // الواجهة بتنقل الطلب من PICKED لـ DELIVERED مباشرة (مفيش زر لـ IN_DELIVERY)
  OrderStatus.picked: [
    OrderStatus.inDelivery,
    OrderStatus.delivered,
    OrderStatus.cancelled
  ],
  OrderStatus.inDelivery: [OrderStatus.delivered, OrderStatus.cancelled],
  OrderStatus.delivered: [],
  OrderStatus.cancelled: [],
};

/// Validates if a status transition is allowed
bool isValidTransition(OrderStatus currentStatus, OrderStatus nextStatus) {
  if (currentStatus == nextStatus) return true;
  return _validTransitions[currentStatus]?.contains(nextStatus) ?? false;
}

/// Creates a new order in Firestore. [orderData] هي خريطة حقول الطلب.
Future<String> createOrder(Map<String, dynamic> orderData) async {
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const initialStatus = OrderStatus.pending;

    final newOrder = <String, dynamic>{
      ...orderData,
      'status': initialStatus.value,
      'createdAt': timestamp,
      'updatedAt': timestamp,
      'statusHistory': [
        StatusHistoryItem(
          status: initialStatus,
          changedAt: timestamp,
          changedBy: (orderData['customerId'] as String?) ?? 'SYSTEM',
        ).toMap()
      ],
    };

    final docRef = await db
        .collection('orders')
        .add(stripFirestore(newOrder) as Map<String, dynamic>);
    return docRef.id;
  } catch (error) {
    handleFirestoreError(error, OperationType.create, 'orders');
  }
}

/// Assigns an order to a specific courier
Future<void> assignOrder(
    String orderId, String courierId, String adminId) async {
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final orderRef = db.collection('orders').doc(orderId);
    final orderSnap = await orderRef.get();

    if (!orderSnap.exists) throw Exception('Order not found');
    final order = Order.fromMap(orderSnap.data()!, orderSnap.id);

    if (order.status != OrderStatus.pending) {
      throw Exception('Order must be in PENDING status to be assigned');
    }

    final statusHistoryItem = StatusHistoryItem(
      status: OrderStatus.assigned,
      changedAt: timestamp,
      changedBy: adminId,
    );

    await orderRef.update({
      'status': OrderStatus.assigned.value,
      'assignedTo': courierId,
      'driverId': courierId, // Mapping for backward compatibility if needed
      'updatedAt': timestamp,
      'statusHistory': FieldValue.arrayUnion([statusHistoryItem.toMap()]),
    });

    // Update courier workload
    final courierDocs = await db
        .collection('couriers')
        .where('userId', isEqualTo: courierId)
        .limit(1)
        .get();
    if (courierDocs.docs.isNotEmpty) {
      await courierDocs.docs.first.reference
          .update({'currentOrdersCount': FieldValue.increment(1)});
    }
  } catch (error) {
    handleFirestoreError(error, OperationType.update, 'orders/$orderId');
  }
}

/// Updates the status of an order with validation
Future<void> updateOrderStatus(
  String orderId,
  OrderStatus newStatus,
  String userId,
  UserRole userRole,
) async {
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final orderRef = db.collection('orders').doc(orderId);
    final orderSnap = await orderRef.get();

    if (!orderSnap.exists) throw Exception('Order not found');
    final order = Order.fromMap(orderSnap.data()!, orderSnap.id);

    // Access Control
    if (userRole == UserRole.customer && order.customerId != userId) {
      throw Exception('Unauthorized');
    }
    if (userRole == UserRole.driver &&
        (order.assignedTo != userId && order.driverId != userId)) {
      throw Exception('Unauthorized');
    }

    // التسليم النهائي: لازم العميل يكون أكد الاستلام الأول
    if (newStatus == OrderStatus.delivered &&
        userRole == UserRole.driver &&
        !order.customerReceived) {
      throw Exception('لازم العميل يضغط "تم الاستلام" أولاً قبل التسليم النهائي');
    }

    // Lifecycle Validation
    if (!isValidTransition(order.status, newStatus)) {
      throw Exception(
          'Invalid transition from ${order.status.value} to ${newStatus.value}');
    }

    final statusHistoryItem = StatusHistoryItem(
      status: newStatus,
      changedAt: timestamp,
      changedBy: userId,
    );

    final updates = <String, dynamic>{
      'status': newStatus.value,
      'updatedAt': timestamp,
      'statusHistory': FieldValue.arrayUnion([statusHistoryItem.toMap()]),
    };

    // If delivered or cancelled, decrement courier workload
    if ((newStatus == OrderStatus.delivered ||
            newStatus == OrderStatus.cancelled) &&
        order.assignedTo != null) {
      final courierDocs = await db
          .collection('couriers')
          .where('userId', isEqualTo: order.assignedTo)
          .limit(1)
          .get();
      if (courierDocs.docs.isNotEmpty) {
        await courierDocs.docs.first.reference
            .update({'currentOrdersCount': FieldValue.increment(-1)});
      }
    }

    await orderRef.update(updates);
  } catch (error) {
    handleFirestoreError(error, OperationType.update, 'orders/$orderId');
  }
}

/// اعتذار الكابتن: الطلب يرجع PENDING ويتشال منه بيانات الكابتن في تحديث واحد.
Future<void> releaseOrderFromCourier(String orderId, String courierId) async {
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final orderRef = db.collection('orders').doc(orderId);
    final snap = await orderRef.get();
    if (!snap.exists) throw Exception('Order not found');
    final order = Order.fromMap(snap.data()!, snap.id);

    if (order.assignedTo != courierId && order.driverId != courierId) {
      throw Exception('Unauthorized');
    }
    if (order.status != OrderStatus.assigned &&
        order.status != OrderStatus.picked) {
      throw Exception('لا يمكن الاعتذار عن مشوار في هذه الحالة');
    }

    await orderRef.update({
      'status': OrderStatus.pending.value,
      'updatedAt': timestamp,
      'statusHistory': FieldValue.arrayUnion([
        StatusHistoryItem(
          status: OrderStatus.pending,
          changedAt: timestamp,
          changedBy: courierId,
        ).toMap()
      ]),
      'driverId': FieldValue.delete(),
      'driverName': FieldValue.delete(),
      'driverPhone': FieldValue.delete(),
      'driverPhoto': FieldValue.delete(),
      'acceptedAt': FieldValue.delete(),
      'assignedTo': FieldValue.delete(),
    });

    try {
      final courierDocs = await db
          .collection('couriers')
          .where('userId', isEqualTo: courierId)
          .limit(1)
          .get();
      if (courierDocs.docs.isNotEmpty) {
        await courierDocs.docs.first.reference
            .update({'currentOrdersCount': FieldValue.increment(-1)});
      }
    } catch (e) {
      // تحديث عداد الطلبات اتسبّب بفشل جانبي، مش بنوقف إتمام الطلب بسببه
      debugPrint('courier counter update failed: $e');
    }
  } catch (error) {
    handleFirestoreError(error, OperationType.update, 'orders/$orderId');
  }
}

/// Automatically assigns an order to the courier with the lowest workload
Future<String?> autoAssignOrder(String orderId) async {
  try {
    final querySnapshot = await db
        .collection('couriers')
        .where('isActive', isEqualTo: true)
        .orderBy('currentOrdersCount', descending: false)
        .limit(1)
        .get();
    if (querySnapshot.docs.isEmpty) return null;

    final bestCourier =
        Courier.fromMap(querySnapshot.docs.first.data(), querySnapshot.docs.first.id);
    await assignOrder(orderId, bestCourier.userId, 'SYSTEM');
    return bestCourier.userId;
  } catch (error) {
    handleFirestoreError(error, OperationType.get, 'couriers');
  }
}
