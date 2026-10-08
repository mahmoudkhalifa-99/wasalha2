import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/verification/domain/declaration.dart';
import 'package:wasalha/features/verification/domain/verification_enums.dart';
import 'package:wasalha/features/verification/domain/verification_rules.dart';
import 'package:wasalha/features/verification/models/captain_verification.dart';
import 'package:wasalha/models/models.dart' show UserStatus, VehicleType;
import 'package:wasalha/config_constants.dart' show platformFeePerTrip;

final now = DateTime(2026, 10, 4, 12);

DocVersion _doc(DocType t, {int v = 1, DateTime? expires, Map<String, dynamic> quality = const {}}) => DocVersion(
      type: t,
      version: v,
      path: 'captain_docs/c/${t.value}/v$v.jpg',
      sha256: 'h$v',
      capturedAt: 1,
      expiresAt: expires?.millisecondsSinceEpoch,
      quality: quality,
    );

Map<DocType, DocVersion> _identity() => {
      for (final t in [DocType.idFront, DocType.idBack, DocType.selfieWithId, DocType.poseRight, DocType.poseLeft])
        t: _doc(t),
    };

Map<DocType, DocVersion> _carDocs({DateTime? license, DateTime? vehicle}) => {
      ..._identity(),
      DocType.drivingLicense: _doc(DocType.drivingLicense, expires: license ?? DateTime(2028, 1, 1)),
      DocType.vehicleLicense: _doc(DocType.vehicleLicense, expires: vehicle ?? DateTime(2028, 1, 1)),
      DocType.vehiclePhoto: _doc(DocType.vehiclePhoto),
    };

GateResult _gate({
  bool email = true,
  VerificationStatus status = VerificationStatus.verified,
  UserStatus account = UserStatus.approved,
  VehicleType? vehicle = VehicleType.toktok,
  Map<DocType, DocVersion>? docs,
  bool declaration = true,
  List<String> flags = const [],
}) =>
    evaluateGate(
      emailVerified: email,
      verificationStatus: status,
      accountStatus: account,
      vehicleType: vehicle,
      activeDocs: docs ?? _identity(),
      declarationAccepted: declaration,
      serverFlags: flags,
      now: now,
    );

