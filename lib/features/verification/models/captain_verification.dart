import '../../../models/models.dart' show toMillis;
import '../domain/declaration.dart';
import '../domain/verification_enums.dart';

/// نسخة مستند. النسخ القديمة بتفضل محفوظة (v1, v2, ...) والمعتمدة الحالية ACTIVE.
class DocVersion {
  final DocType type;
  final int version;
  final String path; // مسار Storage (خاص). مفيش روابط عامة.
  final String sha256;
  final int capturedAt;
  final int? expiresAt; // millis، للمستندات اللي لها انتهاء
  final String? number; // رقم الرخصة/اللوحة
  final Map<String, dynamic> quality;
  final String status; // PENDING / ACTIVE / SUPERSEDED / REJECTED

  const DocVersion({
    required this.type,
    required this.version,
    required this.path,
    required this.sha256,
    required this.capturedAt,
    this.expiresAt,
    this.number,
    this.quality = const {},
    this.status = 'PENDING',
  });

  DateTime? get expiryDate =>
      expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt!);

  static DocVersion? fromMap(Object? o, [String? typeKey]) {
    if (o is! Map) return null;
    final t = DocType.tryParse((o['type'] as String?) ?? typeKey);
    final path = o['path'];
    if (t == null || path is! String) return null;
    return DocVersion(
      type: t,
      version: (o['version'] as num?)?.toInt() ?? 1,
      path: path,
      sha256: (o['sha256'] as String?) ?? '',
      capturedAt: toMillis(o['capturedAt']) ?? 0,
      expiresAt: toMillis(o['expiresAt']),
      number: o['number'] as String?,
      quality: o['quality'] is Map
          ? Map<String, dynamic>.from(o['quality'] as Map)
          : const {},
      status: (o['status'] as String?) ?? 'PENDING',
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'version': version,
        'path': path,
        'sha256': sha256,
        'capturedAt': capturedAt,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (number != null) 'number': number,
        'quality': quality,
        'status': status,
      };
}

/// مؤشرات الفحص الآلي. كلها مساعدة للمراجعة البشرية، ومحسوبة عند الكابتن
/// (استشارية فقط، القرار الوحيد هو مراجعة الأدمن).
class VerificationChecks {
  final CheckResult quality;
  final CheckResult ocr;
  final CheckResult dataMatch;
  final DocumentRisk documentRisk;
  final bool selfieCaptured;
  final FaceMatchStatus faceMatch;
  final LivenessStatus liveness;
  final List<String> flags;

  const VerificationChecks({
    this.quality = CheckResult.unavailable,
    this.ocr = CheckResult.unavailable,
    this.dataMatch = CheckResult.unavailable,
    this.documentRisk = DocumentRisk.unableToDetermine,
    this.selfieCaptured = false,
    this.faceMatch = FaceMatchStatus.unavailable,
    this.liveness = LivenessStatus.unableToVerify,
    this.flags = const [],
  });

  static VerificationChecks fromMap(Object? m) {
    if (m is! Map) return const VerificationChecks();
    return VerificationChecks(
      quality: CheckResult.parse(m['quality'] as String?),
      ocr: CheckResult.parse(m['ocr'] as String?),
      dataMatch: CheckResult.parse(m['dataMatch'] as String?),
      documentRisk: DocumentRisk.parse(m['documentRisk'] as String?),
      selfieCaptured: m['selfieCaptured'] == true,
      faceMatch: FaceMatchStatus.parse(m['faceMatch'] as String?),
      liveness: LivenessStatus.parse(m['liveness'] as String?),
      flags: [for (final f in (m['flags'] as List? ?? const [])) f.toString()],
    );
  }

  Map<String, dynamic> toMap() => {
        'quality': quality.value,
        'ocr': ocr.value,
        'dataMatch': dataMatch.value,
        'documentRisk': documentRisk.value,
        'selfieCaptured': selfieCaptured,
        'faceMatch': faceMatch.value,
        'liveness': liveness.value,
        'flags': flags,
      };
}

class ReviewInfo {
  final String decision;
  final String reason;
  final String reviewerId;
  final int reviewedAt;
  final List<String> correctionDocs;

  /// بنود الفحص اللي المراجع أكدها وقت الاعتماد (review_checklist.dart).
  final List<String> checklist;

  const ReviewInfo({
    required this.decision,
    required this.reason,
    required this.reviewerId,
    required this.reviewedAt,
    this.correctionDocs = const [],
    this.checklist = const [],
  });

  static ReviewInfo? fromMap(Object? m) {
    if (m is! Map) return null;
    return ReviewInfo(
      decision: (m['decision'] as String?) ?? '',
      reason: (m['reason'] as String?) ?? '',
      reviewerId: (m['reviewerId'] as String?) ?? '',
      reviewedAt: toMillis(m['reviewedAt']) ?? 0,
      correctionDocs: [
        for (final d in (m['correctionDocs'] as List? ?? const [])) d.toString()
      ],
      checklist: [
        for (final d in (m['checklist'] as List? ?? const [])) d.toString()
      ],
    );
  }

