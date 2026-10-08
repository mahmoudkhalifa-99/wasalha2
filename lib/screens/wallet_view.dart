import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

class _Transaction {
  final String id;
  final String type; // CREDIT | DEBIT
  final double amount;
  final String description;
  final int createdAt;
  const _Transaction(
      {required this.id,
      required this.type,
      required this.amount,
      required this.description,
      required this.createdAt});
}

/// نسخة Flutter من pages/WalletView.tsx
class WalletView extends StatefulWidget {
  final AppUser user;
  final VoidCallback onBack;
  const WalletView({super.key, required this.user, required this.onBack});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  List<_Transaction> _transactions = [];
  bool _loading = true;
  bool _showTopUp = false;
  bool _showWithdraw = false;
  final _amountCtrl = TextEditingController();
  bool _isSubmitting = false;
  StreamSubscription? _sub;

  static const String _cashNumber = '01065019364'; // رقم الإدارة المعتمد

  @override
  void initState() {
    super.initState();
    _sub = db
        .collection('transactions')
        .where('userId', isEqualTo: widget.user.id)
        .snapshots()
        .listen((snap) {
      final docs = snap.docs.map((d) {
        final m = stripFirestore(d.data()) as Map<String, dynamic>;
        return _Transaction(
          id: d.id,
          type: m['type'] as String? ?? 'DEBIT',
          amount: (m['amount'] as num?)?.toDouble() ?? 0,
          description: m['description'] as String? ?? '',
          createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _transactions = docs;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAction(String action) async {
    final numAmount = double.tryParse(_amountCtrl.text);
    if (numAmount == null || numAmount <= 0) {
      showAppAlert(context, 'يرجى إدخال مبلغ صحيح');
      return;
    }
    if (action == 'WITHDRAW' && numAmount > widget.user.wallet.balance) {
      showAppAlert(context, 'المبلغ المطلوب أكبر من رصيدك الحالي');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await db.collection('payment_requests').add({
        'userId': widget.user.id,
        'userName': widget.user.name,
        'userPhone': widget.user.phone,
        'type': action,
        'amount': numAmount,
        'status': 'PENDING',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      final whatsappMsg = action == 'TOPUP'
          ? 'طلب شحن محفظة وصلها: $numAmount ج.م\nالاسم: ${widget.user.name}'
          : 'طلب سحب أرباح من وصلها: $numAmount ج.م\nالاسم: ${widget.user.name}';

      final url = Uri.parse(
          'https://wa.me/$_cashNumber?text=${Uri.encodeComponent(whatsappMsg)}');
      await launchUrl(url, mode: LaunchMode.externalApplication);

      setState(() {
        _showTopUp = false;
        _showWithdraw = false;
        _amountCtrl.clear();
      });
      if (mounted) showAppAlert(context, 'تم إرسال طلبك بنجاح، سيتم تنفيذه بعد المراجعة.');
    } catch (e) {
      if (mounted) showAppAlert(context, 'حدث خطأ أثناء إرسال الطلب');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                          Text('محفظتي الرقمية',
                              style: T.s(24, T.w900, C.slate900,
                                  letterSpacing: -0.5)),
                          const SizedBox(height: 2),
                          Text('رصيدك الحالي، شحن فودافون كاش، وسجل المعاملات',
                              style: T.s(11, T.w500, C.slate500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _balanceCard(),
                  if (_showTopUp || _showWithdraw) ...[
                    const SizedBox(height: 24),
                    _actionCard(),
                  ],
                  const SizedBox(height: 24),
                  _transactionsCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.slate950, C.slate900, C.emerald950],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.slate800),
        boxShadow: Sh.xl(),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              top: -20, right: -20,
              child: Blob(size: 288, color: C.emerald500.withOpacity(0.15))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(LucideIcons.wallet,
                      size: 24, color: Color(0xCC34D399)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: C.emerald950.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: C.emerald500.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('الرصيد المتاح للاستخدام',
                            style: T.s(11, T.w700, C.emerald400)),
                        const SizedBox(width: 6),
                        const PingDot(size: 6, color: C.emerald400),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('جنيه مصري',
                      style: T.s(16, T.w800, C.emerald400)),
                  const SizedBox(width: 8),
                  Text(widget.user.wallet.balance.toStringAsFixed(1),
                      style: T.s(44, T.w900, C.white, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 4),
              Text('يمكنك استخدام رصيدك لدفع المشاوير والطلبات بدون كاش',
                  style: T.s(11, T.w500, C.slate400)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PressScale(
                      onTap: () => setState(() {
                        _showTopUp = true;
                        _showWithdraw = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [C.emerald600, C.emerald700]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: Sh.md(color: C.emerald600.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.plusCircle,
                                size: 16, color: C.white),
                            const SizedBox(width: 8),
                            Text('شحن رصيد كاش',
                                style: T.s(11, T.w900, C.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PressScale(
                      onTap: () => setState(() {
                        _showWithdraw = true;
                        _showTopUp = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: C.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.banknote,
                                size: 16, color: C.white),
                            const SizedBox(width: 8),
                            Text('سحب أرباح',
                                style: T.s(11, T.w900, C.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.emerald500.withOpacity(0.3)),
        boxShadow: Sh.xl(),
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
                    Text(_showTopUp ? 'شحن المحفظة فورياً' : 'طلب سحب رصيد',
                        style: T.s(16, T.w900, C.slate900)),
                    const SizedBox(height: 2),
                    Text('عبر محفظة فودافون كاش أو المقر المعتمد',
                        style: T.s(11, T.w500, C.slate500)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _showTopUp ? C.emerald600 : C.amber500,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                    _showTopUp ? LucideIcons.plusCircle : LucideIcons.banknote,
                    size: 24,
                    color: C.white),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: Text('المبلغ المطلوب (ج.م)',
                style: T.s(11, T.w700, C.slate600)),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.slate200.withOpacity(0.8)),
            ),
            child: TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              textAlign: TextAlign.center,
              style: T.s(30, T.w900, C.slate900),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: T.s(30, T.w900, C.gray400),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          if (_showTopUp) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.emerald50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.emerald200.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PressScale(
                    scale: 0.9,
                    onTap: () async {
                      await Clipboard.setData(
                          const ClipboardData(text: _cashNumber));
                      if (mounted) showAppAlert(context, 'تم نسخ الرقم بنجاح');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: Sh.sm(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.copy,
                              size: 16, color: C.emerald700),
                          const SizedBox(width: 6),
                          Text('نسخ الرقم',
                              style: T.s(11, T.w700, C.emerald700)),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('رقم فودافون كاش الرسمي للإدارة',
                          style: T.s(11, T.w700, C.emerald800)),
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(_cashNumber,
                            style: T.s(18, T.w900, C.slate900,
                                letterSpacing: 1.2)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: PressScale(
                  onTap: _isSubmitting
                      ? null
                      : () => _handleAction(_showTopUp ? 'TOPUP' : 'WITHDRAW'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _showTopUp
                          ? const LinearGradient(
                              colors: [C.emerald600, C.emerald700])
                          : null,
                      color: _showTopUp ? null : C.slate900,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: Sh.md(
                          color: _showTopUp
                              ? C.emerald600.withOpacity(0.25)
                              : null),
                    ),
                    child: _isSubmitting
                        ? const Spinner()
                        : Text('تأكيد وإرسال الطلب',
                            style: T.s(14, T.w900, C.white)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _showTopUp = false;
                    _showWithdraw = false;
                    _amountCtrl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.slate100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('إلغاء',
                        style: T.s(14, T.w700, C.slate600)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transactionsCard() {
    return Container(
      padding: const EdgeInsets.all(28),
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: C.slate100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('تحديث فوري',
                    style: T.s(11, T.w700, C.slate400)),
              ),
              Row(
                children: [
                  Text('سجل المعاملات المالية',
                      style: T.s(15, T.w800, C.slate900)),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.history,
                      size: 20, color: C.emerald600),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Spinner(color: C.emerald600)),
            )
          else if (_transactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                    color: C.slate200.withOpacity(0.7), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('لا توجد معاملات مسجلة في محفظتك حتى الآن',
                  textAlign: TextAlign.center,
                  style: T.s(12, T.w700, C.slate400)),
            )
          else
            for (final t in _transactions) _transactionRow(t),
        ],
      ),
    );
  }

  Widget _transactionRow(_Transaction t) {
    final isCredit = t.type == 'CREDIT';
    final date = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
    final dateStr = intl.DateFormat('d MMM', 'ar').format(date);
    final timeStr = intl.DateFormat('hh:mm a', 'ar').format(date);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.slate50.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.slate100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Text(
                    '${isCredit ? "+" : "-"}${t.amount.toStringAsFixed(1)}',
                    style: T.s(16, T.w900,
                        isCredit ? C.emerald600 : C.rose600)),
                const SizedBox(width: 4),
                Text('ج.م', style: T.s(10, T.w700, C.slate400)),
              ],
            ),
          ),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(t.description,
                      style: T.s(13, T.w800, C.slate800)),
                  const SizedBox(height: 2),
                  Text('$dateStr • $timeStr',
                      style: T.s(10, T.w700, C.slate400)),
                ],
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCredit ? C.emerald100 : C.rose100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                    isCredit
                        ? LucideIcons.arrowDownRight
                        : LucideIcons.arrowUpLeft,
                    size: 16,
                    color: isCredit ? C.emerald700 : C.rose600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
