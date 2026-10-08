import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config_constants.dart';
import '../models/models.dart';
import '../pricing.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';
import '../widgets/fare_breakdown.dart';

/// نسخة Flutter من pages/ActivityView.tsx
class ActivityView extends StatefulWidget {
  final AppUser user;
  final VoidCallback onBack;
  const ActivityView({super.key, required this.user, required this.onBack});

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  List<Order> _orders = [];
  bool _loading = true;
  String _selectedDistrict = 'الكل';
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final field =
        widget.user.role == UserRole.driver ? 'driverId' : 'customerId';
    _sub = db
        .collection('orders')
        .where(field, isEqualTo: widget.user.id)
        .snapshots()
        .listen((snap) {
      final docs = snap.docs
          .map((d) => Order.fromMap(
              stripFirestore(d.data()) as Map<String, dynamic>, d.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _orders = docs;
        _loading = false;
      });
    }, onError: (e) => handleFirestoreError(e, OperationType.list, 'orders'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _getDistrictName(String? villageName) {
    if (villageName == null) return 'المنوفية';
    for (final d in menofiaData) {
      if (d.villages.any((v) => v.name == villageName)) return d.name;
    }
    return 'المنوفية';
  }

  ({Color bg, Color fg, Color border}) _statusStyle(OrderStatus s) {
    switch (s) {
      case OrderStatus.delivered:
        return (bg: C.emerald50, fg: C.emerald700, border: C.emerald200.withOpacity(0.6));
      case OrderStatus.cancelled:
        return (bg: C.rose50, fg: C.rose700, border: C.rose200.withOpacity(0.6));
      case OrderStatus.assigned:
      case OrderStatus.picked:
      case OrderStatus.inDelivery:
        return (bg: const Color(0xFFEFF6FF), fg: C.blue600, border: const Color(0x99BFDBFE));
      default:
        return (bg: C.slate100, fg: C.slate600, border: C.slate200);
    }
  }

  String _statusLabel(OrderStatus s) {
    if (s == OrderStatus.delivered) return 'تم التوصيل بنجاح';
    if (s == OrderStatus.cancelled) return 'تم الإلغاء';
    return s.value;
  }

  List<Order> get _filteredOrders {
    if (_selectedDistrict == 'الكل') return _orders;
    return _orders.where((o) {
      final p = _getDistrictName(o.pickup.villageName);
      final d = _getDistrictName(o.dropoff.villageName);
      return p == _selectedDistrict || d == _selectedDistrict;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.slate50,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PressScale(
                        scale: 0.9,
                        onTap: widget.onBack,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: C.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: C.slate200.withOpacity(0.7)),
                            boxShadow: Sh.sm(),
                          ),
                          child: const Icon(LucideIcons.chevronRight,
                              size: 20, color: C.slate700),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('سجل طلباتي ورحلاتي',
                              style: T.s(24, T.w900, C.slate900,
                                  letterSpacing: -0.5)),
                          const SizedBox(height: 2),
                          Text('تتبع طلباتك السابقة وتفاصيل كل مشوار',
                              style: T.s(11, T.w500, C.slate500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip('الكل', 'جميع المراكز'),
                        for (final d in menofiaData)
                          _filterChip(d.name, 'مركز ${d.name}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(child: Spinner(color: C.emerald600)),
                    )
                  else if (_filteredOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: C.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: C.slate200.withOpacity(0.7), width: 2),
                      ),
                      child: Column(
                        children: [
                          Icon(LucideIcons.filter,
                              size: 40, color: C.emerald600.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text('لا توجد طلبات مسجلة في هذا المركز حتى الآن',
                              textAlign: TextAlign.center,
                              style: T.s(13, T.w700, C.slate600)),
                          const SizedBox(height: 4),
                          Text('ابدأ بطلب مشوارك الأول الآن بضغطة زر',
                              style: T.s(11, T.w500, C.slate400)),
                        ],
                      ),
                    )
                  else
                    for (final order in _filteredOrders) _orderCard(order),
                  const SizedBox(height: 16),
                  Text('وصـــلــهــا • أمان وسرعة في كل مكان بالمنوفية',
                      textAlign: TextAlign.center,
                      style: T.s(10, T.w700, C.slate400)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _selectedDistrict == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedDistrict = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? C.emerald600 : C.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? C.emerald600 : C.slate200.withOpacity(0.7)),
            boxShadow: selected ? Sh.sm(color: C.emerald600.withOpacity(0.2)) : null,
          ),
          child: Text(label,
              style: T.s(11, T.w700, selected ? C.white : C.slate600)),
        ),
      ),
    );
  }

  Widget _orderCard(Order order) {
    final style = _statusStyle(order.status);
    final dateStr =
        intl.DateFormat('d MMMM y', 'ar').format(
            DateTime.fromMillisecondsSinceEpoch(order.createdAt));
    final isCar = order.requestedVehicleType == VehicleType.car;
    final otherPartyLabel =
        widget.user.role == UserRole.driver ? 'العميل:' : 'الكابتن:';
    final otherPartyValue = widget.user.role == UserRole.driver
        ? order.customerPhone
        : (order.driverName ?? 'كابتن معتمد');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.slate200.withOpacity(0.6)),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    Text('${order.price.toInt()}',
                        style: T.s(20, T.w900, C.slate900)),
                    const SizedBox(width: 4),
                    Text('ج.م', style: T.s(11, T.w700, C.slate400)),
                  ],
                ),
              ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(dateStr, style: T.s(11, T.w700, C.slate400)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: style.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: style.border),
                        ),
                        child: Text(_statusLabel(order.status),
                            style: T.s(10, T.w800, style.fg)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.emerald50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.emerald100),
                    ),
                    child: Icon(isCar ? LucideIcons.car : LucideIcons.bike,
                        size: 20, color: C.emerald600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.slate50.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.slate100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _routeRow(C.emerald500, 'من:',
                    '${order.pickup.villageName ?? "غير محدد"} (${_getDistrictName(order.pickup.villageName)})'),
                const SizedBox(height: 8),
                _routeRow(C.rose500, 'إلى:',
                    '${order.dropoff.villageName ?? "غير محدد"} (${_getDistrictName(order.dropoff.villageName)})'),
              ],
            ),
          ),
          if (widget.user.role == UserRole.driver &&
              order.status == OrderStatus.delivered) ...[
            const SizedBox(height: 12),
            FareBreakdownView(fare: tripFareOf(order)),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: C.slate100)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(otherPartyValue,
                        style: T.s(11, T.w900, C.emerald700)),
                    const SizedBox(width: 4),
                    Text(otherPartyLabel,
                        style: T.s(11, T.w700, C.slate500)),
                  ],
                ),
                Text(
                    'رقم الطلب: #${order.id.length >= 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id.toUpperCase()}',
                    style: T.s(11, T.w500, C.slate400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeRow(Color dot, String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: T.s(12, T.w800, C.slate800)),
        ),
        const SizedBox(width: 8),
        Text(label, style: T.s(12, T.w500, C.slate500)),
        const SizedBox(width: 8),
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      ],
    );
  }
}
