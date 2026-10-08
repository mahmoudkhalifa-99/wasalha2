import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/account_deletion.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// نافذة تأكيد حذف الحساب. لو الحذف نجح، AppShell بيرجّع المستخدم لشاشة الدخول
/// لوحده (لأن حساب الدخول اتمسح).
Future<void> showDeleteAccountDialog(BuildContext context, AppUser user) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeleteAccountDialog(user: user),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  final AppUser user;
  const _DeleteAccountDialog({required this.user});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String _errorText(Object e) {
    if (e is fb.FirebaseAuthException) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return 'كلمة المرور غلط';
        case 'too-many-requests':
          return 'محاولات كتير، استنى شوية وحاول تاني';
        case 'network-request-failed':
          return 'تأكد من الاتصال بالإنترنت وحاول مرة أخرى';
        case 'requires-recent-login':
          return 'لأسباب أمنية سجّل الخروج وادخل تاني وبعدين جرّب الحذف';
        case 'user-mismatch':
          return 'اخترت حساب جوجل مختلف عن حسابك، اختار نفس الحساب';
        case 'admin-not-deletable':
          return e.message ?? 'الحساب ده ما ينفعش يتحذف';
        default:
          return 'تعذّر حذف الحساب (${e.code})، حاول مرة أخرى';
      }
    }
    return 'تعذّر حذف الحساب، حاول مرة أخرى';
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (AccountDeletion.usesPassword && _password.text.isEmpty) {
      setState(() => _error = 'اكتب كلمة المرور لتأكيد الحذف');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await AccountDeletion.hasActiveOrders(widget.user)) {
        if (mounted) {
          setState(() => _error =
              'عندك طلب شغال لسه ماخلصش. استنى لما يتسلّم أو يتلغي وبعدين احذف حسابك.');
        }
        return;
      }
      await AccountDeletion.delete(widget.user, password: _password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (isGoogleSignInCancelled(e)) return; // لغى بنفسه، ولا رسالة
      debugPrint('delete account failed: $e');
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.user.role == UserRole.driver;
    final balance = widget.user.wallet.balance;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('حذف الحساب نهائياً', style: T.s(20, T.w900, C.rose600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'هيتم حذف حسابك وبياناتك الشخصية (الاسم، الهاتف، البريد، الصورة${isDriver ? '، والموقع' : ''}) ومش هتقدر ترجعه تاني.',
                  style: T.s(13, T.w600, C.slate700)),
              const SizedBox(height: 8),
              Text(
                  'سجلات الطلبات والمعاملات القديمة بتتحفظ كسجل للتشغيل وما بتظهرش باسمك.${isDriver ? ' ومستندات توثيق الكابتن بتتحفظ حسب السياسة القانونية.' : ''}',
                  style: T.s(11, T.w500, C.slate500)),
              if (balance > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: C.amber50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      'تنبيه: رصيد محفظتك (${balance.toStringAsFixed(2)} ج.م) هيتلغي مع الحساب. تواصل مع الإدارة قبل الحذف لو ليك مستحقات.',
                      style: T.s(11, T.w700, C.amber500)),
                ),
              ],
              const SizedBox(height: 14),
              if (AccountDeletion.usesPassword)
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور للتأكيد',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                )
              else
                Text('هنطلب منك تأكيد الحذف بحساب جوجل بتاعك.',
                    style: T.s(11, T.w700, C.slate500)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: T.s(12, T.w700, C.rose600)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: T.s(14, T.w700, C.slate700)),
          ),
          TextButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('حذف حسابي نهائياً',
                    style: T.s(14, T.w800, C.rose600)),
          ),
        ],
      ),
    );
  }
}
