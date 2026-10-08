import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;

import '../../../models/models.dart' show AppUser, VehicleType;
import '../../../services/firebase_service.dart' show friendlyError;
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../data/verification_repository.dart';
import '../domain/declaration.dart';
import '../domain/document_requirements.dart';
import '../domain/image_quality.dart';
import '../domain/national_id.dart';
import '../domain/verification_enums.dart';
import '../domain/verification_rules.dart';
import '../models/captain_verification.dart';
import 'camera_capture_screen.dart';

const Map<VerificationStatus, String> kStatusLabels = {
  VerificationStatus.notStarted: 'لم يبدأ',
  VerificationStatus.incomplete: 'غير مكتمل',
  VerificationStatus.pendingReview: 'قيد المراجعة',
  VerificationStatus.needsCorrection: 'يحتاج تصحيح',
  VerificationStatus.verified: 'موثّق',
  VerificationStatus.rejected: 'مرفوض',
  VerificationStatus.suspended: 'معلّق',
  VerificationStatus.expired: 'منتهي الصلاحية',
};

const Map<DocType, String> kDocLabels = {
  DocType.idFront: 'البطاقة (الوجه)',
  DocType.idBack: 'البطاقة (الظهر)',
  DocType.selfieWithId: 'سيلفي وأنت ماسك البطاقة',
  DocType.poseRight: 'صورة: حرّك رأسك لليمين',
  DocType.poseLeft: 'صورة: حرّك رأسك لليسار',
  DocType.drivingLicense: 'رخصة القيادة',
  DocType.vehicleLicense: 'رخصة المركبة',
  DocType.vehiclePhoto: 'صورة المركبة (اللوحة واضحة)',
};

CaptureSpec _specFor(DocType t) {
  switch (t) {
    case DocType.idFront:
    case DocType.idBack:
    case DocType.drivingLicense:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction:
            'ضع المستند بالكامل داخل الإطار. إضاءة جيدة، بدون انعكاس، وكل البيانات واضحة.',
        frame: CaptureFrame.card,
      );
    case DocType.vehicleLicense:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction: 'ضع الرخصة بالكامل داخل الإطار. بدون انعكاس وكل البيانات واضحة.',
        frame: CaptureFrame.document,
      );
    case DocType.vehiclePhoto:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction: 'صوّر المركبة بحيث يظهر رقم اللوحة بوضوح. ابعد قدر يسمح بقراءة اللوحة.',
        frame: CaptureFrame.none,
      );
    case DocType.selfieWithId:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction: 'انظر للكاميرا وأمسك البطاقة بجانب وجهك بحيث تكون بياناتها واضحة.',
        frame: CaptureFrame.face,
        useFrontCamera: true,
        thresholds: QualityThresholds.selfie,
      );
    case DocType.poseRight:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction: 'حرّك رأسك ببطء ناحية اليمين مع بقاء وجهك داخل الإطار ثم صوّر.',
        frame: CaptureFrame.face,
        useFrontCamera: true,
        thresholds: QualityThresholds.selfie,
      );
    case DocType.poseLeft:
      return CaptureSpec(
        title: kDocLabels[t]!,
        instruction: 'حرّك رأسك ببطء ناحية اليسار مع بقاء وجهك داخل الإطار ثم صوّر.',
        frame: CaptureFrame.face,
        useFrontCamera: true,
        thresholds: QualityThresholds.selfie,
      );
  }
}

enum _Step { basics, identity, selfie, vehicle, declaration, review, send }

const Map<_Step, String> _stepTitles = {
  _Step.basics: 'البيانات الأساسية',
  _Step.identity: 'بطاقة الرقم القومي',
  _Step.selfie: 'السيلفي والتحقق',
  _Step.vehicle: 'مستندات المركبة',
  _Step.declaration: 'الإقرار الإلكتروني',
  _Step.review: 'مراجعة البيانات',
  _Step.send: 'إرسال للمراجعة',
};

/// شاشة توثيق الكابتن. emailVerified شيء منفصل عن حالة التوثيق.
class CaptainVerificationScreen extends StatefulWidget {
  final AppUser user;
  const CaptainVerificationScreen({super.key, required this.user});

  @override
  State<CaptainVerificationScreen> createState() => _CaptainVerificationScreenState();
}

