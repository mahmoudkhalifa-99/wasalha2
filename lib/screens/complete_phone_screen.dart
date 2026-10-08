import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/form_fields.dart';

/// إجباري: لازم رقم موبايل مصري صحيح قبل استخدام التطبيق (حتى حسابات جوجل).
/// بعد الحفظ، AppShell بيستلم التحديث من Firestore ويفتح التطبيق تلقائياً.
class CompletePhoneScreen extends StatefulWidget {
  final String userId;
  final String name;
  final Future<void> Function() onLogout;
  const CompletePhoneScreen(
      {super.key,
      required this.userId,
      required this.name,
      required this.onLogout});

  @override
  State<CompletePhoneScreen> createState() => _CompletePhoneScreenState();
}

class _CompletePhoneScreenState extends State<CompletePhoneScreen> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final phone = _ctrl.text.trim();
    if (!isValidPhone(phone)) {
      setState(() => _error = 'رقم الهاتف غير صحيح (010, 011, 012, 015)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await db.collection('users').doc(widget.userId).update({'phone': phone});
    } catch (e) {
      debugPrint('save phone failed: $e');
      if (mounted) {
        setState(() => _error = 'تعذر حفظ الرقم، تأكد من الإنترنت وحاول تاني');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                        decoration: const BoxDecoration(
                            color: C.emerald50, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.phone,
                            size: 32, color: C.emerald600),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('أضف رقم هاتفك',
                        textAlign: TextAlign.center,
                        style: T.s(22, T.w900, C.slate900, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    Text(
                        'رقم الموبايل إجباري عشان الكباتن والعملاء يقدروا يتواصلوا معاك في الطلبات.',
                        textAlign: TextAlign.center,
                        style: T.s(12, T.w700, C.slate400, height: 1.7)),
                    const SizedBox(height: 18),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 11,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: T.s(16, T.w900, C.slate900),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '01xxxxxxxxx',
                          filled: true,
                          fillColor: C.slate50,
                          prefixIcon: const Icon(LucideIcons.phone,
                              size: 18, color: C.slate400),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: C.slate200),
                          ),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: T.s(11, T.w800, C.rose500)),
                    ],
                    const SizedBox(height: 18),
                    PrimaryButton(
                      onTap: _saving ? null : _save,
                      child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ والمتابعة',
                          style: T.s(16, T.w900, C.white)),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onLogout(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
