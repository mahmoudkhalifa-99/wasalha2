import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/verification/domain/verification_enums.dart';
import 'package:wasalha/features/verification/models/captain_verification.dart';

void main() {
  test('وثيقة فاضية: NOT_STARTED وبوابة مقفولة', () {
    final v = CaptainVerification.fromMap({}, 'c1');
    expect(v.status, VerificationStatus.notStarted);
    expect(v.gate.canReceive, isFalse);
    expect(v.pendingDocs, isEmpty);
    expect(v.checks.ocr, CheckResult.unavailable);
    expect(v.checks.liveness, LivenessStatus.unableToVerify);
  });

  test('حالة غير معروفة ترجع NOT_STARTED (مش VERIFIED)', () {
    expect(VerificationStatus.parse('???'), VerificationStatus.notStarted);
    expect(VerificationStatus.parse(null), VerificationStatus.notStarted);
  });

  test('قراءة المستندات والإقرار والبوابة', () {
    final v = CaptainVerification.fromMap({
      'status': 'VERIFIED',
      'fullName': 'محمد أحمد',
      'activeDocs': {
        'drivingLicense': {
          'type': 'drivingLicense',
          'version': 2,
          'path': 'captain_docs/c1/drivingLicense/v2.jpg',
          'sha256': 'x',
          'capturedAt': 5,
          'expiresAt': 1900000000000,
          'status': 'ACTIVE',
        },
        'broken': {'path': 1}, // مستند تالف يتجاهل
      },
      'gate': {'canReceive': true, 'validUntil': 1900000000000, 'reasons': []},
      'serverFlags': ['DUPLICATE_NID'],
    }, 'c1');
    expect(v.activeDocs.keys, [DocType.drivingLicense]);
    expect(v.activeDocs[DocType.drivingLicense]!.version, 2);
    expect(v.activeDocs[DocType.drivingLicense]!.expiryDate, isNotNull);
    expect(v.gate.canReceive, isTrue);
    expect(v.gate.validUntil, 1900000000000);
    expect(v.serverFlags, ['DUPLICATE_NID']);
  });

  test('DocVersion: toMap ثم fromMap', () {
    const d = DocVersion(
      type: DocType.idFront,
      version: 3,
      path: 'captain_docs/c/idFront/v3.jpg',
      sha256: 'abc',
      capturedAt: 10,
      quality: {'result': 'PASS'},
    );
    final back = DocVersion.fromMap(d.toMap())!;
    expect(back.type, DocType.idFront);
    expect(back.version, 3);
    expect(back.path, d.path);
    expect(back.quality['result'], 'PASS');
  });

  test('مراجعة: تقرأ السبب والمراجع والمستندات المطلوب تصحيحها', () {
    final r = ReviewInfo.fromMap({
      'decision': 'NEEDS_CORRECTION',
      'reason': 'الصورة غير واضحة',
      'reviewerId': 'admin1',
      'reviewedAt': 7,
      'correctionDocs': ['idFront'],
    })!;
    expect(r.reason, 'الصورة غير واضحة');
    expect(r.correctionDocs, ['idFront']);
    expect(ReviewInfo.fromMap(null), isNull);
  });
}