class _CaptainVerificationScreenState extends State<CaptainVerificationScreen> {
  final _repo = VerificationRepository();
  // الـ stream بيتعمل مرة واحدة. لو اتعمل جوه build كان كل إعادة بناء (فتح/قفل
  // الكيبورد، أي حرف) بيشترك من جديد، وللحساب اللي لسه ماله مستند التوثيق
  // (البيانات null) كان بيظهر لودينج بدل الفورم ويضيع مكان المؤشر.
  late final Stream<CaptainVerification?> _verStream = _repo.watch(user.id);
  final _name = TextEditingController();
  final _nid = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();

  int _stepIndex = 0;
  bool _seeded = false;
  bool _busy = false;
  bool _agree = false;
  bool _emailVerified = false;
  String? _error;

  AppUser get user => widget.user;
  VehicleType? get _vehicle => user.vehicleType;

  List<_Step> get _steps => [
        _Step.basics,
        _Step.identity,
        _Step.selfie,
        if (vehicleNeedsLicenseData(_vehicle)) _Step.vehicle,
        _Step.declaration,
        _Step.review,
        _Step.send,
      ];

  @override
  void initState() {
    super.initState();
    _emailVerified = fb.FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    _name.text = user.name;
    _plate.text = user.plateNumber ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _nid, _license, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  /// نص + مؤشر في الآخر. (`controller.text = ...` بيسيب المؤشر في -1 فالحروف
  /// اللي بتتكتب بعدها كانت بتتحط في أول الحقل.)
  void _setText(TextEditingController c, String t) {
    c.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  void _seed(CaptainVerification? v) {
    if (_seeded || v == null) return;
    _seeded = true;
    if (v.fullName.isNotEmpty) _setText(_name, v.fullName);
    _setText(_nid, v.nationalId);
    _setText(_license, v.licenseNumber);
    if (v.plateNumber.isNotEmpty) _setText(_plate, v.plateNumber);
    _agree = v.declaration?.isCurrent ?? false;
  }

  bool _editable(VerificationStatus s) => const {
        VerificationStatus.notStarted,
        VerificationStatus.incomplete,
        VerificationStatus.needsCorrection,
        VerificationStatus.expired,
      }.contains(s);

  Future<T?> _guard<T>(Future<T> Function() job) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      return await job();
    } catch (e) {
      if (mounted) setState(() => _error = 'حدث خطأ: ${friendlyError(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile(CaptainVerification? v) => _guard(() => _repo.saveProfile(
        user.id,
        fullName: _name.text,
        nationalId: _nid.text,
        licenseNumber: _license.text,
        plateNumber: _plate.text,
        current: v,
      ));

  String? _basicsError() {
    if (_name.text.trim().length < 6) return 'اكتب الاسم الرباعي كما في البطاقة';
    final info = parseNationalId(_nid.text);
    if (info == null) return 'الرقم القومي غير صحيح (14 رقم)';
    if (ageOn(info.birthDate, DateTime.now()) < 18) return 'لازم يكون عمرك 18 سنة أو أكتر';
    if (vehicleNeedsLicenseData(_vehicle)) {
      if (_license.text.trim().length < 5) return 'اكتب رقم رخصة القيادة';
      if (_plate.text.trim().length < 3) return 'اكتب رقم اللوحة';
    }
    return null;
  }

  Future<void> _capture(DocType type, CaptainVerification? v) async {
    final req = requiredDocuments(_vehicle).firstWhere((r) => r.type == type,
        orElse: () => DocRequirement(type));
    final res = await captureDocument(context, _specFor(type));
    if (res == null || !mounted) return;

    int? expiresAt;
    if (req.hasExpiry) {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        helpText: 'تاريخ انتهاء ${kDocLabels[type]}',
        initialDate: now.add(const Duration(days: 365)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 365 * 30)),
      );
      if (d == null) return; // من غير تاريخ انتهاء مفيش حفظ
      expiresAt = d.millisecondsSinceEpoch;
    }
    final number = type == DocType.drivingLicense
        ? _license.text.trim()
        : (type == DocType.vehiclePhoto ? _plate.text.trim() : null);
    await _guard(() => _repo.uploadDocument(
          uid: user.id,
          type: type,
          jpegBytes: res.jpegBytes,
          quality: res.quality.toMap(),
          expiresAt: expiresAt,
          number: number,
          current: v,
          verified: v?.status == VerificationStatus.verified,
        ));
  }

  Future<void> _refreshEmail() async {
    final u = fb.FirebaseAuth.instance.currentUser;
    await u?.reload();
    final ok = fb.FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    await _repo.requestGateRefresh(user.id);
    if (mounted) setState(() => _emailVerified = ok);
  }

  // ───────── الواجهة ─────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: C.slate50,
        appBar: AppBar(
          title: Text('توثيق حساب الكابتن', style: T.s(17, T.w900, C.slate900)),
          backgroundColor: C.white,
          foregroundColor: C.slate900,
          elevation: 0,
        ),
        body: StreamBuilder<CaptainVerification?>(
          stream: _verStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('تعذر تحميل بيانات التوثيق', style: T.s(14, T.w900, C.rose500)));
            }
            // waiting = لسه ماجاش أول رد (بعدها بيبقى active حتى لو المستند null).
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final v = snap.data;
            _seed(v);
            final status = v?.status ?? VerificationStatus.notStarted;
            return Stack(
              children: [
                _body(v, status),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(CaptainVerification? v, VerificationStatus status) {
    if (status == VerificationStatus.pendingReview) return _statusCard(v, status);
    if (status == VerificationStatus.rejected || status == VerificationStatus.suspended) {
      return _statusCard(v, status);
    }
    if (status == VerificationStatus.verified) return _verifiedBody(v!);
    return _wizard(v, status);
  }

  // ───── حالات القراءة فقط ─────

  Widget _chip(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: T.s(12, T.w900, fg)),
      );

  Widget _emailRow() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(_emailVerified ? Icons.mark_email_read : Icons.mark_email_unread,
                color: _emailVerified ? C.emerald600 : C.amber500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _emailVerified
                      ? 'البريد الإلكتروني مؤكد (ده لا يعني إن حسابك موثّق)'
                      : 'البريد الإلكتروني غير مؤكد',
                  style: T.s(12, T.w700, C.slate800)),
            ),
            TextButton(onPressed: _refreshEmail, child: const Text('تحديث')),
          ],
        ),
      );

  Widget _statusCard(CaptainVerification? v, VerificationStatus status) {
    final reason = v?.review?.reason ?? '';
    final text = switch (status) {
      VerificationStatus.pendingReview =>
        'تم إرسال طلب التوثيق وهو قيد المراجعة من الإدارة. هنبلغك بالنتيجة.',
      VerificationStatus.rejected =>
        'تم رفض طلب التوثيق. لو شايف إن في خطأ تواصل مع الدعم.',
      _ => 'حسابك معلّق حاليًا ولا يمكنك استقبال الطلبات. تواصل مع الدعم.',
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _emailRow(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chip(kStatusLabels[status]!, C.amber50, C.amber500),
              const SizedBox(height: 12),
              Text(text, style: T.s(14, T.w700, C.slate800, height: 1.7)),
              if (reason.isNotEmpty && status != VerificationStatus.pendingReview) ...[
                const SizedBox(height: 10),
                Text('السبب: $reason', style: T.s(13, T.w900, C.rose500)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _verifiedBody(CaptainVerification v) {
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _emailRow(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chip('موثّق', C.emerald50, C.emerald700),
              const SizedBox(height: 10),
              Text(
                  gateOpen(v, now)
                      ? 'حسابك موثّق ويمكنك استقبال الطلبات.'
                      : 'حسابك موثّق لكن استقبال الطلبات متوقف مؤقتًا (${[
                          for (final r in v.gate.reasons) kGateReasonLabels[r] ?? r
                        ].join('، ')}).',
                  style: T.s(13, T.w700, C.slate800, height: 1.7)),
              if (v.renewalPending) ...[
                const SizedBox(height: 8),
                Text('طلب تجديد مستندات قيد المراجعة.', style: T.s(12, T.w900, C.amber500)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final req in requiredDocuments(_vehicle).where((r) => r.hasExpiry)) ...[
          _expiryCard(req, v, now),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _expiryCard(DocRequirement req, CaptainVerification v, DateTime now) {
    final doc = v.activeDocs[req.type];
    final exp = doc?.expiryDate;
    final st = exp == null ? null : expiryStatus(exp, now);
    final (label, bg, fg) = switch (st) {
      ExpiryStatus.valid => ('ساري', C.emerald50, C.emerald700),
      ExpiryStatus.expiringSoon => ('ينتهي قريبًا', C.amber50, C.amber500),
      ExpiryStatus.expired => ('منتهي', C.rose50, C.rose500),
      null => ('غير محدد', C.slate50, C.slate500),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kDocLabels[req.type]!, style: T.s(14, T.w900, C.slate900)),
                const SizedBox(height: 4),
                Text(
                    exp == null
                        ? '—'
                        : 'ينتهي ${intl.DateFormat('yyyy/MM/dd').format(exp)} (${daysUntilExpiry(exp, now)} يوم)',
                    style: T.s(12, T.w700, C.slate500)),
                if (v.pendingDocs.containsKey(req.type))
                  Text('نسخة جديدة قيد المراجعة', style: T.s(11, T.w900, C.amber500)),
              ],
            ),
          ),
          _chip(label, bg, fg),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _capture(req.type, v),
            child: const Text('تجديد'),
          ),
        ],
      ),
    );
  }

  // ───── المعالج (الخطوات) ─────

  Widget _wizard(CaptainVerification? v, VerificationStatus status) {
    final steps = _steps;
    if (_stepIndex >= steps.length) _stepIndex = steps.length - 1;
    final step = steps[_stepIndex];
    final editable = _editable(status);

    return Column(
      children: [
        Container(
          color: C.white,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الخطوة ${_stepIndex + 1} من ${steps.length}: ${_stepTitles[step]}',
                  style: T.s(13, T.w900, C.slate800)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_stepIndex + 1) / steps.length,
                  minHeight: 8,
                  backgroundColor: C.slate100,
                  color: C.emerald600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (status == VerificationStatus.needsCorrection && v?.review != null) ...[
                _correctionBanner(v!),
                const SizedBox(height: 14),
              ],
              if (status == VerificationStatus.expired) ...[
                _notice('انتهت صلاحية مستند. جدّد المستند المنتهي ثم أعد الإرسال.', C.rose50, C.rose500),
                const SizedBox(height: 14),
              ],
              _stepBody(step, v, status, editable),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: T.s(13, T.w900, C.rose500)),
              ],
            ],
          ),
        ),
        _navBar(steps, step, v, status),
      ],
    );
  }

  Widget _notice(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(t, style: T.s(12, T.w900, fg, height: 1.6)),
      );

  Widget _correctionBanner(CaptainVerification v) {
    final r = v.review!;
    final docs = [
      for (final d in r.correctionDocs)
        if (DocType.tryParse(d) != null) kDocLabels[DocType.tryParse(d)]!
    ];
    return _notice(
      'مطلوب تصحيح: ${r.reason}${docs.isEmpty ? '' : '\nالمستندات المطلوب إعادة تصويرها: ${docs.join('، ')}'}',
      C.amber50,
      C.amber500,
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? type,
      bool enabled = true,
      int? maxLength,
      String? hint,
      bool digitsOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: enabled,
        keyboardType: type,
        maxLength: maxLength,
        // الأرقام بتتكتب شمال-لليمين حتى في واجهة RTL، وبتتحوّل للإنجليزي
        // (لو الكيبورد عربي) من غير ما المؤشر يتحرك.
        textDirection: digitsOnly ? TextDirection.ltr : null,
        textAlign: digitsOnly ? TextAlign.right : TextAlign.start,
        inputFormatters: digitsOnly ? [_DigitsOnlyFormatter()] : null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
          filled: true,
          fillColor: C.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _stepBody(_Step step, CaptainVerification? v, VerificationStatus status, bool editable) {
    switch (step) {
      case _Step.basics:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _emailRow(),
            const SizedBox(height: 12),
            _field(_name, 'الاسم الرباعي (كما في البطاقة)', enabled: editable),
            _field(_nid, 'الرقم القومي (14 رقم)',
                type: TextInputType.number, enabled: editable, maxLength: 14, digitsOnly: true),
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(16)),
              child: Text('نوع المركبة: ${_vehicleLabel(_vehicle)}  •  الهاتف: ${user.phone}',
                  style: T.s(12, T.w700, C.slate500)),
            ),
            if (vehicleNeedsLicenseData(_vehicle)) ...[
              _field(_license, 'رقم رخصة القيادة', enabled: editable),
              _field(_plate, 'رقم اللوحة', enabled: editable),
            ],
          ],
        );
      case _Step.identity:
        return _docTiles([DocType.idFront, DocType.idBack], v, editable,
            note: 'صوّر البطاقة من الكاميرا مباشرة داخل الإطار. لا يمكن اختيار صورة من المعرض.');
      case _Step.selfie:
        return _docTiles([DocType.selfieWithId, DocType.poseRight, DocType.poseLeft], v, editable,
            note:
                'الصور دي بتتراجع بواسطة موظف من الإدارة. التحقق الآلي من الوجه غير متاح حاليًا، والقرار النهائي بشري.');
      case _Step.vehicle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _docTiles([DocType.drivingLicense, DocType.vehicleLicense, DocType.vehiclePhoto], v, editable,
                note: 'بعد التصوير هتختار تاريخ انتهاء المستند.'),
          ],
        );
      case _Step.declaration:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
              child: SingleChildScrollView(
                child: Text(kDeclarationText, style: T.s(13, T.w700, C.slate800, height: 1.9)),
              ),
            ),
            const SizedBox(height: 6),
            Text('نسخة الإقرار: $kTermsVersion', style: T.s(11, T.w700, C.slate400)),
            CheckboxListTile(
              value: _agree,
              onChanged: editable ? (b) => setState(() => _agree = b ?? false) : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(kDeclarationCheckboxLabel, style: T.s(14, T.w900, C.slate900)),
            ),
            if (v?.declaration != null)
              Text(
                  'تمت الموافقة على النسخة ${v!.declaration!.termsVersion} بتاريخ ${intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(v.declaration!.acceptedAt))}',
                  style: T.s(11, T.w700, C.emerald700)),
          ],
        );
      case _Step.review:
        return _reviewList(v);
      case _Step.send:
        final blockers = _blockers(v);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _notice(
                blockers.isEmpty
                    ? 'كل شيء جاهز. بعد الإرسال هتتراجع بياناتك من الإدارة، ولن تستقبل طلبات إلا بعد الاعتماد.'
                    : 'لا يمكن الإرسال قبل استكمال: ${blockers.length} بند. ارجع لخطوة "مراجعة البيانات".',
                blockers.isEmpty ? C.emerald50 : C.amber50,
                blockers.isEmpty ? C.emerald700 : C.amber500),
          ],
        );
    }
  }

  String _vehicleLabel(VehicleType? t) => switch (t) {
        VehicleType.car => 'سيارة',
        VehicleType.motorcycle => 'موتوسيكل',
        VehicleType.toktok => 'توكتوك',
        null => 'غير محدد',
      };

  Widget _docTiles(List<DocType> types, CaptainVerification? v, bool editable, {String? note}) {
    final highlight = {for (final d in v?.review?.correctionDocs ?? const <String>[]) d};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null) ...[_notice(note, C.slate100, C.slate800), const SizedBox(height: 12)],
        for (final t in types) ...[
          _tile(t, v, editable, highlight.contains(t.value)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _tile(DocType t, CaptainVerification? v, bool editable, bool needsRetake) {
    final d = v?.currentDoc(t);
    final failed = d?.quality['result'] == 'FAIL';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: needsRetake ? C.amber500 : C.slate100, width: 2),
      ),
      child: Row(
        children: [
          Icon(d == null ? Icons.radio_button_unchecked : Icons.check_circle,
              color: d == null ? C.slate400 : C.emerald600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kDocLabels[t]!, style: T.s(14, T.w900, C.slate900)),
                const SizedBox(height: 2),
                Text(
                    d == null
                        ? 'لم يتم التصوير'
                        : 'تم التصوير (نسخة ${d.version})${d.expiresAt != null ? ' • ينتهي ${intl.DateFormat('yyyy/MM/dd').format(d.expiryDate!)}' : ''}',
                    style: T.s(11, T.w700, failed ? C.rose500 : C.slate500)),
                if (needsRetake) Text('مطلوب إعادة التصوير', style: T.s(11, T.w900, C.amber500)),
              ],
            ),
          ),
          TextButton(
            onPressed: (!editable || _busy) ? null : () => _capture(t, v),
            child: Text(d == null ? 'تصوير' : 'إعادة'),
          ),
        ],
      ),
    );
  }

  List<String> _blockers(CaptainVerification? v) => submissionBlockers(
        vehicleType: _vehicle,
        nationalId: _nid.text,
        fullName: _name.text,
        licenseNumber: _license.text,
        plateNumber: _plate.text,
        docs: {...?v?.activeDocs, ...?v?.pendingDocs},
        declarationAccepted: v?.declaration?.isCurrent ?? false,
        now: DateTime.now(),
      );

  Widget _reviewList(CaptainVerification? v) {
    final blockers = _blockers(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blockers.isEmpty)
          _notice('البيانات مكتملة.', C.emerald50, C.emerald700)
        else ...[
          _notice('بنود ناقصة:', C.amber50, C.amber500),
          for (final b in blockers)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• ${_blockerLabel(b)}', style: T.s(13, T.w700, C.slate800)),
            ),
        ],
        const SizedBox(height: 14),
        _summaryRow('الاسم', _name.text),
        _summaryRow('الرقم القومي', maskNationalId(_nid.text)),
        _summaryRow('الإقرار', v?.declaration?.isCurrent == true ? 'تمت الموافقة (نسخة $kTermsVersion)' : 'غير مسجّل'),
      ],
    );
  }

  String _blockerLabel(String b) {
    for (final t in DocType.values) {
      if (b.endsWith(t.value)) return b.replaceAll(t.value, kDocLabels[t]!);
    }
    return b;
  }

  Widget _summaryRow(String k, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(k, style: T.s(12, T.w900, C.slate500))),
            Expanded(child: Text(val.isEmpty ? '—' : val, style: T.s(13, T.w700, C.slate900))),
          ],
        ),
      );

  Widget _navBar(List<_Step> steps, _Step step, CaptainVerification? v, VerificationStatus status) {
    final editable = _editable(status);
    final last = _stepIndex == steps.length - 1;
    return SafeArea(
      top: false,
      child: Container(
        color: C.white,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_stepIndex > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _stepIndex--),
                  child: const Text('السابق'),
                ),
              ),
            if (_stepIndex > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: C.emerald600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _busy ? null : () => _next(steps, step, v, last, editable),
                child: Text(last ? 'إرسال للمراجعة' : 'التالي'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _next(List<_Step> steps, _Step step, CaptainVerification? v, bool last, bool editable) async {
    setState(() => _error = null);
    if (editable) {
      switch (step) {
        case _Step.basics:
          final e = _basicsError();
          if (e != null) return setState(() => _error = e);
          await _saveProfile(v);
        case _Step.identity:
          if (v?.currentDoc(DocType.idFront) == null || v?.currentDoc(DocType.idBack) == null) {
            return setState(() => _error = 'صوّر وجه وظهر البطاقة');
          }
        case _Step.selfie:
          if (!{DocType.selfieWithId, DocType.poseRight, DocType.poseLeft}
              .every((t) => v?.currentDoc(t) != null)) {
            return setState(() => _error = 'استكمل الصور الثلاث');
          }
        case _Step.vehicle:
          if (!{DocType.drivingLicense, DocType.vehicleLicense, DocType.vehiclePhoto}
              .every((t) => v?.currentDoc(t) != null)) {
            return setState(() => _error = 'استكمل مستندات المركبة');
          }
        case _Step.declaration:
          if (!_agree) return setState(() => _error = 'لازم توافق على الإقرار والتعهد للمتابعة');
          if (!(v?.declaration?.isCurrent ?? false)) {
            await _guard(() => _repo.acceptDeclaration(user.id));
          }
        case _Step.review:
        case _Step.send:
          break;
      }
      if (_error != null) return;
    }
    if (!last) {
      setState(() => _stepIndex++);
      return;
    }
    // الإرسال
    if (v == null) return setState(() => _error = 'ابدأ بإدخال البيانات أولًا');
    final blockers = _blockers(v);
    if (blockers.isNotEmpty) return setState(() => _error = 'استكمل البنود الناقصة أولًا');
    await _guard(() => _repo.submit(v));
  }
}

/// بيسمح بالأرقام بس، وبيحوّل العربية (٠-٩) للإنجليزية، ويحافظ على مكان المؤشر.
class _DigitsOnlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = normalizeDigits(newValue.text);
    if (cleaned == newValue.text) return newValue;
    final sel = newValue.selection;
    final cut = sel.isValid ? sel.baseOffset.clamp(0, newValue.text.length) : newValue.text.length;
    final offset = normalizeDigits(newValue.text.substring(0, cut)).length;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset.clamp(0, cleaned.length)),
    );
  }
}