void main() {
  group('انتقالات الحالة', () {
    test('الكابتن: بدء ← إرسال، وتصحيح ← إعادة إرسال', () {
      expect(canTransition(VerificationStatus.notStarted, VerificationStatus.incomplete, Actor.captain), isTrue);
      expect(canTransition(VerificationStatus.incomplete, VerificationStatus.pendingReview, Actor.captain), isTrue);
      expect(canTransition(VerificationStatus.needsCorrection, VerificationStatus.pendingReview, Actor.captain), isTrue);
      expect(canTransition(VerificationStatus.expired, VerificationStatus.pendingReview, Actor.captain), isTrue);
    });

    test('الكابتن لا يوثّق نفسه ولا يفك تعليقه أو رفضه', () {
      for (final from in VerificationStatus.values) {
        expect(canTransition(from, VerificationStatus.verified, Actor.captain), from == VerificationStatus.verified,
            reason: 'from ${from.value}');
      }
      expect(canTransition(VerificationStatus.suspended, VerificationStatus.pendingReview, Actor.captain), isFalse);
      expect(canTransition(VerificationStatus.rejected, VerificationStatus.pendingReview, Actor.captain), isFalse);
    });

    test('الأدمن: قرار المراجعة والتعليق وإعادة التفعيل', () {
      expect(canTransition(VerificationStatus.pendingReview, VerificationStatus.verified, Actor.admin), isTrue);
      expect(canTransition(VerificationStatus.pendingReview, VerificationStatus.rejected, Actor.admin), isTrue);
      expect(canTransition(VerificationStatus.pendingReview, VerificationStatus.needsCorrection, Actor.admin), isTrue);
      expect(canTransition(VerificationStatus.verified, VerificationStatus.suspended, Actor.admin), isTrue);
      expect(canTransition(VerificationStatus.suspended, VerificationStatus.verified, Actor.admin), isTrue);
      expect(canTransition(VerificationStatus.rejected, VerificationStatus.needsCorrection, Actor.admin), isTrue);
    });

    test('انتقالات ممنوعة على الجميع', () {
      for (final a in Actor.values) {
        expect(canTransition(VerificationStatus.incomplete, VerificationStatus.verified, a), isFalse);
        expect(canTransition(VerificationStatus.rejected, VerificationStatus.verified, a), isFalse);
        expect(canTransition(VerificationStatus.expired, VerificationStatus.verified, a), isFalse);
      }
    });

    test('النظام يقدر ينقل VERIFIED ← EXPIRED فقط', () {
      expect(canTransition(VerificationStatus.verified, VerificationStatus.expired, Actor.system), isTrue);
      expect(canTransition(VerificationStatus.verified, VerificationStatus.suspended, Actor.system), isFalse);
    });

    test('السبب مطلوب للتصحيح والرفض والتعليق فقط', () {
      expect(transitionNeedsReason(VerificationStatus.needsCorrection), isTrue);
      expect(transitionNeedsReason(VerificationStatus.rejected), isTrue);
      expect(transitionNeedsReason(VerificationStatus.suspended), isTrue);
      expect(transitionNeedsReason(VerificationStatus.verified), isFalse);
    });
  });

  group('canReceiveOrders', () {
    test('كابتن توكتوك موثّق بدون مستندات سيارة: مسموح', () {
      expect(_gate().canReceive, isTrue);
      expect(_gate().reasons, isEmpty);
    });

    test('VERIFIED لا يكفي لوحده: البريد غير مؤكد', () {
      final g = _gate(email: false);
      expect(g.canReceive, isFalse);
      expect(g.reasons, contains(GateReason.emailNotVerified));
    });

    test('غير موثّق / معلّق / حساب موقوف', () {
      expect(_gate(status: VerificationStatus.pendingReview).reasons, contains(GateReason.notVerified));
      expect(_gate(status: VerificationStatus.suspended).reasons, contains(GateReason.accountSuspended));
      expect(_gate(account: UserStatus.suspended).reasons, contains(GateReason.accountSuspended));
    });

    test('سيارة: تحتاج الرخصتين وصورة المركبة', () {
      expect(_gate(vehicle: VehicleType.car).canReceive, isFalse);
      expect(_gate(vehicle: VehicleType.car).reasons, contains(GateReason.missingDocument));
      expect(_gate(vehicle: VehicleType.car, docs: _carDocs()).canReceive, isTrue);
    });

    test('رخصة منتهية تمنع، ورخصة بتنتهي اليوم لسه صالحة', () {
      final expired = _gate(vehicle: VehicleType.car, docs: _carDocs(license: DateTime(2026, 10, 3)));
      expect(expired.canReceive, isFalse);
      expect(expired.reasons, contains(GateReason.documentExpired));
      final today = _gate(vehicle: VehicleType.car, docs: _carDocs(license: DateTime(2026, 10, 4)));
      expect(today.canReceive, isTrue);
    });

    test('رخصة مركبة منتهية تمنع أيضًا', () {
      final g = _gate(vehicle: VehicleType.car, docs: _carDocs(vehicle: DateTime(2026, 1, 1)));
      expect(g.reasons, contains(GateReason.documentExpired));
    });

    test('الإقرار والتكرار', () {
      expect(_gate(declaration: false).reasons, contains(GateReason.missingDeclaration));
      expect(_gate(flags: ['DUPLICATE_NID']).reasons, contains(GateReason.duplicateIdentity));
      // صورة مكررة علامة للمراجع مش حجب تلقائي
      expect(_gate(flags: ['DUPLICATE_IMAGE']).canReceive, isTrue);
    });

    test('canReceiveOrders بيعكس evaluateGate', () {
      expect(
          canReceiveOrders(
            emailVerified: true,
            verificationStatus: VerificationStatus.verified,
            accountStatus: UserStatus.approved,
            vehicleType: VehicleType.motorcycle,
            activeDocs: _identity(),
            declarationAccepted: true,
            now: now,
          ),
          isTrue);
    });
  });

  group('gateOpen (واجهة)', () {
    CaptainVerification v({bool can = true, int? until, VerificationStatus s = VerificationStatus.verified}) =>
        CaptainVerification(captainId: 'c', status: s, gate: GateInfo(canReceive: can, validUntil: until));

    test('مفتوحة فقط لو VERIFIED والسيرفر قال canReceive وما انتهتش', () {
      expect(gateOpen(v(), now), isTrue);
      expect(gateOpen(v(until: now.add(const Duration(days: 1)).millisecondsSinceEpoch), now), isTrue);
      expect(gateOpen(v(until: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch), now), isFalse);
      expect(gateOpen(v(can: false), now), isFalse);
      expect(gateOpen(v(s: VerificationStatus.suspended), now), isFalse);
      expect(gateOpen(null, now), isFalse);
    });
  });

  group('submissionBlockers', () {
    List<String> blockers({
      VehicleType? vehicle = VehicleType.toktok,
      String nid = '29001011234567',
      String name = 'محمد أحمد علي حسن',
      Map<DocType, DocVersion>? docs,
      bool decl = true,
      String license = '',
      String plate = '',
    }) =>
        submissionBlockers(
          vehicleType: vehicle,
          nationalId: nid,
          fullName: name,
          licenseNumber: license,
          plateNumber: plate,
          docs: docs ?? _identity(),
          declarationAccepted: decl,
          now: now,
        );

    test('كل شيء جاهز', () => expect(blockers(), isEmpty));

    test('الإقرار شرط للإرسال', () => expect(blockers(decl: false), isNotEmpty));

    test('الرقم القومي والعمر', () {
      expect(blockers(nid: '123'), contains('الرقم القومي غير صحيح'));
      expect(blockers(nid: '30901011234567'), contains('العمر أقل من 18 سنة'));
    });

    test('سيارة تطلب رقم الرخصة واللوحة والمستندات وتواريخ الانتهاء', () {
      final b = blockers(vehicle: VehicleType.car);
      expect(b, contains('رقم رخصة القيادة مطلوب'));
      expect(b, contains('رقم اللوحة مطلوب'));
      expect(b.where((x) => x.contains('drivingLicense')), isNotEmpty);
      final ok = blockers(vehicle: VehicleType.car, docs: _carDocs(), license: 'AB123456', plate: 'أ ب ج 123');
      expect(ok, isEmpty);
    });

    test('مستند منتهي يمنع الإرسال', () {
      final b = blockers(
          vehicle: VehicleType.car,
          docs: _carDocs(license: DateTime(2026, 1, 1)),
          license: 'AB123456',
          plate: 'أ ب ج 123');
      expect(b.any((x) => x.contains('مستند منتهي')), isTrue);
    });

    test('صورة جودتها FAIL ما تتقبلش', () {
      final docs = _identity()..[DocType.idFront] = _doc(DocType.idFront, quality: {'result': 'FAIL'});
      expect(blockers(docs: docs).any((x) => x.contains('جودة الصورة')), isTrue);
    });

  });

  group('مطابقة البيانات (OCR)', () {
    test('OCR غير متاح = UNAVAILABLE بدون علامات', () {
      final r = compareIdentity(accountName: 'محمد أحمد', enteredNationalId: '29001011234567');
      expect(r.result, CheckResult.unavailable);
      expect(r.flags, isEmpty);
    });

    test('تطابق (مع اختلاف التشكيل والهمزات)', () {
      final r = compareIdentity(
        accountName: 'أحمد محمد',
        enteredNationalId: '29001011234567',
        ocr: const OcrIdData(name: 'احمد مُحمد', nationalId: '٢٩٠٠١٠١١٢٣٤٥٦٧', birthDate: null),
      );
      expect(r.result, CheckResult.pass);
      expect(r.flags, isEmpty);
    });

    test('DATA_MISMATCH للاسم والرقم وتاريخ الميلاد (من غير رفض تلقائي)', () {
      final r = compareIdentity(
        accountName: 'أحمد محمد',
        enteredNationalId: '29001011234567',
        ocr: OcrIdData(name: 'سعيد علي', nationalId: '29001011234568', birthDate: DateTime(1991, 5, 5)),
      );
      expect(r.result, CheckResult.warn); // تنبيه للمراجع، مش FAIL
      expect(r.flags, containsAll(['DATA_MISMATCH_NAME', 'DATA_MISMATCH_NID', 'DATA_MISMATCH_BIRTHDATE']));
    });
  });

  group('مؤشرات المخاطر (Risk)', () {
    Map<String, dynamic> q(String result, [List<String> warnings = const []]) =>
        {'result': result, 'warnings': warnings};

    test('جودة: الأسوأ يغلب', () {
      expect(worstQuality([q('PASS'), q('WARN')]), CheckResult.warn);
      expect(worstQuality([q('PASS'), q('FAIL'), q('WARN')]), CheckResult.fail);
      expect(worstQuality([q('PASS')]), CheckResult.pass);
      expect(worstQuality(const []), CheckResult.unavailable);
    });

    test('مفيش LOW_RISK أبدًا: أفضل نتيجة UNABLE_TO_DETERMINE', () {
      expect(assessDocumentRisk(qualityReports: [q('PASS')]), DocumentRisk.unableToDetermine);
      expect(assessDocumentRisk(qualityReports: const []), DocumentRisk.unableToDetermine);
    });

    test('مؤشرات حقيقية ترفعها لمتوسط، وصورة مكررة بين حسابات = مرتفع', () {
      expect(assessDocumentRisk(qualityReports: [q('WARN', ['ASPECT_OFF'])]), DocumentRisk.mediumRisk);
      expect(assessDocumentRisk(qualityReports: [q('PASS')], serverFlags: ['DUPLICATE_IMAGE']), DocumentRisk.highRisk);
    });

    test('computeChecks: OCR/وجه/Liveness غير متاحة بصراحة، والقرار للإدارة', () {
      final c = computeChecks(
        docs: {..._identity(), DocType.idFront: _doc(DocType.idFront, quality: q('PASS'))},
        fullName: 'محمد أحمد علي',
        nationalId: '29001011234567',
      );
      expect(c.ocr, CheckResult.unavailable);
      expect(c.faceMatch, FaceMatchStatus.unavailable);
      expect(c.liveness, LivenessStatus.unableToVerify);
      expect(c.selfieCaptured, isTrue);
      expect(c.flags, containsAll(['OCR_UNAVAILABLE', 'FACE_MATCH_UNAVAILABLE', 'LIVENESS_UNAVAILABLE']));
      final r = buildRiskSummary(c);
      expect(r.finalDecision, 'ADMIN REVIEW');
    });

    test('buildRiskSummary يرفع الخطر لـ HIGH لو الصورة مكررة', () {
      final r = buildRiskSummary(const VerificationChecks(), serverFlags: ['DUPLICATE_IMAGE']);
      expect(r.documentRisk, DocumentRisk.highRisk);
      expect(r.flags, contains('DUPLICATE_IMAGE'));
    });
  });

  group('نسخ المستندات القديمة', () {
    test('رقم النسخة الجديدة = أعلى نسخة موجودة + 1', () {
      expect(nextDocVersion(null, DocType.idFront), 1);
      final v = CaptainVerification(
        captainId: 'c',
        activeDocs: {DocType.drivingLicense: _doc(DocType.drivingLicense, v: 2)},
        pendingDocs: {DocType.drivingLicense: _doc(DocType.drivingLicense, v: 3)},
      );
      expect(nextDocVersion(v, DocType.drivingLicense), 4);
      expect(nextDocVersion(v, DocType.idFront), 1);
    });

    test('الاعتماد: الجديدة ACTIVE والقديمة SUPERSEDED وما بتتحذفش', () {
      final active = {DocType.drivingLicense: _doc(DocType.drivingLicense, v: 1), DocType.idFront: _doc(DocType.idFront)};
      final pending = {DocType.drivingLicense: _doc(DocType.drivingLicense, v: 2, expires: DateTime(2030, 1, 1))};
      final m = mergeApprovedDocs(active, pending);
      expect(m.active[DocType.drivingLicense]!.version, 2);
      expect(m.active[DocType.drivingLicense]!.status, 'ACTIVE');
      expect(m.active[DocType.idFront]!.version, 1); // اللي ما اتجددش بيفضل
      expect(m.superseded.map((d) => d.version), [1]);
      expect(m.activated.map((d) => d.version), [2]);
    });

    test('نفس النسخة المعتمدة ما تتحولش SUPERSEDED', () {
      final d = _doc(DocType.idFront);
      final m = mergeApprovedDocs({DocType.idFront: d}, {DocType.idFront: d});
      expect(m.superseded, isEmpty);
    });
  });

  group('الإقرار الإلكتروني', () {
    test('البصمة ثابتة لنفس النص والنسخة', () {
      expect(declarationHash(), declarationHash());
      expect(declarationHash().length, 64);
    });

    test('تغيّر النص أو النسخة يغيّر البصمة (نعرف أنهي نسخة وافق عليها)', () {
      expect(declarationHash(version: '1.0'), isNot(declarationHash()));
      expect(declarationHash(text: '${kDeclarationText}.'), isNot(declarationHash()));
    });

    test('الموافقة بتسجّل captainId + النسخة + الوقت + البصمة، مش accepted=true', () {
      final at = DateTime(2026, 10, 4, 10);
      final a = DeclarationAcceptance.now('cap1', at: at);
      final m = a.toMap();
      expect(m.keys.toSet(), {'captainId', 'termsVersion', 'acceptedAt', 'acceptedDocumentHash'});
      expect(m['captainId'], 'cap1');
      expect(m['termsVersion'], kTermsVersion);
      expect(m['acceptedAt'], at.millisecondsSinceEpoch);
      expect(m['acceptedDocumentHash'], declarationHash());
      expect(a.isCurrent, isTrue);
    });

    test('موافقة على نسخة أقدم أو نص مختلف = مش حالية', () {
      final old = DeclarationAcceptance(
          captainId: 'c', termsVersion: '0.9', acceptedAt: 1, acceptedDocumentHash: declarationHash(version: '0.9'));
      expect(old.isCurrent, isFalse);
    });

    test('رجوع من الخريطة (وعدم قبول بيانات ناقصة)', () {
      final a = DeclarationAcceptance.now('c');
      expect(DeclarationAcceptance.fromMap(a.toMap())!.acceptedDocumentHash, a.acceptedDocumentHash);
      expect(DeclarationAcceptance.fromMap({'captainId': 'c'}), isNull);
      expect(DeclarationAcceptance.fromMap(null), isNull);
    });

    test('الإقرار فيه بند رسوم المنصة بنفس قيمة الثابت (5 جنيه على كل مشوار)', () {
      expect(platformFeePerTrip, 5);
      expect(kDeclarationText.contains('${platformFeePerTrip.toInt()} جنيهات'), isTrue);
      expect(kDeclarationText.contains('عن كل مشوار'), isTrue);
      expect(kTermsVersion, '1.1');
    });

    test('النص يبدأ وينتهي بالجمل المعتمدة حرفيًا', () {
      expect(kDeclarationText.startsWith('أقر أنا الكابتن بأن جميع البيانات والمستندات'), isTrue);
      expect(kDeclarationText.endsWith('وأوافق عليه إلكترونيًا.'), isTrue);
      expect(kDeclarationCheckboxLabel, 'أوافق على الإقرار والتعهد');
    });
  });
}
