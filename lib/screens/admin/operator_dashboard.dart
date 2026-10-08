import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config_constants.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../services/order_service.dart' as order_service;
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';
import 'broadcast_dialog.dart';
import 'reviews_view.dart';

String _districtNameFor(String? villageName) {
  if (villageName == null) return 'المنوفية';
  for (final d in menofiaData) {
    if (d.villages.any((v) => v.name == villageName)) return d.name;
  }
  return 'المنوفية';
}

/// نسخة Flutter من pages/OperatorDashboard.tsx
class OperatorDashboard extends StatefulWidget {
  final AppUser user;
  const OperatorDashboard({super.key, required this.user});

  @override
  State<OperatorDashboard> createState() => _OperatorDashboardState();
}

enum _OpTab { live, drivers, history, reviews }

class _OperatorDashboardState extends State<OperatorDashboard> {
  List<Order> _orders = [];
  List<AppUser> _drivers = [];
  _OpTab _activeTab = _OpTab.live;
  Order? _assignTarget;
  Order? _selectedOrderDetails;
  final _scrollController = ScrollController();
  bool _showScrollTop = false;

  StreamSubscription? _subOrders, _subDrivers;

  @override
  void initState() {
    super.initState();
    _subOrders = db
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _orders = snap.docs
            .map((d) => Order.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    }, onError: (e) => handleFirestoreError(e, OperationType.list, 'orders'));

