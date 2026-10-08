import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

/// شاشة الحساب المعطّل: المستخدم مش بيقدر يكمل، والإدارة هي اللي بترجّع تفعيله.
class SuspendedScreen extends StatelessWidget {
  final String name;
  final Future<void> Function() onLogout;
  const SuspendedScreen({super.key, required this.name, required this.onLogout});

  Future<void> _contactDeveloper() async {
    final msg = Uri.encodeComponent(
        'السلام عليكم، حسابي في تطبيق وصلها (${name.isEmpty ? 'مستخدم' : name}) اتعطّل وأحتاج المساعدة.');
    await launchUrl(Uri.parse('https://wa.me/$developerWhatsApp?text=$msg'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.slate50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(28),
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
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                            color: C.rose50, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.shieldAlert,
                            size: 36, color: C.rose500),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('تم تعطيل حسابك',
                        textAlign: TextAlign.center,
                        style: T.s(24, T.w900, C.slate900, letterSpacing: -0.5)),
                    const SizedBox(height: 10),
                    Text(
                        'لا يمكنك استخدام التطبيق بهذا الحساب حالياً. استرجاع الحساب بيتم عن طريق الإدارة.',
                        textAlign: TextAlign.center,
                        style: T.s(12, T.w700, C.slate500, height: 1.7)),
                    const SizedBox(height: 22),
                    PressScale(
                      onTap: _contactDeveloper,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('تواصل مع الإدارة عبر واتساب',
                            style: T.s(14, T.w900, C.white)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onLogout(),
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
