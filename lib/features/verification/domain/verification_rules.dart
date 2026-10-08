import '../../../models/models.dart' show UserStatus, VehicleType;
import '../models/captain_verification.dart';
import 'document_requirements.dart';
import 'national_id.dart';
import 'verification_enums.dart';

// ═════════════ انتقالات الحالة ═════════════

enum Actor { captain, admin, system }

/// الانتقالات المسموحة لكل جهة. لازم تطابق firestore.rules و functions/verification.js.
const Map<Actor, Map<VerificationStatus, Set<VerificationStatus>>> kTransitions = {
  Actor.captain: {
    VerificationStatus.notStarted: {VerificationStatus.incomplete},
    VerificationStatus.incomplete: {VerificationStatus.pendingReview},
    VerificationStatus.needsCorrection: {
      VerificationStatus.incomplete,
      VerificationStatus.pendingReview
    },
    VerificationStatus.expired: {VerificationStatus.pendingReview},
  },
  Actor.admin: {
    VerificationStatus.pendingReview: {
      VerificationStatus.verified,
      VerificationStatus.needsCorrection,
      VerificationStatus.rejected
    },
    VerificationStatus.verified: {
      VerificationStatus.suspended,
      VerificationStatus.expired
    },
    VerificationStatus.suspended: {VerificationStatus.verified},
    VerificationStatus.rejected: {VerificationStatus.needsCorrection},
  },
  Actor.system: {
    VerificationStatus.verified: {VerificationStatus.expired},
  },
};

bool canTransition(VerificationStatus from, VerificationStatus to, Actor by) =>
    from == to || (kTransitions[by]?[from]?.contains(to) ?? false);

/// النزول لـ NEEDS_CORRECTION/REJECT/SUSPEND لازم بسبب مكتوب.
bool transitionNeedsReason(VerificationStatus to) =>
    to == VerificationStatus.needsCorrection ||
    to == VerificationStatus.rejected ||
    to == VerificationStatus.suspended;

// ═════════════ canReceiveOrders ═════════════

/// أسباب الحجب (أكواد ثابتة، بتتعرض للكابتن والأدمن).
class GateReason {
  GateReason._();
  static const emailNotVerified = 'EMAIL_NOT_VERIFIED';
  static const notVerified = 'NOT_VERIFIED';
  static const accountSuspended = 'ACCOUNT_SUSPENDED';
  static const missingDocument = 'MISSING_DOCUMENT';
  static const documentExpired = 'DOCUMENT_EXPIRED';
  static const missingDeclaration = 'MISSING_DECLARATION';
  static const duplicateIdentity = 'DUPLICATE_IDENTITY';
}

const Map<String, String> kGateReasonLabels = {
  GateReason.emailNotVerified: 'البريد الإلكتروني غير مؤكد',
  GateReason.notVerified: 'الحساب غير موثّق بعد',
  GateReason.accountSuspended: 'الحساب معلّق',
  GateReason.missingDocument: 'مستند مطلوب ناقص',
  GateReason.documentExpired: 'مستند منتهي الصلاحية',
  GateReason.missingDeclaration: 'الإقرار الإلكتروني غير مسجّل',
  GateReason.duplicateIdentity: 'بيانات مكررة تحتاج مراجعة',
};

/// أكواد serverFlags اللي بتمنع الاستقبال.
const Set<String> kBlockingServerFlags = {
  'DUPLICATE_NID',
  'DUPLICATE_PHONE',
  'DUPLICATE_LICENSE',
  'DUPLICATE_PLATE',
};

class GateResult {
  final bool canReceive;
  final List<String> reasons;
  const GateResult(this.canReceive, this.reasons);
}