    _subDrivers = db
        .collection('users')
        .where('role', isEqualTo: UserRole.driver.value)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _drivers = snap.docs
            .map((d) => AppUser.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    }, onError: (e) => handleFirestoreError(e, OperationType.list, 'users'));

    _scrollController.addListener(() {
      final show = _scrollController.offset > 400;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void dispose() {
    _subOrders?.cancel();
    _subDrivers?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleShareWhatsApp(Order order) async {
    final pickupDist = _districtNameFor(order.pickup.villageName);
    final dropoffDist = _districtNameFor(order.dropoff.villageName);
    final msg = '*📢 طلب متاح في وصلها الآن*\n'
        '📍 *من:* مركز $pickupDist (${order.pickup.villageName})\n'
        '🏁 *إلى:* مركز $dropoffDist (${order.dropoff.villageName})\n'
        '💰 *السعر:* ${order.price} ج.م\n'
        '🛵 *المركبة:* ${order.requestedVehicleType.value}\n'
        '_افتح التطبيق الآن واقبل الطلب!_';
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleCancelOrder(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('إلغاء الطلب؟', style: T.s(16, T.w900, C.slate900)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('تراجع', style: T.s(13, T.w700, C.slate500))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('إلغاء الطلب', style: T.s(13, T.w900, C.rose600))),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await order_service.updateOrderStatus(order.id, OrderStatus.cancelled,
          'OPERATOR_UI', UserRole.operator);
    } catch (e) {
      if (mounted) showAppAlert(context, 'فشل الإلغاء');
    }
  }

  List<Order> get _liveOrders => _orders
      .where((o) =>
          o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled)
      .toList();
  List<Order> get _historyOrders => _orders
      .where((o) =>
          o.status == OrderStatus.delivered || o.status == OrderStatus.cancelled)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bgLight,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerBar(),
                    const SizedBox(height: 24),
                    if (_activeTab == _OpTab.live) _liveTab(context),
                    if (_activeTab == _OpTab.history) _historyTab(),
                    if (_activeTab == _OpTab.drivers) _driversTab(context),
                    if (_activeTab == _OpTab.reviews) ReviewsView(user: widget.user),
                  ],
                ),
              ),
            ),
          ),
          if (_showScrollTop)
            Positioned(
              bottom: 24,
              left: 24,
              child: PressScale(
                onTap: () => _scrollController.animateTo(0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.slate900,
                    shape: BoxShape.circle,
                    boxShadow: Sh.xxl(),
                  ),
                  child: const Icon(LucideIcons.arrowUp,
                      size: 24, color: C.white),
                ),
              ),
            ),
          if (_assignTarget != null)
            _ManualAssignModal(
              order: _assignTarget!,
              onClose: () => setState(() => _assignTarget = null),
            ),
          if (_selectedOrderDetails != null)
            _OrderDetailsModal(
              order: _selectedOrderDetails!,
              onClose: () => setState(() => _selectedOrderDetails = null),
            ),
        ],
      ),
    );
  }

  Widget _headerBar() {
    final approvedCount =
        _drivers.where((d) => d.status == UserStatus.approved).length;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xl(),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: C.slate900,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: Sh.xxl(),
                ),
                child: const Pulse(
                    child: Icon(LucideIcons.activity,
                        size: 32, color: Color(0xFF34D399))),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('تحكم المنوفية',
                      style: T.s(24, T.w900, C.slate950, letterSpacing: -0.6)),
                  Text('المراقبة المركزية للرحلات',
                      style: T.s(10, T.w700, C.slate400, letterSpacing: 1.4)),
                ],
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Expanded(child: _tabChip(_OpTab.reviews, LucideIcons.star, 'الآراء', null)),
                const SizedBox(width: 4),
                Expanded(child: _tabChip(_OpTab.history, LucideIcons.clock, 'السجل', null)),
                const SizedBox(width: 4),
                Expanded(child: _tabChip(_OpTab.drivers, LucideIcons.bike, 'الكباتن', approvedCount)),
                const SizedBox(width: 4),
                Expanded(child: _tabChip(_OpTab.live, LucideIcons.zap, 'النشاط', _liveOrders.length)),
              ],
            ),
          ),
          PressScale(
            scale: 0.97,
            onTap: () => showBroadcastDialog(context, sender: widget.user),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: C.emerald50,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: C.emerald200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.send, size: 16, color: C.emerald600),
                  const SizedBox(width: 8),
                  Text('رسالة للمستخدمين / الكباتن',
                      style: T.s(12, T.w900, C.emerald700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(_OpTab tab, IconData icon, String label, int? count) {
    final active = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          color: active ? C.slate950 : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active ? Sh.xxl() : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? C.white : C.slate400),
            const SizedBox(width: 8),
            Text(label,
                style:
                    T.s(11, T.w900, active ? C.white : C.slate400)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? C.emerald500 : C.slate200,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count',
                    style: T.s(8, T.w900,
                        active ? C.white : C.slate400)),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  // ── تبويب النشاط الحي ──

  Widget _liveTab(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 640 ? 2 : 1);
    if (_liveOrders.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 160),
        decoration: BoxDecoration(
          color: C.white,
          borderRadius: BorderRadius.circular(64),
          border: Border.all(
              color: C.slate100, width: 4, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.zap, size: 80, color: C.slate100),
            const SizedBox(height: 24),
            Text('لا توجد رحلات نشطة حالياً',
                style: T.s(20, T.w900, C.slate300)),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      children: [
        for (final order in _liveOrders)
          SizedBox(
            width: (width - 32 - 24 * (cols - 1)) / cols,
            child: _liveOrderCard(order),
          ),
      ],
    );
  }

  Widget _liveOrderCard(Order order) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(64),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xxl(),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedOrderDetails = order),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  color: C.slate50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(order.status.value,
                              style: T.s(10, T.w900, C.slate700,
                                  letterSpacing: 1.2)),
                          const SizedBox(width: 10),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: order.driverId != null
                                  ? C.emerald500
                                  : C.amber500,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('${order.price.toInt()}',
                              style: T.s(26, T.w900, C.slate900)),
                          const SizedBox(width: 4),
                          Text('ج.م',
                              style: T.s(11, T.w700, C.slate400)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('المسار',
                                  style: T.s(10, T.w900, C.slate400,
                                      letterSpacing: 1.2)),
                              const SizedBox(height: 4),
                              Text(order.pickup.villageName ?? '',
                                  textAlign: TextAlign.right,
                                  style: T.s(16, T.w900, C.slate800)),
                              Text('← ${order.dropoff.villageName ?? ""}',
                                  textAlign: TextAlign.right,
                                  style: T.s(12, T.w900, C.emerald500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: C.emerald50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(LucideIcons.mapPin,
                              size: 20, color: C.emerald600),
                        ),
                      ],
                    ),
                    if (order.category == OrderCategory.food &&
                        order.foodItems != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: C.slate50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: C.slate100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('الوجبات:',
                                style: T.s(8, T.w900, C.slate400,
                                    letterSpacing: 1.2)),
                            Text(
                                order.foodItems!.map((i) => i.name).join('، '),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: T.s(11, T.w700, C.slate600)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: C.slate50)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(order.customerPhone,
                                style: T.s(11, T.w700, C.slate400,
                                    letterSpacing: 1.2)),
                          ),
                          const SizedBox(width: 10),
                          const Icon(LucideIcons.smartphone,
                              size: 18, color: C.slate300),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: order.driverId == null
                              ? PressScale(
                                  onTap: () =>
                                      setState(() => _assignTarget = order),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 20),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: C.amber500,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: Sh.xl(),
                                    ),
                                    child: Text('توجيه كابتن',
                                        style: T.s(11, T.w900, C.white)),
                                  ),
                                )
                              : PressScale(
                                  onTap: () => launchUrl(
                                      Uri.parse('tel:${order.driverPhone}')),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 20),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: C.slate950,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: Sh.xxl(),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(LucideIcons.phone,
                                            size: 16, color: C.white),
                                        const SizedBox(width: 10),
                                        Text('اتصال',
                                            style:
                                                T.s(11, T.w900, C.white)),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          onTap: () => _handleShareWhatsApp(order),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: C.emerald50,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(LucideIcons.share2,
                                size: 22, color: C.emerald600),
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => _handleCancelOrder(order),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('إلغاء الرحلة',
                            textAlign: TextAlign.center,
                            style: T.s(9, T.w900, C.rose500,
                                letterSpacing: 1.4)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 24,
            left: 24,
            child: PressScale(
              scale: 0.9,
              onTap: () => setState(() => _selectedOrderDetails = order),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: Sh.sm(),
                ),
                child: const Icon(LucideIcons.eye,
                    size: 20, color: C.slate400),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── تبويب السجل ──

  Widget _historyTab() {
    final completed =
        _historyOrders.where((o) => o.status != OrderStatus.cancelled).toList();
    final cancelled =
        _historyOrders.where((o) => o.status == OrderStatus.cancelled).length;
    final totalSales =
        completed.fold(0.0, (sum, o) => sum + o.price);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(64),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xxl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 500 ? 3 : 1;
            final cards = [
              _statBox(C.emerald50, LucideIcons.checkCircle2, C.emerald600,
                  '${completed.length}', 'مكتملة', C.emerald700),
              _statBox(C.slate900, LucideIcons.dollarSign, Color(0xFF34D399),
                  intl.NumberFormat('#,##0', 'en_US').format(totalSales),
                  'إجمالي المبيعات', C.white),
              _statBox(C.rose50, LucideIcons.xCircle, C.rose600,
                  '$cancelled', 'ملغاة', C.rose600),
            ];
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in cards)
                  SizedBox(
                      width: (box.maxWidth - 16 * (cols - 1)) / cols,
                      child: c),
              ],
            );
          }),
          const SizedBox(height: 32),
          for (final order in _historyOrders.take(50)) _historyRow(order),
        ],
      ),
    );
  }

  Widget _statBox(Color bg, IconData icon, Color iconColor, String value,
      String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: iconColor),
          const SizedBox(height: 10),
          Text(value, style: T.s(22, T.w900, textColor)),
          Text(label,
              style: T.s(10, T.w900, textColor.withOpacity(0.8),
                  letterSpacing: 1.2)),
        ],
      ),
    );
  }

  Widget _historyRow(Order order) {
    final isCancelled = order.status == OrderStatus.cancelled;
    final date = DateTime.fromMillisecondsSinceEpoch(order.createdAt);
    final dateStr = intl.DateFormat('yyyy/MM/dd', 'ar').format(date);
    final timeStr = intl.DateFormat('hh:mm a', 'ar').format(date);
    return GestureDetector(
      onTap: () => setState(() => _selectedOrderDetails = order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: C.slate50,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    '${order.pickup.villageName ?? ""} ← ${order.dropoff.villageName ?? ""}',
                    style: T.s(13, T.w900, C.slate800)),
                const SizedBox(height: 4),
                Text('$dateStr • $timeStr',
                    style: T.s(9, T.w700, C.slate400, letterSpacing: 1.2)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${order.price.toInt()} ج.م',
                    style: T.s(16, T.w900, C.slate900)),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCancelled ? C.rose100 : C.emerald100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(order.status.value,
                      style: T.s(8, T.w900,
                          isCancelled ? C.rose600 : C.emerald600,
                          letterSpacing: 1.2)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── تبويب الكباتن ──

  Widget _driversTab(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 640 ? 2 : 1);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(64),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xl(),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final d in _drivers)
            SizedBox(
              width: (width - 80 - 16 * (cols - 1)) / cols,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: C.slate50,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Row(
                  children: [
                    PressScale(
                      scale: 0.9,
                      onTap: () => launchUrl(Uri.parse('tel:${d.phone}')),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: C.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: Sh.sm(),
                        ),
                        child: const Icon(LucideIcons.phone,
                            size: 20, color: C.slate400),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(d.name,
                                overflow: TextOverflow.ellipsis,
                                style: T.s(16, T.w900, C.slate900)),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(d.phone,
                                  style: T.s(11, T.w700, C.slate400)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(d.status.value,
                                    style: T.s(9, T.w900, C.slate400,
                                        letterSpacing: 1.2)),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: d.status == UserStatus.approved
                                        ? C.emerald500
                                        : C.rose500,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: Sh.sm(),
                      ),
                      child: Text(
                          d.name.isNotEmpty ? d.name.substring(0, 1) : 'ك',
                          style: T.s(24, T.w900, C.slate300)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════ OrderDetailsModal ═══════════════════════

class _OrderDetailsModal extends StatelessWidget {
  final Order order;
  final VoidCallback onClose;
  const _OrderDetailsModal({required this.order, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GlassBox(
        sigma: 20,
        color: C.slate950.withOpacity(0.9),
        borderRadius: BorderRadius.zero,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672, maxHeight: 700),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(56),
                    boxShadow: Sh.xxl(),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: C.slate50,
                          border: Border(bottom: BorderSide(color: C.slate100)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PressScale(
                              onTap: onClose,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: C.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: C.slate100),
                                  boxShadow: Sh.sm(),
                                ),
                                child: const Icon(LucideIcons.x,
                                    size: 24, color: C.slate400),
                              ),
                            ),
                            Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('تفاصيل الرحلة',
                                        style: T.s(18, T.w900, C.slate900)),
                                    Text('تطبيق وصلها - وحدة التحكم',
                                        style:
                                            T.s(9, T.w700, C.slate400,
                                                letterSpacing: 1.2)),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: C.emerald600,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: Sh.lg(),
                                  ),
                                  child: const Icon(LucideIcons.zap,
                                      size: 20, color: C.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: C.slate900,
                                        borderRadius:
                                            BorderRadius.circular(28),
                                      ),
                                      child: Column(
                                        children: [
                                          Text('الحالة',
                                              style: T.s(9, T.w900,
                                                  C.slate400,
                                                  letterSpacing: 1.2)),
                                          const SizedBox(height: 4),
                                          Text(order.status.value,
                                              style: T.s(
                                                  13, T.w900, C.white)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: C.emerald50,
                                        borderRadius:
                                            BorderRadius.circular(28),
                                        border: Border.all(
                                            color: C.emerald100, width: 2),
                                      ),
                                      child: Column(
                                        children: [
                                          Text('التكلفة',
                                              style: T.s(9, T.w900,
                                                  C.emerald600,
                                                  letterSpacing: 1.2)),
                                          const SizedBox(height: 4),
                                          Text('${order.price} ج.م',
                                              style: T.s(
                                                  22, T.w900, C.emerald700)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (order.category == OrderCategory.food &&
                                  order.foodItems != null) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: C.white,
                                    borderRadius: BorderRadius.circular(32),
                                    border:
                                        Border.all(color: C.emerald100),
                                    boxShadow: Sh.sm(),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text('قائمة الوجبات المطلوبة:',
                                              style: T.s(
                                                  13, T.w900, C.slate800)),
                                          const SizedBox(width: 10),
                                          const Icon(
                                              LucideIcons.clipboardList,
                                              size: 20,
                                              color: C.emerald500),
                                        ],
                                      ),
                                      for (final item in order.foodItems!)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          decoration: BoxDecoration(
                                            border: Border(
                                                top: BorderSide(
                                                    color: C.slate100)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceBetween,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 14,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: C.slate900,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12),
                                                ),
                                                child: Text(
                                                    'الكمية: ${item.quantity}',
                                                    style: T.s(
                                                        10,
                                                        T.w900,
                                                        const Color(
                                                            0xFF34D399))),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(item.name,
                                                      style: T.s(13, T.w900,
                                                          C.slate800)),
                                                  Text(
                                                      'سعر القطعة: ${item.price} ج.م',
                                                      style: T.s(9, T.w700,
                                                          C.slate400)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                      child: _participantCard(
                                          'العميل',
                                          order.customerPhone,
                                          LucideIcons.user,
                                          C.emerald50,
                                          C.emerald600,
                                          order.customerPhone)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: _participantCard(
                                          'الكابتن',
                                          order.driverName ?? 'لم يحدد',
                                          LucideIcons.bike,
                                          C.amber50,
                                          C.amber600,
                                          order.driverPhone)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: C.slate50,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text('الاستلام',
                                              style: T.s(9, T.w900,
                                                  C.emerald600,
                                                  letterSpacing: 1.2)),
                                          Text(order.pickup.villageName ?? '',
                                              style: T.s(13, T.w900,
                                                  C.slate800)),
                                          const SizedBox(height: 16),
                                          Text('الوصول',
                                              style: T.s(9, T.w900,
                                                  C.rose600,
                                                  letterSpacing: 1.2)),
                                          Text(
                                              order.dropoff.villageName ?? '',
                                              style: T.s(13, T.w900,
                                                  C.slate800)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      children: [
                                        Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                                color: C.emerald500,
                                                shape: BoxShape.circle)),
                                        Container(
                                            width: 2,
                                            height: 48,
                                            color: C.slate200),
                                        Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                                color: C.rose500,
                                                shape: BoxShape.circle)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: C.slate50,
                          border: Border(top: BorderSide(color: C.slate100)),
                        ),
                        child: PressScale(
                          onTap: onClose,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.slate900,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text('إغلاق',
                                style: T.s(11, T.w900, C.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _participantCard(String label, String value, IconData icon,
      Color iconBg, Color iconColor, String? phone) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(label,
                        style: T.s(9, T.w900, C.slate400,
                            letterSpacing: 1.2)),
                    Text(value,
                        overflow: TextOverflow.ellipsis,
                        style: T.s(12, T.w900, C.slate800)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (phone != null)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('tel:$phone')),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: C.slate50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.phone, size: 14, color: iconColor),
                    const SizedBox(width: 8),
                    Text('اتصال', style: T.s(10, T.w700, C.slate600)),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('بانتظار عرض...',
                  textAlign: TextAlign.center,
                  style: T.s(9, T.w700, C.slate300)),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════ ManualAssignModal ═══════════════════════

class _ManualAssignModal extends StatefulWidget {
  final Order order;
  final VoidCallback onClose;
  const _ManualAssignModal({required this.order, required this.onClose});

  @override
  State<_ManualAssignModal> createState() => _ManualAssignModalState();
}

class _ManualAssignModalState extends State<_ManualAssignModal> {
  List<AppUser> _drivers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDrivers();
  }

  Future<void> _fetchDrivers() async {
    try {
      final snap = await db
          .collection('users')
          .where('role', isEqualTo: UserRole.driver.value)
          .where('status', isEqualTo: UserStatus.approved.value)
          .limit(30)
          .get();
      if (mounted) {
        setState(() {
          _drivers = snap.docs
              .map((d) => AppUser.fromMap(
                  stripFirestore(d.data()) as Map<String, dynamic>, d.id))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assignDriver(AppUser driver) async {
    try {
      await order_service.assignOrder(widget.order.id, driver.id, 'OPERATOR');
      widget.onClose();
    } catch (e) {
      if (mounted) showAppAlert(context, 'فشل التوجيه: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GlassBox(
        sigma: 20,
        color: C.slate900.withOpacity(0.9),
        borderRadius: BorderRadius.zero,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 512, maxHeight: 560),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(56),
                    boxShadow: Sh.xxl(),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: widget.onClose,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: C.slate100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(LucideIcons.x,
                                  size: 20, color: C.slate600),
                            ),
                          ),
                          Text('توجيه كابتن',
                              style: T.s(20, T.w900, C.slate800)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: _loading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 80),
                                child: Center(
                                    child:
                                        Spinner(size: 32, color: C.emerald500)),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final d in _drivers)
                                      GestureDetector(
                                        onTap: () => _assignDriver(d),
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(18),
                                          decoration: BoxDecoration(
                                            color: C.slate50,
                                            borderRadius:
                                                BorderRadius.circular(32),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceBetween,
                                            children: [
                                              const Icon(
                                                  LucideIcons.chevronRight,
                                                  size: 20,
                                                  color: C.slate300),
                                              Row(
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .end,
                                                    children: [
                                                      Text(d.name,
                                                          style: T.s(
                                                              14,
                                                              T.w900,
                                                              C.slate800)),
                                                      Text(
                                                          d.vehicleType
                                                                  ?.value ??
                                                              '',
                                                          style: T.s(
                                                              9,
                                                              T.w700,
                                                              C.slate400,
                                                              letterSpacing:
                                                                  1.2)),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Container(
                                                    width: 48,
                                                    height: 48,
                                                    alignment:
                                                        Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: C.white,
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(12),
                                                      boxShadow: Sh.sm(),
                                                    ),
                                                    child: Text(
                                                        d.name.isNotEmpty
                                                            ? d.name
                                                                .substring(0, 1)
                                                            : 'ك',
                                                        style: T.s(
                                                            18,
                                                            T.w900,
                                                            C.slate300)),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
