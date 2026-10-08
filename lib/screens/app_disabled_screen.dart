import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../services/app_status_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

/// شاشة التطبيق المتوقف: بتظهر لكل المستخدمين ما عدا السوبر أدمن.
class AppDisabledScreen extends StatelessWidget {
  final String message;
  final bool signedIn;
  final Future<void> Function() onLogout;
  final VoidCallback onAdminLogin;
  const AppDisabledScreen({
    super.key,
    required this.message,
    required this.signedIn,
    required this.onLogout,
    required this.onAdminLogin,
  });

  Future<void> _contact() async {
    final msg = Uri.encodeComponent('السلام عليكم، عندي استفسار عن تطبيق وصلها.');
    await launchUrl(Uri.parse('https://wa.me/$developerWhatsApp?text=$msg'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final text = message.isEmpty ? AppStatus.defaultMessage : message;
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
                            color: C.amber50, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.wrench,
                            size: 36, color: C.amber500),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('التطبيق متوقف مؤقتاً',
                        textAlign: TextAlign.center,
                        style: T.s(24, T.w900, C.slate900, letterSpacing: -0.5)),
                    const SizedBox(height: 10),
                    Text(text,
                        textAlign: TextAlign.center,
                        style: T.s(13, T.w500, C.slate500)),
                    const SizedBox(height: 22),
                    PressScale(
                      onTap: _contact,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.emerald600,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('تواصل معنا',
                            style: T.s(14, T.w700, C.white)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (signedIn)
                      PressScale(
                        onTap: onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.slate100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('تسجيل الخروج',
                              style: T.s(14, T.w700, C.slate700)),
                        ),
                      )
                    else
                      // باب للسوبر أدمن عشان يقدر يدخل ويشغّل التطبيق تاني
                      GestureDetector(
                        onTap: onAdminLogin,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text('دخول الإدارة',
                              textAlign: TextAlign.center,
                              style: T.s(11, T.w700, C.slate400)),
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
