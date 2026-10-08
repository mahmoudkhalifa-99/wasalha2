import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';
import 'admin_ads_manager.dart';
import 'app_status_card.dart';
import 'broadcast_dialog.dart';
import 'admin_geography_manager.dart';
import 'admin_restaurant_manager.dart';
import 'admin_users_list.dart';
import '../../features/captain_accounts/ui/captain_accounts_view.dart';
import '../../features/verification/ui/admin_verification_view.dart';
import 'reviews_view.dart';

enum _AdminTab {
  dashboard,
  users,
  restaurants,
  ads,
  geo,
  reviews,
  verification,
  captainAccounts
}

/// نسخة Flutter من pages/SuperAdminDashboard.tsx
class SuperAdminDashboard extends StatefulWidget {
  final AppUser user;
  const SuperAdminDashboard({super.key, required this.user});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  List<AppUser> _users = [];
  List<Order> _orders = [];
  _AdminTab _activeTab = _AdminTab.dashboard;

  final _scrollController = ScrollController();
  final _activityKey = GlobalKey();
  bool _showScrollTop = false;

  StreamSubscription? _subUsers, _subOrders;

  @override
  void initState() {
    super.initState();
    _subUsers = db.collection('users').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _users = snap.docs
            .map((d) => AppUser.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    });
    _subOrders = db
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _orders = snap.docs
            .map((d) => Order.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    });
    _scrollController.addListener(() {
      final show = _scrollController.offset > 400;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void dispose() {
    _subUsers?.cancel();
    _subOrders?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  ({double systemBalance, int driversCount, int customersCount, int activeOrders})
      get _stats {
    final systemBalance =
        _users.fold(0.0, (acc, u) => acc + u.wallet.balance);
    final driversCount = _users
        .where((u) => u.role == UserRole.driver && u.status == UserStatus.approved)
        .length;
    final customersCount = _users.where((u) => u.role == UserRole.customer).length;
    final activeOrders = _orders
        .where((o) =>
            o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled)
        .length;
    return (
      systemBalance: systemBalance,
      driversCount: driversCount,
      customersCount: customersCount,
      activeOrders: activeOrders
    );
  }

  ({Color bg, Color fg}) _statusBadge(OrderStatus s) {
    switch (s) {
      case OrderStatus.delivered:
        return (bg: C.emerald500.withOpacity(0.2), fg: C.emerald400);
      case OrderStatus.cancelled:
        return (bg: C.rose500.withOpacity(0.2), fg: C.rose400);
      default:
        return (bg: C.amber500.withOpacity(0.2), fg: C.amber400);
    }
  }

  void _scrollToActivity() {
    final ctx = _activityKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (_activeTab != _AdminTab.dashboard) {
      return Container(
        color: C.slate50,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: C.white,
                border: Border(bottom: BorderSide(color: C.slate100)),
                boxShadow: Sh.sm(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('وحدة التحكم',
                      style: T.s(13, T.w900, C.slate800)),
                  PressScale(
                    onTap: () => setState(() => _activeTab = _AdminTab.dashboard),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: C.slate900,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.arrowLeft,
                              size: 16, color: C.white),
                          const SizedBox(width: 8),
                          Text('العودة', style: T.s(11, T.w900, C.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _detailedView()),
          ],
        ),
      );
    }

    final s = _stats;
    return Container(
      color: C.bgLight,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1152),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      _topBar(),
                      const SizedBox(height: 32),
                      _statsGrid(s),
                      const SizedBox(height: 24),
                      AppStatusCard(admin: widget.user),
                      const SizedBox(height: 32),
                      _controlUnitsGrid(),
                      const SizedBox(height: 32),
                      _liveFeed(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showScrollTop)
            Positioned(
              bottom: 24,
              left: 24,
              child: PressScale(
                onTap: _scrollToTop,
                child: Container(
                  padding: const EdgeInsets.all(18),
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
        ],
      ),
    );
  }

  Widget _detailedView() {
    switch (_activeTab) {
      case _AdminTab.users:
        return AdminUsersList(user: widget.user);
      case _AdminTab.restaurants:
        return AdminRestaurantManager(user: widget.user);
      case _AdminTab.ads:
        return AdminAdsManager(user: widget.user);
      case _AdminTab.geo:
        return AdminGeographyManager(user: widget.user);
      case _AdminTab.verification:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: AdminVerificationView(user: widget.user),
            ),
          ),
        );
      case _AdminTab.captainAccounts:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CaptainAccountsView(user: widget.user),
            ),
          ),
        );
      case _AdminTab.reviews:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ReviewsView(user: widget.user),
            ),
          ),
        );
      case _AdminTab.dashboard:
        return const SizedBox.shrink();
    }
  }

  Widget _topBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.slate900,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: Sh.xxl(),
                ),
                child: const Icon(LucideIcons.shieldCheck,
                    size: 28, color: Color(0xFF34D399)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('مركز الإدارة العليا',
                          style: T.s(22, T.w900, C.slate900,
                              letterSpacing: -0.6)),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('التحكم المطلق في المنظومة',
                          style: T.s(9, T.w700, C.slate400,
                              letterSpacing: 1.2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.slate50),
                boxShadow: Sh.sm(),
              ),
              child: const Icon(LucideIcons.bell, size: 20, color: C.slate400),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.slate50),
                boxShadow: Sh.sm(),
              ),
              child: Transform.rotate(
                angle: 3.14159265,
                child: const Icon(LucideIcons.logOut, size: 20, color: C.slate400),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statsGrid(({double systemBalance, int driversCount, int customersCount, int activeOrders}) s) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 560 ? 2 : 1);
      final cards = [
        _statCard(
          bg: const Color(0xFF10B981),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('رصيد المنظومة',
                      style: T.s(10, T.w900, C.white.withOpacity(0.6),
                          letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('ج.م',
                          style: T.s(11, T.w700, C.white.withOpacity(0.6))),
                      const SizedBox(width: 6),
                      Text(
                          intl.NumberFormat('#,##0.0', 'en_US')
                              .format(s.systemBalance),
                          style: T.s(30, T.w900, C.white,
                              letterSpacing: -0.6)),
                    ],
                  ),
                ],
              ),
              PressScale(
                onTap: _scrollToActivity,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: C.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('متابعة النشاط',
                          style: T.s(9, T.w900, C.white)),
                      const SizedBox(width: 6),
                      const Icon(LucideIcons.arrowDown,
                          size: 12, color: C.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _statCard(
          bg: C.slate950,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('كباتن معتمدين',
                  style: T.s(10, T.w900, C.white.withOpacity(0.4),
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text('${s.driversCount}',
                  style: T.s(48, T.w900, C.white, letterSpacing: -0.6)),
            ],
          ),
        ),
        _statCard(
          bg: C.white,
          border: true,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('إجمالي العملاء',
                  style: T.s(10, T.w900, C.slate400, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text('${s.customersCount}',
                  style: T.s(48, T.w900, C.slate900, letterSpacing: -0.6)),
            ],
          ),
        ),
        _statCard(
          bg: C.white,
          border: true,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('رحلات نشطة',
                  style: T.s(10, T.w900, C.slate400, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text('${s.activeOrders}',
                  style: T.s(48, T.w900, C.slate900, letterSpacing: -0.6)),
            ],
          ),
        ),
      ];
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final c in cards)
            SizedBox(
                width: (box.maxWidth - 16 * (cols - 1)) / cols, child: c),
        ],
      );
    });
  }

  Widget _statCard({required Color bg, required Widget content, bool border = false}) {
    final narrow = MediaQuery.of(context).size.width < 560;
    return Container(
      height: narrow ? 140 : 200,
      padding: EdgeInsets.all(narrow ? 20 : 28),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(narrow ? 32 : 48),
        border: border ? Border.all(color: C.slate100) : null,
        boxShadow: border ? Sh.sm() : Sh.xxl(),
      ),
      child: content,
    );
  }

  Widget _controlUnitsGrid() {
    final items = [
      (_AdminTab.users, 'إدارة الأعضاء', 'تعديل، تفعيل، وحظر المستخدمين',
          LucideIcons.users, C.indigo50, C.indigo500),
      (_AdminTab.restaurants, 'إدارة المطاعم', 'إضافة مطاعم وتعديل المنيو',
          LucideIcons.utensilsCrossed, C.emerald50, C.emerald500),
      (_AdminTab.ads, 'إدارة الإعلانات', 'نشر عروض ترويجية',
          LucideIcons.megaphone, C.amber50, C.amber500),
      (_AdminTab.geo, 'إدارة الجغرافيا', 'إضافة قرى ومراكز جديدة',
          LucideIcons.mapPin, C.rose50, C.rose500),
      (_AdminTab.verification, 'توثيق الكباتن', 'مراجعة مستندات وهوية الكباتن',
          LucideIcons.shieldCheck, C.emerald50, C.emerald600),
      (_AdminTab.captainAccounts, 'حسابات الكباتن', 'عدد المشاوير والنسبة المستحقة لكل كابتن',
          LucideIcons.bike, C.indigo50, C.indigo500),
      (_AdminTab.reviews, 'آراء وتقييمات العملاء', 'تقييمات الكباتن وتعليقات العملاء',
          LucideIcons.star, C.amber50, C.amber500),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 700 ? 2 : 1;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final item in items)
            SizedBox(
              width: cols == 2 ? (box.maxWidth - 16) / 2 : box.maxWidth,
              child: PressScale(
                scale: 0.98,
                onTap: () => setState(() => _activeTab = item.$1),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(color: C.slate100),
                    boxShadow: Sh.sm(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(LucideIcons.chevronLeft,
                          size: 20, color: C.slate200),
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(item.$2,
                                  style: T.s(20, T.w900, C.slate900)),
                              Text(item.$3,
                                  style: T.s(10, T.w700, C.slate400)),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: item.$5,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Icon(item.$4, size: 28, color: item.$6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SizedBox(
            width: cols == 2 ? (box.maxWidth - 16) / 2 : box.maxWidth,
            child: PressScale(
              scale: 0.98,
              onTap: () => showBroadcastDialog(context, sender: widget.user),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: C.white,
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(color: C.slate100),
                  boxShadow: Sh.sm(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(LucideIcons.chevronLeft,
                        size: 20, color: C.slate200),
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('رسالة للمستخدمين',
                                style: T.s(20, T.w900, C.slate900)),
                            Text('إرسال لكل المستخدمين أو العملاء أو الكباتن',
                                style: T.s(10, T.w700, C.slate400)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: C.indigo50,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Icon(LucideIcons.send,
                              size: 28, color: C.indigo500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _liveFeed() {
    return Container(
      key: _activityKey,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.slate950,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.white.withOpacity(0.05)),
        boxShadow: Sh.xxl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('آخر العمليات',
                      style: T.s(20, T.w900, C.white)),
                  const SizedBox(width: 12),
                  const Pulse(
                      child: Icon(LucideIcons.activity,
                          size: 20, color: Color(0xFF10B981))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: C.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: C.white.withOpacity(0.1)),
                ),
                child: Text('Live Activity',
                    style: T.s(9, T.w900, const Color(0xFF34D399),
                        letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (final order in _orders) _activityRow(order),
        ],
      ),
    );
  }

  Widget _activityRow(Order order) {
    final badge = _statusBadge(order.status);
    final timeStr = intl.DateFormat('hh:mm a', 'ar')
        .format(DateTime.fromMillisecondsSinceEpoch(order.createdAt));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: C.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('ج.م', style: T.s(11, T.w700, C.white.withOpacity(0.5))),
                  const SizedBox(width: 4),
                  Text('${order.price.toInt()}',
                      style: T.s(22, T.w900, const Color(0xFF34D399))),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(order.status.value,
                    style: T.s(8, T.w900, badge.fg, letterSpacing: 1.2)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(order.pickup.villageName ?? '',
                      style: T.s(14, T.w900, C.slate200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('←',
                        style: T.s(14, T.w900,
                            const Color(0xFF34D399).withOpacity(0.5))),
                  ),
                  Text(order.dropoff.villageName ?? '',
                      style: T.s(14, T.w900, C.slate200)),
                ],
              ),
              const SizedBox(height: 4),
              Text('$timeStr • ${order.category.value}',
                  style: T.s(9, T.w700, C.slate500, letterSpacing: 1.2)),
            ],
          ),
        ],
      ),
    );
  }
}