/// الشرط الكامل لاستقبال الطلبات. مش بيعتمد على VERIFIED لوحده:
/// emailVerified AND VERIFIED AND الحساب نشط AND كل المستندات المطلوبة معتمدة وغير منتهية
/// AND مش معلّق AND مفيش تكرار. (نسخة السيرفر في functions/verification.js ونفس المنطق.)
GateResult evaluateGate({
  required bool emailVerified,
  required VerificationStatus verificationStatus,
  required UserStatus accountStatus,
  required VehicleType? vehicleType,
  required Map<DocType, DocVersion> activeDocs,
  required bool declarationAccepted,
  List<String> serverFlags = const [],
  required DateTime now,
}) {
  final reasons = <String>[];
  if (!emailVerified) reasons.add(GateReason.emailNotVerified);
  if (accountStatus != UserStatus.approved ||
      verificationStatus == VerificationStatus.suspended) {
    reasons.add(GateReason.accountSuspended);
  }
  if (verificationStatus != VerificationStatus.verified) {
    reasons.add(GateReason.notVerified);
  }
  for (final req in requiredDocuments(vehicleType)) {
    final d = activeDocs[req.type];
    if (d == null) {
      reasons.add(GateReason.missingDocument);
      continue;
    }
    if (req.hasExpiry) {
      final exp = d.expiryDate;
      if (exp == null) {
        reasons.add(GateReason.missingDocument);
      } else if (expiryStatus(exp, now) == ExpiryStatus.expired) {
        reasons.add(GateReason.documentExpired);
      }
    }
  }
  if (!declarationAccepted) reasons.add(GateReason.missingDeclaration);
  if (serverFlags.any(kBlockingServerFlags.contains)) {
    reasons.add(GateReason.duplicateIdentity);
  }
  final unique = reasons.toSet().toList();
  return GateResult(unique.isEmpty, unique);
}

bool canReceiveOrders({
  required bool emailVerified,
  required VerificationStatus verificationStatus,
  required UserStatus accountStatus,
  required VehicleType? vehicleType,
  required Map<DocType, DocVersion> activeDocs,
  required bool declarationAccepted,
  List<String> serverFlags = const [],
  required DateTime now,
}) =>
    evaluateGate(
      emailVerified: emailVerified,
      verificationStatus: verificationStatus,
      accountStatus: accountStatus,
      vehicleType: vehicleType,
      activeDocs: activeDocs,
      declarationAccepted: declarationAccepted,
      serverFlags: serverFlags,
      now: now,
    ).canReceive;

// ═════════════ جاهزية الإرسال ═════════════

/// الأخطاء اللي بتمنع إرسال الطلب للمراجعة (قائمة فاضية = جاهز).
List<String> submissionBlockers({
  required VehicleType? vehicleType,
  required String nationalId,
  required String fullName,
  required String licenseNumber,
  required String plateNumber,
  required Map<DocType, DocVersion> docs,
  required bool declarationAccepted,
  required DateTime now,
}) {
  final out = <String>[];
  if (fullName.trim().length < 6) out.add('الاسم الرباعي مطلوب');
  final info = parseNationalId(nationalId, now: now);
  if (info == null) {
    out.add('الرقم القومي غير صحيح');
  } else if (ageOn(info.birthDate, now) < 18) {
    out.add('العمر أقل من 18 سنة');
  }
  if (vehicleNeedsLicenseData(vehicleType)) {
    if (licenseNumber.trim().length < 5) out.add('رقم رخصة القيادة مطلوب');
    if (plateNumber.trim().length < 3) out.add('رقم اللوحة مطلوب');
  }
  for (final req in requiredDocuments(vehicleType)) {
    final d = docs[req.type];
    if (d == null) {
      out.add('مستند مطلوب: ${req.type.value}');
    } else if (d.quality['result'] == 'FAIL') {
      out.add('جودة الصورة غير مقبولة: ${req.type.value}');
    } else if (req.hasExpiry) {
      final exp = d.expiryDate;
      if (exp == null) {
        out.add('تاريخ انتهاء مطلوب: ${req.type.value}');
      } else if (expiryStatus(exp, now) == ExpiryStatus.expired) {
        out.add('مستند منتهي: ${req.type.value}');
      }
    }
  }
  if (!declarationAccepted) out.add('الموافقة على الإقرار مطلوبة');
  return out;
}

// ═════════════ مطابقة البيانات (OCR) ═════════════

/// بيانات مستخرجة من البطاقة (لو أي OCR اتوفر مستقبلًا). مش متاح حاليًا:
/// NOT AVAILABLE WITH CURRENT DEPENDENCIES.
class OcrIdData {
  final String? name;
  final String? nationalId;
  final DateTime? birthDate;
  const OcrIdData({this.name, this.nationalId, this.birthDate});
}

