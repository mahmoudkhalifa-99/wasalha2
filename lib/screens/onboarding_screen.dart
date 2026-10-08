import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

/// شاشة التعريف بتظهر مرة واحدة بس بعد أول تثبيت للتطبيق.
class OnboardingPrefs {
  static const _key = 'onboarding_seen_v1';

  static Future<bool> seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) == true;
    } catch (_) {
      // لو التخزين فشل، ما نزعجش المستخدم بالشاشة في كل مرة
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }
}

class _Slide {
  final String title;
  final String body;
  final String badge;
  final Widget Function(BuildContext) icon;
  final List<Color> colors;
  const _Slide(this.title, this.body, this.badge, this.icon, this.colors);
}

/// نسخة Flutter من مكون Onboarding في Login.tsx
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  late final List<_Slide> _slides = [
    _Slide(
      'أهلاً بك في تطبيق وصلها',
      'المنظومة الذكية الأولى لخدمة كافة مراكز وقرى محافظة المنوفية، مشاويرك وطلباتك وأكلك بين إيديك بثواني.',
      'تغطية شاملة لكل القرى والمراكز',
      (ctx) {
        final s = isMd(ctx) ? 128.0 : 112.0;
        return Container(
          width: s,
          height: s,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [...Sh.xxl(), Sh.ring(C.white.withOpacity(0.3))],
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/images/icon-512.png',
                fit: BoxFit.contain),
          ),
        );
      },
      const [C.emerald800, C.emerald700, C.teal900],
    ),
    _Slide(
      'توكتوك • سيارة • دليفري فوري',
      'اختر وسيلة التوصيل الأنسب لمشوارك: توكتوك سريع في الشوارع، عربية مريحة، أو موتوسيكل لتوصيل طلبات المطاعم والصيدليات.',
      'أسطول نقل متكامل',
      (ctx) => GlassBox(
        sigma: 12,
        color: C.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.white.withOpacity(0.25)),
        shadows: Sh.xxl(),
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('🛺', style: TextStyle(fontSize: 36, height: 1.1)),
            SizedBox(width: 12),
            Text('🚗', style: TextStyle(fontSize: 36, height: 1.1)),
            SizedBox(width: 12),
            Text('🏍️', style: TextStyle(fontSize: 36, height: 1.1)),
          ],
        ),
      ),
      const [C.slate950, C.slate900, C.emerald950],
    ),
    _Slide(
      'كباتن ثقة، تتبع مباشر وأسعار عادلة',
      'كل رحلة مؤمنة وتتبع لحظي على الخريطة مع تسعيرة عادلة معلنة مسبقاً ودعم فني وخدمة عملاء مباشرة.',
      'أمان وثقة 100%',
      (ctx) => GlassBox(
        sigma: 12,
        color: C.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.white.withOpacity(0.25)),
        shadows: Sh.xxl(),
        padding: const EdgeInsets.all(20),
        child: const Icon(LucideIcons.shieldCheck, size: 64, color: C.emerald300),
      ),
      const [C.emerald950, C.teal900, C.slate950],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final md = isMd(context);
    final slide = _slides[_step];
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: slide.colors[1],
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: slide.colors,
          ),
        ),
        child: Stack(
          children: [
            // Ambient circles
            Positioned(
                top: 40, right: 40,
                child: Blob(size: 288, color: C.white.withOpacity(0.05))),
            Positioned(
                bottom: 80, left: 40,
                child: Blob(size: 288, color: C.emerald400.withOpacity(0.10))),

            Column(
              children: [
                // Top skip button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      md ? 32 : 24, top + (md ? 32 : 24), md ? 32 : 24, md ? 32 : 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassBox(
                        sigma: 12,
                        color: C.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Text(
                          slide.badge,
                          style: T.s(10, T.w900, C.emerald300,
                              letterSpacing: 1.0),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onComplete,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Text('تخطي',
                              style: T.s(12, T.w700, C.white.withOpacity(0.7))),
                        ),
                      ),
                    ],
                  ),
                ),

                // Center content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(md ? 40 : 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassBox(
                            sigma: 40,
                            color: C.white.withOpacity(0.10),
                            borderRadius:
                                BorderRadius.circular(md ? 56 : 44),
                            border: Border.all(color: C.white.withOpacity(0.20)),
                            shadows: Sh.xxl(),
                            padding: EdgeInsets.all(md ? 48 : 32),
                            child: slide.icon(context),
                          ),
                          SizedBox(height: md ? 32 : 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 384),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slide.title,
                                  textAlign: TextAlign.center,
                                  style: T.s(md ? 36 : 24, T.w900, C.white,
                                      height: 1.25,
                                      letterSpacing: md ? -0.9 : -0.6),
                                ),
                                SizedBox(height: md ? 16 : 12),
                                Text(
                                  slide.body,
                                  textAlign: TextAlign.center,
                                  style: T.s(md ? 14 : 12, T.w600,
                                      C.white.withOpacity(0.8),
                                      height: 1.625),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom controls
                Container(
                  padding: EdgeInsets.fromLTRB(md ? 40 : 24, md ? 40 : 24,
                      md ? 40 : 24, (md ? 64 : 48) + bottom),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x66000000), Color(0x00000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _slides.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                  left: i == _slides.length - 1 ? 0 : 8),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: 8,
                                width: i == _step ? 40 : 8,
                                decoration: BoxDecoration(
                                  color: i == _step
                                      ? C.emerald400
                                      : C.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 384),
                        child: Row(
                          children: [
                            if (_step > 0) ...[
                              PressScale(
                                onTap: () => setState(() => _step--),
                                child: GlassBox(
                                  sigma: 12,
                                  color: C.white.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(16),
                                  padding: const EdgeInsets.all(16),
                                  child: const Icon(LucideIcons.arrowRight,
                                      size: 20, color: C.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: PressScale(
                                onTap: () {
                                  if (_step < _slides.length - 1) {
                                    setState(() => _step++);
                                  } else {
                                    widget.onComplete();
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      vertical: md ? 20 : 16),
                                  decoration: BoxDecoration(
                                    color: C.emerald500,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: Sh.xl(
                                        color:
                                            C.emerald950.withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _step == _slides.length - 1
                                            ? 'ابدأ تجربة وصلها الآن'
                                            : 'التالي',
                                        style: T.s(16, T.w900, C.white),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(LucideIcons.chevronLeft,
                                          size: 20, color: C.white),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
