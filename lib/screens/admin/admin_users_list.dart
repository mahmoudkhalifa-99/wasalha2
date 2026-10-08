import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app_router.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';

/// نسخة Flutter من pages/AdminUsersList.tsx
class AdminUsersList extends StatefulWidget {
  final AppUser user;
  const AdminUsersList({super.key, required this.user});

  @override
  State<AdminUsersList> createState() => _AdminUsersListState();
}

class _AdminUsersListState extends State<AdminUsersList> {
  List<AppUser> _users = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'ALL';
  final _scrollController = ScrollController();
  bool _scrollDown = true;
  StreamSubscription? _sub;

  static const _roles = ['ALL', 'CUSTOMER', 'DRIVER', 'OPERATOR', 'ADMIN'];

  @override
  void initState() {
    super.initState();
    _sub = db.collection('users').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _users = snap.docs
            .map((d) => AppUser.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
        _loading = false;
      });
    });
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      final down = pos.pixels + pos.viewportDimension < pos.maxScrollExtent - 150;
      if (down != _scrollDown) setState(() => _scrollDown = down);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<AppUser> get _filtered {
    final term = _searchCtrl.text.toLowerCase();
    return _users.where((u) {
      final matchesSearch =
          u.name.toLowerCase().contains(term) || u.phone.contains(term);
      final matchesRole = _roleFilter == 'ALL' || u.role.value == _roleFilter;
      return matchesSearch && matchesRole;
    }).toList();
  }

  Future<void> _handleDelete(AppUser u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('حذف نهائي؟', style: T.s(16, T.w900, C.slate900)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('تراجع', style: T.s(13, T.w700, C.slate500))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('حذف', style: T.s(13, T.w900, C.rose600))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await db.collection('users').doc(u.id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 160),
              child: Spinner(size: 48, color: C.indigo500)));
    }

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
                    _header(context),
                    const SizedBox(height: 24),
                    _searchAndFilters(),
                    const SizedBox(height: 24),
                    _usersGrid(context),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 40,
            child: PressScale(
              onTap: () {
                if (_scrollDown) {
                  _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                } else {
                  _scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.slate900,
                  shape: BoxShape.circle,
                  border: Border.all(color: C.white, width: 4),
                  boxShadow: Sh.xxl(),
                ),
                child: Icon(
                    _scrollDown ? LucideIcons.arrowDown : LucideIcons.arrowUp,
                    size: 24,
                    color: C.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.indigo500,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sh.xl(),
              ),
              child: const Icon(LucideIcons.users, size: 28, color: C.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('دليل الأعضاء',
                    style: T.s(24, T.w900, C.slate900, letterSpacing: -0.6)),
                Text('إدارة ${_users.length} مستخدم',
                    style: T.s(10, T.w700, C.slate400, letterSpacing: 1.2)),
              ],
            ),
          ],
        ),
        PressScale(
          onTap: () => AppRouter.of(context).go('/'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.slate100),
              boxShadow: Sh.sm(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.arrowRight, size: 20, color: C.slate400),
                const SizedBox(width: 8),
                Text('رجوع للرئيسية', style: T.s(11, T.w900, C.slate500)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: C.slate50),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(32),
            ),
            child: TextField(
              controller: _searchCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: T.s(13, T.w900, C.slate800),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(LucideIcons.search, size: 20, color: C.slate300),
                ),
                hintText: 'ابحث بالاسم أو رقم الموبايل...',
                hintStyle: T.s(13, T.w900, C.gray400),
                contentPadding: const EdgeInsets.symmetric(vertical: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final role in _roles)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _roleFilter = role),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _roleFilter == role
                              ? C.indigo500
                              : C.slate50,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow:
                              _roleFilter == role ? Sh.lg() : null,
                        ),
                        child: Text(role == 'ALL' ? 'الكل' : role,
                            style: T.s(
                                10,
                                T.w900,
                                _roleFilter == role
                                    ? C.white
                                    : C.slate400)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usersGrid(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 640 ? 2 : 1);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final u in _filtered)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 32 - 16 * (cols - 1)) /
                cols,
            child: _userCard(context, u),
          ),
      ],
    );
  }

  Widget _userCard(BuildContext context, AppUser u) {
    final isDriver = u.role == UserRole.driver;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(48),
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
                    Text(u.name,
                        overflow: TextOverflow.ellipsis,
                        style: T.s(15, T.w900, C.slate900)),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(u.phone,
                          style: T.s(10, T.w700, C.slate400,
                              letterSpacing: 1.0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 56,
                height: 56,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: C.slate100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: u.photoURL != null
                    ? SmartImage(u.photoURL, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                            u.name.isNotEmpty ? u.name.substring(0, 1) : 'ع',
                            style: T.s(18, T.w900, C.slate300))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(u.wallet.balance.toStringAsFixed(1),
                        style: T.s(13, T.w900, C.slate900)),
                    const SizedBox(width: 3),
                    Text('ج.م', style: T.s(9, T.w700, C.slate400)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDriver ? C.emerald100 : C.indigo50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(u.role.value,
                      style: T.s(8, T.w900,
                          isDriver ? C.emerald700 : C.indigo500,
                          letterSpacing: 1.2)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: () =>
                      AppRouter.of(context).go('/admin/edit-user/${u.id}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.slate900,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: Sh.xl(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.edit3,
                            size: 14, color: C.white),
                        const SizedBox(width: 8),
                        Text('تعديل شامل',
                            style: T.s(10, T.w900, C.white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                scale: 0.9,
                onTap: () => _handleDelete(u),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.rose50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(LucideIcons.trash2,
                      size: 16, color: C.rose500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