class DataMatchResult {
  final CheckResult result;
  final List<String> flags;
  const DataMatchResult(this.result, this.flags);
}

/// مقارنة بيانات الحساب ببيانات OCR. أي اختلاف = DATA_MISMATCH كعلامة للمراجع،
/// ومبيترفضش تلقائيًا (OCR بيغلط). لو OCR مش متاح: UNAVAILABLE.
DataMatchResult compareIdentity({
  required String accountName,
  required String enteredNationalId,
  OcrIdData? ocr,
}) {
  if (ocr == null) return const DataMatchResult(CheckResult.unavailable, []);
  final flags = <String>[];
  if (ocr.name != null &&
      normalizeArabicName(ocr.name!) != normalizeArabicName(accountName)) {
    flags.add('DATA_MISMATCH_NAME');
  }
  if (ocr.nationalId != null &&
      normalizeDigits(ocr.nationalId!) != normalizeDigits(enteredNationalId)) {
    flags.add('DATA_MISMATCH_NID');
  }
  final entered = parseNationalId(enteredNationalId);
  if (ocr.birthDate != null && entered != null) {
    final a = ocr.birthDate!;
    final b = entered.birthDate;
    if (a.year != b.year || a.month != b.month || a.day != b.day) {
      flags.add('DATA_MISMATCH_BIRTHDATE');
    }
  }
  return DataMatchResult(flags.isEmpty ? CheckResult.pass : CheckResult.warn, flags);
}

// ═════════════ ملخص المخاطر ═════════════

/// ملخص مؤشرات للمراجع. مفيش Score رقمي لأن المؤشرات المتاحة مش كفاية تبنيه.
/// القرار النهائي دايمًا: ADMIN REVIEW (مش AI VERIFIED).
class RiskSummary {
  final CheckResult documentQuality;
  final CheckResult ocr;
  final CheckResult dataMatch;
  final DocumentRisk documentRisk;
  final bool selfieCaptured;
  final FaceMatchStatus faceMatch;
  final LivenessStatus liveness;
  final List<String> flags;
  final String finalDecision;

  const RiskSummary({
    required this.documentQuality,
    required this.ocr,
    required this.dataMatch,
    required this.documentRisk,
    required this.selfieCaptured,
    required this.faceMatch,
    required this.liveness,
    required this.flags,
    this.finalDecision = 'ADMIN REVIEW',
  });
}

/// تجميع نتائج جودة الصور (الأسوأ) لكل المستندات.
CheckResult worstQuality(Iterable<Map<String, dynamic>> reports) {
  var worst = CheckResult.pass;
  var any = false;
  for (final r in reports) {
    any = true;
    final res = CheckResult.parse(r['result'] as String?);
    if (res == CheckResult.fail) return CheckResult.fail;
    if (res == CheckResult.warn) worst = CheckResult.warn;
  }
  return any ? worst : CheckResult.unavailable;
}

/// مؤشر خطر المستند مبني على مؤشرات حقيقية بس (جودة وشكل الصورة وتكرار صورة بين حسابات).
/// ما بيطلعش LOW_RISK أبدًا لأن مفيش فحص تلاعب موثوق متاح: أفضل نتيجة UNABLE_TO_DETERMINE.
DocumentRisk assessDocumentRisk({
  required Iterable<Map<String, dynamic>> qualityReports,
  List<String> serverFlags = const [],
}) {
  if (serverFlags.contains('DUPLICATE_IMAGE')) return DocumentRisk.highRisk;
  final reports = qualityReports.toList();
  if (reports.isEmpty) return DocumentRisk.unableToDetermine;
  final warnings = <String>{};
  for (final r in reports) {
    for (final w in (r['warnings'] as List? ?? const [])) {
      warnings.add(w.toString());
    }
  }
  const strong = {'ASPECT_OFF', 'GLARE_BORDERLINE', 'BLUR_BORDERLINE'};
  if (warnings.any(strong.contains)) return DocumentRisk.mediumRisk;
  return DocumentRisk.unableToDetermine;
}