  Map<String, dynamic> toMap() => {
        'decision': decision,
        'reason': reason,
        'reviewerId': reviewerId,
        'reviewedAt': reviewedAt,
        'correctionDocs': correctionDocs,
        if (checklist.isNotEmpty) 'checklist': checklist,
      };
}

/// البوابة المحسوبة في السيرفر (Cloud Function). الكلاينت ما يكتبهاش.
class GateInfo {
  final bool canReceive;
  final int? validUntil; // millis
  final List<String> reasons;
  const GateInfo({this.canReceive = false, this.validUntil, this.reasons = const []});

  static GateInfo fromMap(Object? m) {
    if (m is! Map) return const GateInfo();
    return GateInfo(
      canReceive: m['canReceive'] == true,
      validUntil: toMillis(m['validUntil']),
      reasons: [for (final r in (m['reasons'] as List? ?? const [])) r.toString()],
    );
  }
}

class CaptainVerification {
  final String captainId;
  final VerificationStatus status;
  final String fullName;
  final String nationalId;
  final String licenseNumber;
  final String plateNumber;
  final DeclarationAcceptance? declaration;
  final Map<DocType, DocVersion> pendingDocs; // اللي رفعه الكابتن (آخر نسخة)
  final Map<DocType, DocVersion> activeDocs; // اللي اعتمده الأدمن
  final VerificationChecks checks;
  final ReviewInfo? review;
  final bool renewalPending;
  final GateInfo gate;
  final List<String> serverFlags;
  final int createdAt;
  final int updatedAt;
  final int? submittedAt;

  const CaptainVerification({
    required this.captainId,
    this.status = VerificationStatus.notStarted,
    this.fullName = '',
    this.nationalId = '',
    this.licenseNumber = '',
    this.plateNumber = '',
    this.declaration,
    this.pendingDocs = const {},
    this.activeDocs = const {},
    this.checks = const VerificationChecks(),
    this.review,
    this.renewalPending = false,
    this.gate = const GateInfo(),
    this.serverFlags = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
    this.submittedAt,
  });

  static Map<DocType, DocVersion> _docs(Object? m) {
    final out = <DocType, DocVersion>{};
    if (m is Map) {
      m.forEach((k, v) {
        final d = DocVersion.fromMap(v, k.toString());
        if (d != null) out[d.type] = d;
      });
    }
    return out;
  }

  factory CaptainVerification.fromMap(Map<String, dynamic> m, String id) =>
      CaptainVerification(
        captainId: id,
        status: VerificationStatus.parse(m['status'] as String?),
        fullName: (m['fullName'] as String?) ?? '',
        nationalId: (m['nationalId'] as String?) ?? '',
        licenseNumber: (m['licenseNumber'] as String?) ?? '',
        plateNumber: (m['plateNumber'] as String?) ?? '',
        declaration: DeclarationAcceptance.fromMap(m['declaration']),
        pendingDocs: _docs(m['pendingDocs']),
        activeDocs: _docs(m['activeDocs']),
        checks: VerificationChecks.fromMap(m['checks']),
        review: ReviewInfo.fromMap(m['review']),
        renewalPending: m['renewalPending'] == true,
        gate: GateInfo.fromMap(m['gate']),
        serverFlags: [for (final f in (m['serverFlags'] as List? ?? const [])) f.toString()],
        createdAt: toMillis(m['createdAt']) ?? 0,
        updatedAt: toMillis(m['updatedAt']) ?? 0,
        submittedAt: toMillis(m['submittedAt']),
      );

  /// المستند اللي بيتعرض: المعتمد لو فيه، وإلا آخر مرفوع.
  DocVersion? currentDoc(DocType t) => pendingDocs[t] ?? activeDocs[t];

  static Map<String, dynamic> docsToMap(Map<DocType, DocVersion> docs) =>
      {for (final e in docs.entries) e.key.value: e.value.toMap()};
}

/// حدث في سجل المراجعة.
class AuditEvent {
  final String id;
  final String captainId;
  final String action;
  final String performedBy;
  final int timestamp;
  final String? oldStatus;
  final String? newStatus;
  final String? reason;

  const AuditEvent({
    required this.id,
    required this.captainId,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.oldStatus,
    this.newStatus,
    this.reason,
  });

  factory AuditEvent.fromMap(Map<String, dynamic> m, String id) => AuditEvent(
        id: id,
        captainId: (m['captainId'] as String?) ?? '',
        action: (m['action'] as String?) ?? '',
        performedBy: (m['performedBy'] as String?) ?? '',
        timestamp: toMillis(m['timestamp']) ?? 0,
        oldStatus: m['oldStatus'] as String?,
        newStatus: m['newStatus'] as String?,
        reason: m['reason'] as String?,
      );
}
