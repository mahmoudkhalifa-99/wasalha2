import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../../models/models.dart' show AppUser, VehicleType;
import '../../../services/firebase_service.dart' show friendlyError;
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../data/verification_repository.dart';
import '../domain/document_requirements.dart';
import '../domain/review_checklist.dart';
import '../domain/national_id.dart';
import '../domain/unique_keys.dart';
import '../domain/verification_enums.dart';
import '../domain/verification_rules.dart';
import '../models/captain_verification.dart';
import 'captain_verification_screen.dart' show kDocLabels, kStatusLabels;

const _tabs = [
  VerificationStatus.pendingReview,
  VerificationStatus.verified,
  VerificationStatus.needsCorrection,
  VerificationStatus.rejected,
  VerificationStatus.suspended,
  VerificationStatus.expired,
];

const _checkLabels = {
  'PASS': 'سليم',
  'WARN': 'تنبيه',
  'FAIL': 'مرفوض آليًا',
  'UNAVAILABLE': 'غير متاح',
};

String _riskLabel(DocumentRisk r) => switch (r) {
      DocumentRisk.lowRisk => 'خطر منخفض',
      DocumentRisk.mediumRisk => 'خطر متوسط',
      DocumentRisk.highRisk => 'خطر مرتفع',
      DocumentRisk.unableToDetermine => 'غير قابل للتحديد',
    };

/// لوحة مراجعة توثيق الكباتن (السوبر أدمن فقط: بيانات هوية حساسة).
class AdminVerificationView extends StatefulWidget {
  final AppUser user;
  const AdminVerificationView({super.key, required this.user});

  @override
  State<AdminVerificationView> createState() => _AdminVerificationViewState();
}

class _AdminVerificationViewState extends State<AdminVerificationView> {
  final _repo = VerificationRepository();
  VerificationStatus _tab = VerificationStatus.pendingReview;

