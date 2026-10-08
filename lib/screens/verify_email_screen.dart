import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/form_fields.dart';

/// هل المستخدم ده لازم يأكد بريده قبل دخول التطبيق؟
/// - الحسابات في verificationExemptEmails مستثناة.
/// - حسابات جوجل بريدها متأكد تلقائياً (emailVerified = true).
bool needsEmailVerification(fb.User? u) {
  if (u == null || u.emailVerified) return false;
  final usesPassword = u.providerData.any((p) => p.providerId == 'password');
  if (!usesPassword) return false;
  return !isExemptEmail(u.email);
}

/// شاشة تأكيد البريد الإلكتروني: بتبعت رابط تفعيل، وبتتابع الحالة تلقائياً
/// (كل 4 ثواني + أول ما المستخدم يرجع من تطبيق الإيميل).
class VerifyEmailScreen extends StatefulWidget {
  final VoidCallback onVerified;
  final Future<void> Function() onLogout;
  const VerifyEmailScreen(
      {super.key, required this.onVerified, required this.onLogout});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  static const _cooldownSeconds = 60;

  Timer? _poll;
  Timer? _tick;
  int _cooldown = _cooldownSeconds;
  bool _sending = false;
  bool _checking = false;
  bool _busyDelete = false;
  String? _msg;
  bool _msgIsError = false;

  String get _email => auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // أول رابط بيتبعت من شاشة التسجيل/الدخول، فنبدأ بعدّاد إعادة الإرسال
    _startCooldown();
    _poll = Timer.periodic(
        const Duration(seconds: 4), (_) => _checkVerified(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkVerified(silent: true);
  }

  void _startCooldown() {
    _tick?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  void _setMsg(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = text;
      _msgIsError = error;
    });
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking) return;
    final u = auth.currentUser;
    if (u == null) return;
    _checking = true;
    if (!silent && mounted) setState(() => _msg = null);
    try {
      await u.reload();
      final fresh = auth.currentUser;
      if (fresh != null && fresh.emailVerified) {
        // تجديد الـ token عشان قواعد Firestore تشوف email_verified = true
        await fresh.getIdToken(true);
        _poll?.cancel();
        if (mounted) widget.onVerified();
        return;
      }
      if (!silent) {
        _setMsg('لسه البريد متأكدش. افتح الرابط اللي وصلك وبعدين جرّب تاني.',
            error: true);
      }
    } on fb.FirebaseAuthException catch (e) {
      if (!silent) _setMsg(_errorText(e.code), error: true);
    } catch (e) {
      debugPrint('verify check failed: $e');
      if (!silent) _setMsg('تعذر التحقق الآن، تأكد من الإنترنت', error: true);
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    if (_sending || _cooldown > 0) return;
    final u = auth.currentUser;
    if (u == null) return;
    setState(() {
      _sending = true;
      _msg = null;
    });
    try {
      await u.sendEmailVerification();
      _setMsg('تم إرسال رابط التفعيل مرة تانية إلى $_email');
      _startCooldown();
    } on fb.FirebaseAuthException catch (e) {
      _setMsg(_errorText(e.code), error: true);
    } catch (e) {
      debugPrint('resend verification failed: $e');
      _setMsg('تعذر إرسال الرابط، حاول مرة أخرى', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _errorText(String code) {
    switch (code) {
      case 'too-many-requests':
        return 'محاولات كتير، استنى شوية وحاول تاني';
      case 'network-request-failed':
        return 'تأكد من الاتصال بالإنترنت وحاول مرة أخرى';
      case 'user-token-expired':
      case 'user-not-found':
        return 'انتهت الجلسة، سجّل الدخول من جديد';
      default:
        return 'حدث خطأ ($code)، حاول مرة أخرى';
    }
  }

  /// البريد اللي اتكتب غلط: نمسح الحساب غير المؤكد عشان يسجّل من جديد.
  Future<void> _deleteAndRestart() async {
    if (_busyDelete) return;
    final u = auth.currentUser;
    if (u == null) return;
    setState(() {
      _busyDelete = true;
      _msg = null;
    });
    try {
      try {
        await db.collection('users').doc(u.uid).delete();
      } catch (e) {
        // لو القواعد مش بتسمح بالمسح، مش مشكلة: هنكمل مسح حساب الدخول
        debugPrint('delete user doc skipped: $e');
      }
      await u.delete();
      await widget.onLogout();
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _setMsg(
            'سجّل الخروج ثم ادخل تاني وبعدين جرّب، أو تواصل مع الإدارة لتصحيح البريد',
            error: true);
      } else {
        _setMsg(_errorText(e.code), error: true);
      }
    } catch (e) {
      debugPrint('delete unverified account failed: $e');
      _setMsg('تعذر حذف الحساب، حاول مرة أخرى', error: true);
    } finally {
      if (mounted) setState(() => _busyDelete = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('البريد غلط؟', style: T.s(16, T.w900, C.slate900)),
          content: Text(
              'هنمسح الحساب ده (غير المؤكد) وترجع لشاشة التسجيل تعمل حساب جديد بالبريد الصحيح.',
              style: T.s(12, T.w700, C.slate500)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مسح وإعادة التسجيل')),
          ],
        ),
      ),
    );
    if (ok == true) await _deleteAndRestart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.slate50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: C.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: C.slate200),
                  boxShadow: Sh.lg(),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                            color: C.emerald50, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.mail,
                            size: 34, color: C.emerald600),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('أكّد بريدك الإلكتروني',
                        textAlign: TextAlign.center,
                        style: T.s(22, T.w900, C.slate900, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    Text('بعتنا رابط تفعيل على',
                        textAlign: TextAlign.center,
                        style: T.s(12, T.w700, C.slate400, height: 1.625)),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(_email,
                          textAlign: TextAlign.center,
                          style: T.s(13, T.w900, C.emerald600, height: 1.625)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        'افتح الرابط من الإيميل وهندخلك التطبيق تلقائياً. لو مش لاقيه شوف فولدر الـ Spam.',
                        textAlign: TextAlign.center,
                        style: T.s(11, T.w700, C.slate400, height: 1.7)),
                    if (_msg != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _msgIsError ? C.rose50 : C.emerald50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _msgIsError ? C.rose200 : C.emerald200),
                        ),
                        child: Text(_msg!,
                            textAlign: TextAlign.center,
                            style: T.s(11, T.w800,
                                _msgIsError ? C.rose500 : C.emerald700)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      onTap: _checking ? null : () => _checkVerified(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.shieldCheck,
                              size: 20, color: C.white),
                          const SizedBox(width: 8),
                          Text('أكدت بريدي', style: T.s(16, T.w900, C.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: (_cooldown > 0 || _sending)
                          ? Text(
                              _sending
                                  ? 'جارٍ الإرسال...'
                                  : 'إعادة الإرسال خلال $_cooldown ثانية',
                              style: T.s(12, T.w700, C.slate400))
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _resend,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text('إعادة إرسال رابط التفعيل',
                                    style: T.s(12, T.w900, C.emerald600)),
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busyDelete ? null : _confirmDelete,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('البريد غلط؟ امسح الحساب وسجّل من جديد',
                            textAlign: TextAlign.center,
                            style: T.s(11, T.w800, C.slate500)),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onLogout(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('تسجيل الخروج',
                            textAlign: TextAlign.center,
                            style: T.s(12, T.w900, C.slate400)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
