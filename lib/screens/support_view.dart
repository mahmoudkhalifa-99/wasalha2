import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';

/// نسخة Flutter من pages/SupportView.tsx
class SupportView extends StatefulWidget {
  final AppUser user;
  final VoidCallback onBack;
  const SupportView({super.key, required this.user, required this.onBack});

  @override
  State<SupportView> createState() => _SupportViewState();
}

class _SupportViewState extends State<SupportView> {
  int _rating = 5;
  final _opinionCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _opinionCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmitFeedback() async {
    if (_opinionCtrl.text.trim().isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await db.collection('feedback').add({
        'userId': widget.user.id,
        'userName': widget.user.name,
        'userPhone': widget.user.phone,
        'rating': _rating,
        'opinion': _opinionCtrl.text,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      setState(() {
        _submitted = true;
        _opinionCtrl.clear();
      });
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في الإرسال');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: C.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: C.slate100),
                            boxShadow: Sh.sm(),
                          ),
                          child: const Icon(LucideIcons.chevronRight,
                              size: 20, color: C.slate700),
                        ),
                      ),
                      Text('صوتك مسموع',
                          style: T.s(30, T.w900, C.slate900,
                              letterSpacing: -0.6)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _contactCard(),
                  const SizedBox(height: 32),
                  _feedbackCard(),
                  const SizedBox(height: 32),
                  Opacity(
                    opacity: 0.3,
                    child: Column(
                      children: [
                        const Icon(LucideIcons.bike,
                            size: 80, color: C.slate900),
                        const SizedBox(height: 16),
                        Text('وصـــلــهــا',
                            style: T.s(10, T.w900, C.slate900,
                                letterSpacing: 8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: C.brandPrimary,
        borderRadius: BorderRadius.circular(64),
        boxShadow: Sh.xxl(),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              top: 0, right: 0,
              child: Blob(size: 192, color: C.white.withOpacity(0.10))),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: C.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(color: C.white.withOpacity(0.2)),
                ),
                child: const Icon(LucideIcons.messageSquare,
                    size: 40, color: C.white),
              ),
              const SizedBox(height: 24),
              Text('تواصل مباشر مع الإدارة',
                  textAlign: TextAlign.center,
                  style: T.s(24, T.w900, C.white, height: 1.2)),
              const SizedBox(height: 12),
              Text('فريقنا متاح لمساعدتك وحل أي مشكلة تواجهك فوراً.',
                  textAlign: TextAlign.center,
                  style: T.s(12, T.w700, C.emerald50.withOpacity(0.8),
                      height: 1.6)),
              const SizedBox(height: 16),
              PressScale(
                onTap: () => launchUrl(Uri.parse('https://wa.me/201065019364'),
                    mode: LaunchMode.externalApplication),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: Sh.xl(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.externalLink,
                          size: 20, color: C.brandPrimary),
                      const SizedBox(width: 12),
                      Text('واتساب الدعم الفني',
                          style: T.s(14, T.w900, C.brandPrimary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feedbackCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(64),
        border: Border.all(color: C.slate50),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.amber50,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: const Icon(LucideIcons.sparkles,
                    size: 40, color: C.amber500),
              ),
              const SizedBox(height: 12),
              Text('رأيك يهمنا لنطور "وصـــلــهــا"',
                  textAlign: TextAlign.center,
                  style: T.s(20, T.w900, C.slate800)),
              const SizedBox(height: 12),
              Text('كل تعليق ترسله يصل مباشرة للمسؤولين لنتمكن من خدمتكم بشكل أفضل.',
                  textAlign: TextAlign.center,
                  style: T.s(12, T.w700, C.slate400, height: 1.6)),
            ],
          ),
          const SizedBox(height: 40),
          if (_submitted)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: C.emerald50,
                borderRadius: BorderRadius.circular(56),
                border: Border.all(color: C.emerald100, width: 2),
              ),
              child: Column(
                children: [
                  const Icon(LucideIcons.heart,
                      size: 64, color: C.emerald500),
                  const SizedBox(height: 24),
                  Text('شكراً لرسالتك الصادقة!',
                      style: T.s(20, T.w900, C.emerald700)),
                  const SizedBox(height: 12),
                  Text('تم استلام رأيك بنجاح، وسيكون الدافع لنا للتطوير الدائم.',
                      textAlign: TextAlign.center,
                      style: T.s(12, T.w700, C.emerald600, height: 1.6)),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () => setState(() => _submitted = false),
                    child: Text('إرسال تعليق آخر',
                        style: T.s(10, T.w900, C.emerald500,
                            letterSpacing: 1.2)),
                  ),
                ],
              ),
            )
          else ...[
            Text('تقييمك لتجربة التطبيق',
                textAlign: TextAlign.center,
                style: T.s(10, T.w900, C.slate400, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: C.slate50,
                borderRadius: BorderRadius.circular(48),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var s = 1; s <= 5; s++)
                    GestureDetector(
                      onTap: () => setState(() => _rating = s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedScale(
                          scale: _rating >= s ? 1.25 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Opacity(
                            opacity: _rating >= s ? 1 : 0.2,
                            child: Icon(LucideIcons.star,
                                size: 40,
                                color: _rating >= s
                                    ? C.amber400
                                    : C.slate300),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text('اكتب ملاحظاتك أو اقتراحاتك',
                style: T.s(10, T.w900, C.slate400, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(minHeight: 180),
              decoration: BoxDecoration(
                color: C.slate50,
                borderRadius: BorderRadius.circular(48),
              ),
              child: TextField(
                controller: _opinionCtrl,
                maxLines: null,
                minLines: 6,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: T.s(13, T.w700, C.slate800),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      'هل لديك فكرة تطوير؟ أو مشكلة واجهتك؟ اكتبها هنا بكل صراحة...',
                  hintStyle: T.s(13, T.w700, C.gray400),
                  contentPadding: const EdgeInsets.all(40),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 40),
            PressScale(
              onTap: (_isSubmitting || _opinionCtrl.text.trim().isEmpty)
                  ? null
                  : _handleSubmitFeedback,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.slate950,
                  borderRadius: BorderRadius.circular(48),
                  boxShadow: Sh.xxl(),
                ),
                child: _isSubmitting
                    ? const Spinner(size: 32)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.send,
                              size: 24, color: Color(0xFF34D399)),
                          const SizedBox(width: 16),
                          Text('إرسال رسالتك الآن',
                              style: T.s(18, T.w900, C.white)),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
