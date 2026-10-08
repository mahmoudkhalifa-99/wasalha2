import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../models/review.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';

/// آراء وتقييمات العملاء للكباتن. بتتعرض للسوبر أدمن (ADMIN) والمشغّل (OPERATOR).
/// الودجت مش بتعمل scroll لوحدها (Column عادي) فينفع تتحط جوه أي SingleChildScrollView.
/// السوبر أدمن بس يقدر يحذف تعليق (إشراف).
class ReviewsView extends StatefulWidget {
  final AppUser user;
  const ReviewsView({super.key, required this.user});

  @override
  State<ReviewsView> createState() => _ReviewsViewState();
}

class _ReviewsViewState extends State<ReviewsView> {
  static const _pageSize = 100;

  StreamSubscription? _sub;
  List<Review> _reviews = [];
  bool _loading = true;
  Object? _error;
  int _limit = _pageSize;

  int _starFilter = 0; // 0 = الكل
  bool _onlyComments = false;
  String? _driverFilter; // driverId
  String _query = '';

  bool get _isAdmin => widget.user.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    _sub = db
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _reviews = snap.docs
            .map((d) => Review.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
        _loading = false;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    });
  }

  List<Review> get _filtered {
    final q = _query.trim().toLowerCase();
    return _reviews.where((r) {
      if (_starFilter != 0 && r.rating != _starFilter) return false;
      if (_onlyComments && r.comment.isEmpty) return false;
      if (_driverFilter != null && r.driverId != _driverFilter) return false;
      if (q.isNotEmpty &&
          !r.driverName.toLowerCase().contains(q) &&
          !r.customerName.toLowerCase().contains(q) &&
          !r.comment.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _delete(Review r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف التقييم؟'),
          content: const Text('هيتحذف التقييم نهائيًا من قائمة الآراء.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await db.collection('reviews').doc(r.id).delete();
    } catch (e) {
      if (mounted) showAppAlert(context, 'تعذر الحذف: ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summary(),
          const SizedBox(height: 16),
          _filters(),
          const SizedBox(height: 16),
          _body(),
        ],
      ),
    );
  }

  Widget _summary() {
    final total = _reviews.length;
    final avg = total == 0
        ? 0.0
        : _reviews.fold<int>(0, (a, r) => a + r.rating) / total;
    final low = _reviews.where((r) => r.rating <= 2).length;
    final withC = _reviews.where((r) => r.comment.isNotEmpty).length;
    final stats = driverReviewStats(_reviews);
    final worst = stats.where((d) => d.count >= 2).take(3).toList();

    Widget cell(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: C.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: Sh.sm(),
            ),
            child: Column(
              children: [
                Text(value, style: T.s(22, T.w900, color)),
                const SizedBox(height: 4),
                Text(label,
                    textAlign: TextAlign.center,
                    style: T.s(10, T.w900, C.slate400)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            cell('متوسط التقييم', total == 0 ? '—' : avg.toStringAsFixed(1),
                C.amber500),
            const SizedBox(width: 8),
            cell('عدد التقييمات', '$total', C.slate900),
            const SizedBox(width: 8),
            cell('بتعليق', '$withC', C.indigo500),
            const SizedBox(width: 8),
            cell('منخفضة (١-٢)', '$low', C.rose500),
          ],
        ),
        if (worst.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.rose50,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كباتن الأقل تقييمًا',
                    style: T.s(12, T.w900, C.rose500)),
                const SizedBox(height: 8),
                for (final d in worst)
                  GestureDetector(
                    onTap: () => setState(() => _driverFilter = d.driverId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                d.driverName.isEmpty ? 'كابتن' : d.driverName,
                                style: T.s(13, T.w900, C.slate900)),
                          ),
                          Text('${d.average.toStringAsFixed(1)} ★  (${d.count})',
                              style: T.s(12, T.w900, C.slate500)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? C.slate950 : C.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? C.slate950 : C.slate100, width: 2),
        ),
        child: Text(label,
            style: T.s(12, T.w900, active ? C.white : C.slate500)),
      ),
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.slate100, width: 2),
          ),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            textAlign: TextAlign.right,
            style: T.s(13, T.w700, C.slate800),
            decoration: InputDecoration(
              border: InputBorder.none,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              hintText: 'بحث باسم الكابتن أو العميل أو في التعليقات',
              hintStyle: T.s(12, T.w700, C.gray400),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('الكل', _starFilter == 0, () => setState(() => _starFilter = 0)),
            for (var st = 5; st >= 1; st--)
              _chip('$st ★', _starFilter == st,
                  () => setState(() => _starFilter = _starFilter == st ? 0 : st)),
            _chip('بتعليق بس', _onlyComments,
                () => setState(() => _onlyComments = !_onlyComments)),
            if (_driverFilter != null)
              _chip('إلغاء فلتر الكابتن ✕', true,
                  () => setState(() => _driverFilter = null)),
          ],
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: Spinner(size: 32)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Text('تعذر تحميل التقييمات: ${friendlyError(_error!)}',
                textAlign: TextAlign.center,
                style: T.s(13, T.w900, C.rose500)),
            const SizedBox(height: 12),
            _chip('إعادة المحاولة', true, _listen),
          ],
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Text(
              _reviews.isEmpty ? 'لسه مفيش تقييمات' : 'مفيش نتائج بالفلاتر دي',
              style: T.s(14, T.w900, C.slate400)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in list) ...[
          _reviewCard(r),
          const SizedBox(height: 12),
        ],
        if (_reviews.length >= _limit)
          Center(
            child: _chip('تحميل المزيد', false, () {
              _limit += _pageSize;
              _listen();
            }),
          ),
      ],
    );
  }

  Widget _reviewCard(Review r) {
    final date = r.createdAt == 0
        ? ''
        : intl.DateFormat('yyyy/MM/dd  HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(r.createdAt));
    final low = r.rating <= 2;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: low ? C.rose50 : C.slate100, width: 2),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var st = 1; st <= 5; st++)
                Icon(LucideIcons.star,
                    size: 18, color: r.rating >= st ? C.amber400 : C.slate200),
              const Spacer(),
              Text(date, style: T.s(10, T.w700, C.slate400)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                    'الكابتن: ${r.driverName.isEmpty ? "—" : r.driverName}',
                    style: T.s(13, T.w900, C.slate900)),
              ),
              if (_isAdmin)
                GestureDetector(
                  onTap: () => _delete(r),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(LucideIcons.trash2, size: 18, color: C.rose500),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('العميل: ${r.customerName.isEmpty ? "—" : r.customerName}',
              style: T.s(12, T.w700, C.slate500)),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.slate50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(r.comment,
                  style: T.s(13, T.w700, C.slate800, height: 1.6)),
            ),
          ],
          const SizedBox(height: 8),
          Text('طلب #${r.orderId.length > 6 ? r.orderId.substring(0, 6) : r.orderId}',
              style: T.s(10, T.w700, C.slate400)),
        ],
      ),
    );
  }
}