RiskSummary buildRiskSummary(
  VerificationChecks c, {
  List<String> serverFlags = const [],
}) =>
    RiskSummary(
      documentQuality: c.quality,
      ocr: c.ocr,
      dataMatch: c.dataMatch,
      documentRisk: serverFlags.contains('DUPLICATE_IMAGE')
          ? DocumentRisk.highRisk
          : c.documentRisk,
      selfieCaptured: c.selfieCaptured,
      faceMatch: c.faceMatch,
      liveness: c.liveness,
      flags: [...c.flags, ...serverFlags],
    );

// ═════════════ حساب مؤشرات الفحص ═════════════

/// بيحسب مؤشرات الفحص الاستشارية من المستندات الحالية. OCR وFace Match وLiveness
/// مش متاحين بالـ dependencies الحالية، فبيتسجّلوا UNAVAILABLE / UNABLE_TO_VERIFY
/// وبيتحوّلوا للمراجعة البشرية (من غير أي فحص وهمي).
VerificationChecks computeChecks({
  required Map<DocType, DocVersion> docs,
  required String fullName,
  required String nationalId,
}) {
  final reports = [for (final d in docs.values) d.quality];
  final dataMatch = compareIdentity(accountName: fullName, enteredNationalId: nationalId);
  final flags = <String>{
    'OCR_UNAVAILABLE',
    'FACE_MATCH_UNAVAILABLE',
    'LIVENESS_UNAVAILABLE',
    for (final r in reports)
      for (final w in (r['warnings'] as List? ?? const [])) w.toString(),
    ...dataMatch.flags,
  };
  return VerificationChecks(
    quality: worstQuality(reports),
    ocr: CheckResult.unavailable,
    dataMatch: dataMatch.result,
    documentRisk: assessDocumentRisk(qualityReports: reports),
    selfieCaptured: docs.containsKey(DocType.selfieWithId),
    faceMatch: FaceMatchStatus.unavailable,
    liveness: LivenessStatus.unableToVerify,
    flags: flags.toList()..sort(),
  );
}

// ═════════════ حالة البوابة عند الكلاينت (للعرض والرسائل فقط) ═════════════

/// هل البوابة مفتوحة حسب آخر حساب من السيرفر؟ ده للواجهة بس. الحماية الحقيقية في القواعد.
bool gateOpen(CaptainVerification? v, DateTime now) =>
    v != null &&
    v.status == VerificationStatus.verified &&
    v.gate.canReceive &&
    (v.gate.validUntil == null || v.gate.validUntil! > now.millisecondsSinceEpoch);

// ═════════════ نسخ المستندات ═════════════

/// رقم النسخة الجديدة لمستند: أعلى نسخة موجودة (مرفوعة أو معتمدة) + 1. النسخ القديمة بتفضل.
int nextDocVersion(CaptainVerification? v, DocType t) {
  final p = v?.pendingDocs[t]?.version ?? 0;
  final a = v?.activeDocs[t]?.version ?? 0;
  return (p > a ? p : a) + 1;
}

class MergeResult {
  final Map<DocType, DocVersion> active;
  final List<DocVersion> activated; // النسخ اللي بقت ACTIVE
  final List<DocVersion> superseded; // النسخ المعتمدة قبل كده واتبدّلت (بتفضل محفوظة)
  const MergeResult(this.active, this.activated, this.superseded);
}

/// اعتماد المرفوعات: الجديدة تبقى ACTIVE والمعتمدة القديمة SUPERSEDED (من غير حذف).
MergeResult mergeApprovedDocs(
  Map<DocType, DocVersion> active,
  Map<DocType, DocVersion> pending,
) {
  final merged = {...active};
  final activated = <DocVersion>[];
  final superseded = <DocVersion>[];
  for (final e in pending.entries) {
    final old = active[e.key];
    if (old != null && old.version != e.value.version) superseded.add(old);
    final a = DocVersion(
      type: e.value.type,
      version: e.value.version,
      path: e.value.path,
      sha256: e.value.sha256,
      capturedAt: e.value.capturedAt,
      expiresAt: e.value.expiresAt,
      number: e.value.number,
      quality: e.value.quality,
      status: 'ACTIVE',
    );
    merged[e.key] = a;
    activated.add(a);
  }
  return MergeResult(merged, activated, superseded);
}
