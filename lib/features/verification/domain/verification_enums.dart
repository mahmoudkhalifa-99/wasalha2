/// حالات توثيق الكابتن. emailVerified شيء منفصل تمامًا عن VERIFIED.
enum VerificationStatus {
  notStarted('NOT_STARTED'),
  incomplete('INCOMPLETE'),
  pendingReview('PENDING_REVIEW'),
  needsCorrection('NEEDS_CORRECTION'),
  verified('VERIFIED'),
  rejected('REJECTED'),
  suspended('SUSPENDED'),
  expired('EXPIRED');

  final String value;
  const VerificationStatus(this.value);

  static VerificationStatus parse(String? s) => values.firstWhere(
      (e) => e.value == s,
      orElse: () => VerificationStatus.notStarted);
}

/// أنواع المستندات/الصور المحفوظة. القيمة = اسم المجلد في Storage ومفتاح الخريطة.
enum DocType {
  idFront('idFront'),
  idBack('idBack'),
  selfieWithId('selfieWithId'),
  poseRight('poseRight'),
  poseLeft('poseLeft'),
  drivingLicense('drivingLicense'),
  vehicleLicense('vehicleLicense'),
  vehiclePhoto('vehiclePhoto');

  final String value;
  const DocType(this.value);

  static DocType? tryParse(String? s) {
    for (final e in values) {
      if (e.value == s) return e;
    }
    return null;
  }
}

/// حالة صلاحية مستند له تاريخ انتهاء.
enum ExpiryStatus { valid, expiringSoon, expired }

/// مؤشر خطر المستند. مساعد للمراجعة البشرية وليس إثباتًا قانونيًا لأصالة المستند.
enum DocumentRisk {
  lowRisk('LOW_RISK'),
  mediumRisk('MEDIUM_RISK'),
  highRisk('HIGH_RISK'),
  unableToDetermine('UNABLE_TO_DETERMINE');

  final String value;
  const DocumentRisk(this.value);
  static DocumentRisk parse(String? s) => values.firstWhere((e) => e.value == s,
      orElse: () => DocumentRisk.unableToDetermine);
}

enum LivenessStatus {
  pass('PASS'),
  fail('FAIL'),
  unableToVerify('UNABLE_TO_VERIFY');

  final String value;
  const LivenessStatus(this.value);
  static LivenessStatus parse(String? s) => values.firstWhere(
      (e) => e.value == s,
      orElse: () => LivenessStatus.unableToVerify);
}

enum FaceMatchStatus {
  pass('FACE_MATCH_PASS'),
  review('FACE_MATCH_REVIEW'),
  fail('FACE_MATCH_FAIL'),
  unavailable('UNAVAILABLE');

  final String value;
  const FaceMatchStatus(this.value);
  static FaceMatchStatus parse(String? s) => values.firstWhere(
      (e) => e.value == s,
      orElse: () => FaceMatchStatus.unavailable);
}

/// نتيجة فحص بسيط (جودة / OCR / مطابقة بيانات).
enum CheckResult {
  pass('PASS'),
  warn('WARN'),
  fail('FAIL'),
  unavailable('UNAVAILABLE');

  final String value;
  const CheckResult(this.value);
  static CheckResult parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => CheckResult.unavailable);
}

enum ReviewDecision {
  approve('APPROVE'),
  needsCorrection('NEEDS_CORRECTION'),
  reject('REJECT'),
  suspend('SUSPEND'),
  reactivate('REACTIVATE');

  final String value;
  const ReviewDecision(this.value);
}

/// أحداث سجل المراجعة. (الكتابة من الكلاينت مقيّدة في القواعد، والباقي من الـ Function.)
class AuditAction {
  AuditAction._();
  static const documentUploaded = 'DOCUMENT_UPLOADED';
  static const documentReplaced = 'DOCUMENT_REPLACED';
  static const documentApproved = 'DOCUMENT_APPROVED';
  static const documentRejected = 'DOCUMENT_REJECTED';
  static const captainVerified = 'CAPTAIN_VERIFIED';
  static const captainSuspended = 'CAPTAIN_SUSPENDED';
  static const captainReactivated = 'CAPTAIN_REACTIVATED';
  static const documentExpired = 'DOCUMENT_EXPIRED';
  static const termsAccepted = 'TERMS_ACCEPTED';
  static const profileChanged = 'PROFILE_CHANGED';
  static const verificationReviewed = 'VERIFICATION_REVIEWED';
  static const submitted = 'VERIFICATION_SUBMITTED';

  /// اللي مسموح للكابتن يسجّلها بنفسه (لازم تطابق firestore.rules).
  static const captainWritable = [
    documentUploaded,
    documentReplaced,
    termsAccepted,
    profileChanged,
    submitted,
  ];
}