  Future<void> _toggleEnforced(bool want) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(want ? 'تفعيل الإلزام؟' : 'إيقاف الإلزام؟'),
          content: Text(want
              ? 'بعد التفعيل: أي كابتن غير موثّق (أو مستنداته منتهية) مش هيقدر يقدّم عروض ولا يتعيّن على طلبات. تأكد إن الـ Cloud Functions منشورة وإن الكباتن الحاليين وثّقوا حساباتهم.'
              : 'الكباتن هيرجعوا يستقبلوا طلبات بدون شرط التوثيق.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _repo.setEnforced(want, widget.user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamBuilder<VerificationConfig>(
            stream: _repo.watchConfig(),
            builder: (c, s) {
              final enforced = s.data?.enforced ?? false;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: enforced ? C.emerald50 : C.amber50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(enforced ? 'إلزام التوثيق: مفعّل' : 'إلزام التوثيق: غير مفعّل',
                              style: T.s(14, T.w900, C.slate900)),
                          const SizedBox(height: 4),
                          Text(
                              enforced
                                  ? 'الكباتن غير الموثّقين ممنوعين من العروض والتعيين (على مستوى السيرفر).'
                                  : 'الكباتن الحاليين لسه بيستقبلوا طلبات. فعّل الإلزام بعد نشر الـ Functions وتوثيق الكباتن.',
                              style: T.s(11, T.w700, C.slate500, height: 1.5)),
                        ],
                      ),
                    ),
                    Switch(value: enforced, onChanged: _toggleEnforced),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in _tabs)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(kStatusLabels[t]!),
                      selected: _tab == t,
                      onSelected: (_) => setState(() => _tab = t),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<CaptainVerification>>(
            stream: _repo.watchByStatus(_tab),
            builder: (c, s) {
              if (s.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('تعذر تحميل القائمة', style: T.s(13, T.w900, C.rose500)),
                );
              }
              if (!s.hasData) {
                return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
              }
              final list = s.data!;
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text('لا توجد حالات', style: T.s(14, T.w900, C.slate400))),
                );
              }
              return Column(
                children: [for (final v in list) _row(v)],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(CaptainVerification v) {
    final when = v.submittedAt ?? v.updatedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _CaptainDetail(admin: widget.user, captainId: v.captainId, repo: _repo),
        )),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.fullName.isEmpty ? 'بدون اسم' : v.fullName, style: T.s(14, T.w900, C.slate900)),
                    const SizedBox(height: 3),
                    Text(
                        '${maskNationalId(v.nationalId)}  •  ${when == 0 ? '' : intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(when))}',
                        style: T.s(11, T.w700, C.slate500)),
                    if (v.serverFlags.isNotEmpty)
                      Text('⚠ ${v.serverFlags.join('، ')}', style: T.s(11, T.w900, C.rose500)),
                    if (v.renewalPending) Text('طلب تجديد مستندات', style: T.s(11, T.w900, C.amber500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════ تفاصيل كابتن ═════════════

class _CaptainDetail extends StatefulWidget {
  final AppUser admin;
  final String captainId;
  final VerificationRepository repo;
  const _CaptainDetail({required this.admin, required this.captainId, required this.repo});

  @override
  State<_CaptainDetail> createState() => _CaptainDetailState();
}

class _CaptainDetailState extends State<_CaptainDetail> {
  final Map<String, Future<Uint8List?>> _imgs = {};
  Map<String, dynamic>? _userData;
  bool _showNid = false;
  bool _busy = false;
  final Map<UniqueKeyType, String?> _dupOwners = {};
  bool _dupLooked = false;

  @override
  void initState() {
    super.initState();
    widget.repo.logAccess(widget.captainId, widget.admin.id);
    FirebaseFirestore.instance.collection('users').doc(widget.captainId).get().then((s) {
      if (mounted) setState(() => _userData = s.data());
    });
  }

  Future<Uint8List?> _img(String path) => _imgs.putIfAbsent(path, () => widget.repo.readDocBytes(path));

  Future<void> _lookupDuplicates(CaptainVerification v) async {
    if (_dupLooked) return;
    _dupLooked = true;
    final pairs = {
      if (v.serverFlags.contains('DUPLICATE_NID')) UniqueKeyType.nid: v.nationalId,
      if (v.serverFlags.contains('DUPLICATE_PHONE')) UniqueKeyType.phone: (_userData?['phone'] as String?) ?? '',
      if (v.serverFlags.contains('DUPLICATE_LICENSE')) UniqueKeyType.license: v.licenseNumber,
      if (v.serverFlags.contains('DUPLICATE_PLATE')) UniqueKeyType.plate: v.plateNumber,
    };
    for (final e in pairs.entries) {
      _dupOwners[e.key] = await widget.repo.duplicateOwner(e.key, e.value, excludeUid: v.captainId);
    }
    if (mounted) setState(() {});
  }

  Future<void> _decide(CaptainVerification v, ReviewDecision d) async {
    final reasonCtrl = TextEditingController();
    final flagged = <DocType>{};
    final items = checklistFor(
        needsVehicleDocs: _vehicleType() != null && vehicleNeedsLicenseData(_vehicleType()));
    final checked = <String>{};
    final needsReason = d != ReviewDecision.approve && d != ReviewDecision.reactivate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (c, setD) => AlertDialog(
            title: Text(switch (d) {
              ReviewDecision.approve => 'اعتماد التوثيق',
              ReviewDecision.needsCorrection => 'طلب تصحيح',
              ReviewDecision.reject => 'رفض الطلب',
              ReviewDecision.suspend => 'تعليق الكابتن',
              ReviewDecision.reactivate => 'إعادة التفعيل',
            }),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (d == ReviewDecision.approve) ...[
                    if (v.serverFlags.any(kBlockingServerFlags.contains))
                      Text('تحذير: يوجد تكرار في بيانات الهوية. الكابتن لن يستقبل طلبات حتى لو اعتمدته.',
                          style: T.s(12, T.w900, C.rose500)),
                    Text('أكّد كل بند بعد ما تقارن البيانات المُدخلة بالمستندات (الفحص الآلي مساعد فقط):',
                        style: T.s(12, T.w900, C.slate800)),
                    for (final it in items)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: checked.contains(it.key),
                        onChanged: (b) => setD(() => b == true ? checked.add(it.key) : checked.remove(it.key)),
                        title: Text(it.label, style: T.s(12, T.w700, C.slate800)),
                      ),
                    if (!checklistComplete(items, checked))
                      Text('الاعتماد يتفعّل بعد تأكيد كل البنود.', style: T.s(11, T.w700, C.slate500)),
                  ],
                  if (d == ReviewDecision.needsCorrection || d == ReviewDecision.reject) ...[
                    Text('المستندات المطلوب إعادتها (اختياري):', style: T.s(12, T.w900, C.slate800)),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final t in v.pendingDocs.keys)
                          FilterChip(
                            label: Text(kDocLabels[t]!, style: const TextStyle(fontSize: 11)),
                            selected: flagged.contains(t),
                            onSelected: (s) => setD(() => s ? flagged.add(t) : flagged.remove(t)),
                          ),
                      ],
                    ),
                  ],
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: needsReason ? 'السبب (مطلوب)' : 'ملاحظة (اختياري)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              TextButton(
                onPressed: () {
                  if (needsReason && reasonCtrl.text.trim().length < 3) return;
                  if (d == ReviewDecision.approve && !checklistComplete(items, checked)) return;
                  Navigator.pop(c, true);
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.review(
        v: v,
        adminId: widget.admin.id,
        decision: d,
        reason: reason,
        correctionDocs: flagged.toList(),
        checklist: d == ReviewDecision.approve ? items.where((i) => checked.contains(i.key)).map((i) => i.key).toList() : const [],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تنفيذ القرار: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: C.slate50,
        appBar: AppBar(
          title: Text('مراجعة التوثيق', style: T.s(16, T.w900, C.slate900)),
          backgroundColor: C.white,
          foregroundColor: C.slate900,
          elevation: 0,
        ),
        body: StreamBuilder<CaptainVerification?>(
          stream: widget.repo.watch(widget.captainId),
          builder: (c, s) {
            final v = s.data;
            if (v == null) return const Center(child: CircularProgressIndicator());
            if (v.serverFlags.isNotEmpty) _lookupDuplicates(v);
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _header(v),
                    _section('بيانات الكابتن', _dataSection(v)),
                    _section('مقارنة البيانات بالمستندات', _compare(v)),
                    _section('الهوية والسيلفي', _docGrid(v, [
                      DocType.idFront, DocType.idBack, DocType.selfieWithId, DocType.poseRight, DocType.poseLeft,
                    ])),
                    _section('نتائج الفحص (مساعدة للمراجعة فقط)', _checks(v)),
                    if (_vehicleType() != null && vehicleNeedsLicenseData(_vehicleType()))
                      _section('مستندات المركبة', _vehicleSection(v)),
                    _section('الإقرار الإلكتروني', _declaration(v)),
                    _section('سجل المراجعة', _audit(v)),
                    const SizedBox(height: 90),
                  ],
                ),
                if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator()))),
                Positioned(left: 0, right: 0, bottom: 0, child: _actions(v)),
              ],
            );
          },
        ),
      ),
    );
  }

  VehicleType? _vehicleType() => VehicleType.tryParse(_userData?['vehicleType'] as String?);

  Widget _header(CaptainVerification v) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Expanded(child: Text(v.fullName.isEmpty ? 'بدون اسم' : v.fullName, style: T.s(16, T.w900, C.slate900))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: C.amber50, borderRadius: BorderRadius.circular(12)),
              child: Text(kStatusLabels[v.status]!, style: T.s(12, T.w900, C.amber500)),
            ),
          ],
        ),
      );

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: T.s(13, T.w900, C.slate500)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: T.s(12, T.w900, C.slate500))),
            Expanded(child: Text(v.isEmpty ? '—' : v, style: T.s(13, T.w700, color ?? C.slate900))),
          ],
        ),
      );

  Widget _dataSection(CaptainVerification v) {
    final info = parseNationalId(v.nationalId);
    return Column(
      children: [
        _kv('الاسم', v.fullName),
        Row(
          children: [
            Expanded(child: _kv('الرقم القومي', _showNid ? v.nationalId : maskNationalId(v.nationalId))),
            TextButton(onPressed: () => setState(() => _showNid = !_showNid), child: Text(_showNid ? 'إخفاء' : 'إظهار')),
          ],
        ),
        _kv('شكل الرقم القومي', info == null ? 'غير صحيح' : 'صحيح (ميلاد ${intl.DateFormat('yyyy/MM/dd').format(info.birthDate)})',
            color: info == null ? C.rose500 : null),
        _kv('الهاتف', (_userData?['phone'] as String?) ?? ''),
        _kv('البريد', (_userData?['email'] as String?) ?? ''),
        _kv('نوع المركبة', _vehicleType()?.value ?? ''),
        if (v.licenseNumber.isNotEmpty) _kv('رخصة القيادة', v.licenseNumber),
        if (v.plateNumber.isNotEmpty) _kv('اللوحة', v.plateNumber),
        for (final f in v.serverFlags) ..._flagRow(f),
      ],
    );
  }

  List<Widget> _flagRow(String f) {
    final t = switch (f) {
      'DUPLICATE_NID' => UniqueKeyType.nid,
      'DUPLICATE_PHONE' => UniqueKeyType.phone,
      'DUPLICATE_LICENSE' => UniqueKeyType.license,
      'DUPLICATE_PLATE' => UniqueKeyType.plate,
      _ => null,
    };
    final owner = t == null ? null : _dupOwners[t];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('⚠ $f${owner != null ? ' (نفس القيمة عند كابتن: $owner)' : ''}',
            style: T.s(12, T.w900, C.rose500)),
      ),
    ];
  }

  Widget _docGrid(CaptainVerification v, List<DocType> types) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in types)
          if (v.currentDoc(t) != null) _docThumb(t, v.currentDoc(t)!, isPending: v.pendingDocs.containsKey(t)),
      ],
    );
  }

  Widget _docThumb(DocType t, DocVersion d, {required bool isPending}) {
    final w = (MediaQuery.of(context).size.width - 32 - 32 - 10) / 2;
    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _openFull(d.path, kDocLabels[t]!),
            child: AspectRatio(
              aspectRatio: 1.3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FutureBuilder<Uint8List?>(
                  future: _img(d.path),
                  builder: (c, s) {
                    if (s.connectionState != ConnectionState.done) {
                      return const ColoredBox(color: C.slate100, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    if (s.data == null) {
                      return const ColoredBox(color: C.slate100, child: Center(child: Text('تعذر التحميل')));
                    }
                    return Image.memory(s.data!, fit: BoxFit.cover);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${kDocLabels[t]} • نسخة ${d.version}${isPending ? ' (جديدة)' : ''}', style: T.s(11, T.w900, C.slate800)),
          if (d.expiresAt != null)
            Text('ينتهي ${intl.DateFormat('yyyy/MM/dd').format(d.expiryDate!)}  ${_expiryLabel(d.expiryDate!)}',
                style: T.s(11, T.w700, C.slate500)),
          if (d.number != null && d.number!.isNotEmpty) Text('رقم: ${d.number}', style: T.s(11, T.w700, C.slate500)),
          if ((d.quality['result'] ?? '') == 'WARN')
            Text('جودة: تنبيه (${(d.quality['warnings'] as List? ?? const []).join(', ')})', style: T.s(10, T.w700, C.amber500)),
        ],
      ),
    );
  }

  String _expiryLabel(DateTime e) => switch (expiryStatus(e, DateTime.now())) {
        ExpiryStatus.valid => 'ساري',
        ExpiryStatus.expiringSoon => 'قارب على الانتهاء',
        ExpiryStatus.expired => 'منتهي',
      };

  void _openFull(String path, String title) {
    showDialog(
      context: context,
      builder: (c) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<Uint8List?>(
                future: _img(path),
                builder: (c, s) => s.data == null
                    ? const Center(child: CircularProgressIndicator())
                    : InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(s.data!))),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checks(CaptainVerification v) {
    final r = buildRiskSummary(v.checks, serverFlags: v.serverFlags);
    String chk(CheckResult x) => _checkLabels[x.value] ?? x.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv('جودة الصور', chk(r.documentQuality)),
        _kv('OCR', chk(r.ocr)),
        _kv('مطابقة البيانات', chk(r.dataMatch)),
        _kv('مؤشر خطر المستند', _riskLabel(r.documentRisk),
            color: r.documentRisk == DocumentRisk.highRisk ? C.rose500 : null),
        _kv('السيلفي', r.selfieCaptured ? 'تم التقاط السيلفي' : 'غير موجود'),
        _kv('مطابقة الوجه', r.faceMatch == FaceMatchStatus.unavailable ? 'غير متاح' : r.faceMatch.value),
        _kv('Liveness', r.liveness == LivenessStatus.unableToVerify ? 'غير متاح (مراجعة بشرية)' : r.liveness.value),
        _kv('القرار النهائي', 'مراجعة الإدارة', color: C.emerald700),
        if (r.flags.isNotEmpty) _kv('علامات', r.flags.join('، ')),
        const SizedBox(height: 8),
        Text(
            'ملاحظة: OCR ومطابقة الوجه والـ Liveness غير متاحة بالتبعيات الحالية، وفحص الصور لا يثبت أصالة المستند ولا يكتشف التزوير. القرار مسؤولية المراجع.',
            style: T.s(11, T.w700, C.slate500, height: 1.6)),
      ],
    );
  }


  // ───────── مقارنة جنب بعض: البيانات المُدخلة ↔ المستند ─────────
  Widget _compare(CaptainVerification v) {
    final info = parseNationalId(v.nationalId);
    final vt = _vehicleType();
    final needsVehicle = vt != null && vehicleNeedsLicenseData(vt);
    final licExp = v.currentDoc(DocType.drivingLicense)?.expiryDate;
    final vlicExp = v.currentDoc(DocType.vehicleLicense)?.expiryDate;
    final df = intl.DateFormat('yyyy/MM/dd');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('قارن كل بيان بالصورة اللي جنبه، وبعدها أكّد البنود عند الاعتماد.',
            style: T.s(11, T.w700, C.slate500)),
        const SizedBox(height: 10),
        _cmpBlock(
          '١) الهوية',
          [
            _cmpKv('الاسم المُدخل', v.fullName),
            _cmpKv('الرقم القومي', _showNid ? v.nationalId : maskNationalId(v.nationalId)),
            if (info != null) ...[
              _cmpKv('الميلاد (من الرقم)', df.format(info.birthDate)),
              _cmpKv('النوع (من الرقم)', info.isMale ? 'ذكر' : 'أنثى'),
              _cmpKv('العمر', '${ageOn(info.birthDate, DateTime.now())} سنة'),
            ] else
              _cmpKv('الرقم القومي', 'شكله غير صحيح', color: C.rose500),
            TextButton(
              onPressed: () => setState(() => _showNid = !_showNid),
              child: Text(_showNid ? 'إخفاء الرقم القومي' : 'إظهار الرقم القومي'),
            ),
          ],
          v,
          [DocType.idFront, DocType.idBack],
        ),
        _cmpBlock(
          '٢) الوجه',
          [
            Text('قارن وجه البطاقة بالسيلفي ووضعيتي الوجه (يمين/يسار).',
                style: T.s(12, T.w700, C.slate800, height: 1.5)),
          ],
          v,
          [DocType.idFront, DocType.selfieWithId, DocType.poseRight, DocType.poseLeft],
        ),
        if (needsVehicle) ...[
          _cmpBlock(
            '٣) رخصة القيادة',
            [
              _cmpKv('رقم الرخصة المُدخل', v.licenseNumber),
              if (licExp != null) _cmpKv('ينتهي', '${df.format(licExp)}  ${_expiryLabel(licExp)}'),
            ],
            v,
            [DocType.drivingLicense],
          ),
          _cmpBlock(
            '٤) المركبة',
            [
              _cmpKv('رقم اللوحة المُدخل', v.plateNumber),
              _cmpKv('نوع المركبة', _vehicleType()?.value ?? ''),
              if (vlicExp != null) _cmpKv('رخصة المركبة تنتهي', '${df.format(vlicExp)}  ${_expiryLabel(vlicExp)}'),
            ],
            v,
            [DocType.vehicleLicense, DocType.vehiclePhoto],
          ),
        ],
      ],
    );
  }

  Widget _cmpKv(String k, String val, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: T.s(10, T.w900, C.slate500)),
            Text(val.isEmpty ? '—' : val, style: T.s(13, T.w900, color ?? C.slate900)),
          ],
        ),
      );

  Widget _cmpBlock(String title, List<Widget> data, CaptainVerification v, List<DocType> docs) {
    final images = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final t in docs) _miniThumb(v, t)],
    );
    final dataCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: data);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.slate50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: T.s(12, T.w900, C.slate800)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (c, box) => box.maxWidth >= 520
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: dataCol),
                      const SizedBox(width: 12),
                      Expanded(child: images),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [dataCol, const SizedBox(height: 6), images],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniThumb(CaptainVerification v, DocType t) {
    final d = v.currentDoc(t);
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: d == null
                ? Container(
                    decoration: BoxDecoration(color: C.slate100, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('غير مرفوع', style: T.s(10, T.w900, C.rose500))),
                  )
                : GestureDetector(
                    onTap: () => _openFull(d.path, kDocLabels[t]!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: FutureBuilder<Uint8List?>(
                        future: _img(d.path),
                        builder: (c, s) {
                          if (s.connectionState != ConnectionState.done) {
                            return const ColoredBox(
                                color: C.slate100,
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                          }
                          if (s.data == null) {
                            return const ColoredBox(color: C.slate100, child: Center(child: Text('تعذر التحميل')));
                          }
                          return Image.memory(s.data!, fit: BoxFit.cover);
                        },
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 3),
          Text(kDocLabels[t]!, textAlign: TextAlign.center, style: T.s(10, T.w900, C.slate800)),
        ],
      ),
    );
  }

  Widget _vehicleSection(CaptainVerification v) =>
      _docGrid(v, [DocType.drivingLicense, DocType.vehicleLicense, DocType.vehiclePhoto]);

  Widget _declaration(CaptainVerification v) {
    final d = v.declaration;
    if (d == null) return Text('لم يوافق بعد', style: T.s(13, T.w900, C.rose500));
    return Column(
      children: [
        _kv('النسخة', d.termsVersion),
        _kv('وقت الموافقة', intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(d.acceptedAt))),
        _kv('بصمة النص', d.acceptedDocumentHash.length >= 16 ? '${d.acceptedDocumentHash.substring(0, 16)}…' : d.acceptedDocumentHash),
        _kv('مطابق للنص الحالي', d.isCurrent ? 'نعم' : 'لا (نسخة أقدم)', color: d.isCurrent ? null : C.amber500),
      ],
    );
  }

  Widget _audit(CaptainVerification v) => StreamBuilder<List<AuditEvent>>(
        stream: widget.repo.watchAudit(v.captainId),
        builder: (c, s) {
          final list = s.data ?? const <AuditEvent>[];
          if (list.isEmpty) return Text('لا توجد أحداث', style: T.s(12, T.w700, C.slate400));
          return Column(
            children: [
              for (final e in list.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                      '${intl.DateFormat('MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.timestamp))}  ${e.action}'
                      '${e.oldStatus != null ? '  ${e.oldStatus}→${e.newStatus}' : ''}'
                      '${e.reason != null ? '  (${e.reason})' : ''}'
                      '${e.performedBy == 'SYSTEM' ? '  [النظام]' : ''}',
                      style: T.s(11, T.w700, C.slate800)),
                ),
            ],
          );
        },
      );

  Widget _actions(CaptainVerification v) {
    final buttons = <Widget>[];
    Widget b(String t, ReviewDecision d, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : () => _decide(v, d),
              child: Text(t, style: const TextStyle(fontSize: 12)),
            ),
          ),
        );
    switch (v.status) {
      case VerificationStatus.pendingReview:
        buttons.addAll([
          b('اعتماد', ReviewDecision.approve, C.emerald600),
          b('تصحيح', ReviewDecision.needsCorrection, C.amber500),
          b('رفض', ReviewDecision.reject, C.rose500),
        ]);
      case VerificationStatus.verified:
        if (v.renewalPending && v.pendingDocs.isNotEmpty) buttons.add(b('اعتماد التجديد', ReviewDecision.approve, C.emerald600));
        buttons.add(b('تعليق', ReviewDecision.suspend, C.rose500));
      case VerificationStatus.suspended:
        buttons.add(b('إعادة التفعيل', ReviewDecision.reactivate, C.emerald600));
      case VerificationStatus.rejected:
        buttons.add(b('إعادة فتح للتصحيح', ReviewDecision.needsCorrection, C.amber500));
      case VerificationStatus.needsCorrection:
      case VerificationStatus.expired:
      case VerificationStatus.incomplete:
      case VerificationStatus.notStarted:
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        color: C.white,
        padding: const EdgeInsets.all(12),
        child: Row(children: buttons),
      ),
    );
  }
}
