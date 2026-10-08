import 'package:flutter/material.dart';

import '../../../models/models.dart' show AppUser;
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../data/verification_repository.dart';
import '../domain/document_requirements.dart';
import '../domain/verification_enums.dart';
import '../domain/verification_rules.dart';
import '../models/captain_verification.dart';
import 'captain_verification_screen.dart';

final VerificationRepository _repo = VerificationRepository();

/// رسالة حجب للواجهة لو الكابتن مش مسموح له يستقبل طلبات، وإلا null.
/// ده للرسالة فقط: المنع الفعلي في firestore.rules (بوابة gate).
Future<String?> verificationBlockMessage(String uid) async {
  try {
    final cfg = await _repo.watchConfig().first;
    if (!cfg.enforced) return null;
    final v = await _repo.watch(uid).first;
    if (gateOpen(v, DateTime.now())) return null;
    final reasons = v?.gate.reasons ?? const [];
    if (v == null || v.status != VerificationStatus.verified) {
      return 'لازم توثّق حسابك أولًا عشان تقدر تقدّم عروض وتستقبل طلبات.';
    }
    return 'استقبال الطلبات متوقف: ${[for (final r in reasons) kGateReasonLabels[r] ?? r].join('، ')}.';
  } catch (_) {
    return null; // مفيش قراءة = ما نمنعش من الواجهة؛ القواعد هي اللي بتقرر
  }
}

/// الكباتن اللي اتعرضتلهم شاشة التوثيق تلقائيًا في الجلسة دي (مرة لكل حساب،
/// عشان ميتفتحش تاني كل ما الشاشة تتبني من جديد).
final Set<String> _autoPrompted = <String>{};

/// بيفتح شاشة التوثيق أول ما الكابتن يدخل حسابه لو التوثيق لسه ناقص
/// (ما بدأش / ناقص / محتاج تصحيح / منتهي). لو قيد المراجعة أو موثّق أو
/// مرفوض أو معلّق مفيش حاجة بتتفتح. الكابتن يقدر يرجع منها عادي.
Future<void> promptVerificationIfNeeded(BuildContext context, AppUser user) async {
  if (!_autoPrompted.add(user.id)) return;
  try {
    final v = await _repo.watch(user.id).first.timeout(const Duration(seconds: 8));
    final status = v?.status ?? VerificationStatus.notStarted;
    const needs = {
      VerificationStatus.notStarted,
      VerificationStatus.incomplete,
      VerificationStatus.needsCorrection,
      VerificationStatus.expired,
    };
    if (!needs.contains(status)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CaptainVerificationScreen(user: user)),
    );
  } catch (_) {
    // فشل القراءة: نسمح بمحاولة تانية في المرة الجاية بدل ما نعلّم إنه اتعرض.
    _autoPrompted.remove(user.id);
  }
}

/// شريط حالة التوثيق في شاشة الكابتن. بيختفي لو كل شيء سليم.
class VerificationBanner extends StatelessWidget {
  final AppUser user;
  const VerificationBanner({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VerificationConfig>(
      stream: _repo.watchConfig(),
      builder: (context, cfgSnap) {
        final enforced = cfgSnap.data?.enforced ?? false;
        return StreamBuilder<CaptainVerification?>(
          stream: _repo.watch(user.id),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const SizedBox.shrink();
            }
            final v = snap.data;
            final now = DateTime.now();
            final status = v?.status ?? VerificationStatus.notStarted;
            String? msg;
            var urgent = false;

            switch (status) {
              case VerificationStatus.notStarted:
              case VerificationStatus.incomplete:
                msg = enforced
                    ? 'لازم توثّق حسابك عشان تستقبل طلبات.'
                    : 'وثّق حسابك لتأمين حقوقك (هيبقى إلزامي قريبًا).';
                urgent = enforced;
              case VerificationStatus.pendingReview:
                msg = 'طلب التوثيق قيد المراجعة.';
              case VerificationStatus.needsCorrection:
                msg = 'طلب التوثيق يحتاج تصحيح: ${v?.review?.reason ?? ''}';
                urgent = true;
              case VerificationStatus.rejected:
                msg = 'تم رفض طلب التوثيق.';
                urgent = true;
              case VerificationStatus.suspended:
                msg = 'حسابك معلّق عن استقبال الطلبات.';
                urgent = true;
              case VerificationStatus.expired:
                msg = 'انتهت صلاحية مستند. جدّده عشان ترجع تستقبل طلبات.';
                urgent = true;
              case VerificationStatus.verified:
                final soon = _soonestExpiry(v!, now);
                if (soon != null) {
                  msg = soon <= kExpiringUrgentDays
                      ? 'تنبيه عاجل: مستند بينتهي بعد $soon يوم. جدّده الآن.'
                      : 'مستند بينتهي بعد $soon يوم. جدّده قريبًا.';
                  urgent = soon <= kExpiringUrgentDays;
                } else if (enforced && !gateOpen(v, now)) {
                  msg = 'استقبال الطلبات متوقف: ${[for (final r in v.gate.reasons) kGateReasonLabels[r] ?? r].join('، ')}';
                  urgent = true;
                }
            }
            if (msg == null) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CaptainVerificationScreen(user: user)),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: urgent ? C.rose50 : C.amber50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(urgent ? Icons.gpp_bad_outlined : Icons.verified_user_outlined,
                          color: urgent ? C.rose500 : C.amber500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(msg,
                            style: T.s(13, T.w900, urgent ? C.rose500 : C.slate800, height: 1.5)),
                      ),
                      const Icon(Icons.chevron_left),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// أقل عدد أيام متبقية لمستند معتمد بيقرب ينتهي (أقل من 30 يوم)، أو null.
  int? _soonestExpiry(CaptainVerification v, DateTime now) {
    int? best;
    for (final d in v.activeDocs.values) {
      final e = d.expiryDate;
      if (e == null) continue;
      final days = daysUntilExpiry(e, now);
      if (days < kExpiringSoonDays && days >= 0 && (best == null || days < best)) best = days;
    }
    return best;
  }
}
