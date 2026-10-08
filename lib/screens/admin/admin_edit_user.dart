import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app_router.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';

/// نسخة Flutter من pages/AdminEditUser.tsx
class AdminEditUser extends StatefulWidget {
  final String userId;
  const AdminEditUser({super.key, required this.userId});

  @override
  State<AdminEditUser> createState() => _AdminEditUserState();
}

class _AdminEditUserState extends State<AdminEditUser> {
  AppUser? _targetUser;
  bool _loading = true;
  bool _isSaving = false;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _sendingReset = false;

  bool get _originallySuspended =>
      _targetUser?.status == UserStatus.suspended;

  /// التعطيل: للمدير بس، ومش للمديرين التانيين ولا لحسابه هو.
  bool get _canSuspend =>
      _targetUser != null &&
      _targetUser!.role != UserRole.admin &&
      widget.userId != auth.currentUser?.uid;
  final _balanceCtrl = TextEditingController(text: '0');
  UserRole _role = UserRole.customer;
  UserStatus _status = UserStatus.approved;
  VehicleType _vehicleType = VehicleType.toktok;

  final _scrollController = ScrollController();
  bool _scrollDown = true;

  final _profileKey = GlobalKey();
  final _authKey = GlobalKey();
  final _vehicleKey = GlobalKey();
  final _walletKey = GlobalKey();
  final _statusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchUser();
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      final down = pos.pixels + pos.viewportDimension < pos.maxScrollExtent - 150;
      if (down != _scrollDown) setState(() => _scrollDown = down);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _balanceCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUser() async {
    try {
      final snap = await db.collection('users').doc(widget.userId).get();
      if (snap.exists) {
        final u = AppUser.fromMap(
            stripFirestore(snap.data()) as Map<String, dynamic>, snap.id);
        setState(() {
          _targetUser = u;
          _nameCtrl.text = u.name;
          _phoneCtrl.text = u.phone;
          _emailCtrl.text = u.email;
          _role = u.role;
          _status = u.status;
          _vehicleType = u.vehicleType ?? VehicleType.toktok;
          _balanceCtrl.text = u.wallet.balance.toStringAsFixed(2);
        });
      }
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في تحميل بيانات المستخدم');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  /// تغيير كلمة المرور الحقيقي يتم عبر رابط إعادة تعيين من Firebase Auth
  /// (مفيش تخزين لكلمات المرور في Firestore).
  Future<void> _sendResetEmail() async {
    final email = _emailCtrl.text.trim();
    if (_sendingReset) return;
    if (!email.contains('@')) {
      await showAppAlert(context, 'البريد الإلكتروني غير صحيح');
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        await showAppAlert(
            context, 'تم إرسال رابط إعادة تعيين كلمة المرور إلى $email');
      }
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, 'تعذر إرسال الرابط: ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _handleUpdate() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final updates = <String, dynamic>{
        'name': _nameCtrl.text,
        'phone': _phoneCtrl.text,
        'email': _emailCtrl.text,
        'role': _role.value,
      };
      // السوبر أدمن يقدر يعطّل ويرجّع تفعيل أي حساب
      updates['status'] = _status.value;
      // تنظيف أي كلمة مرور قديمة مخزنة كنص في وثيقة المستخدم
      updates['password'] = FieldValue.delete();
      if (_role == UserRole.driver) {
        updates['vehicleType'] = _vehicleType.value;
      }
      final balance = double.tryParse(_balanceCtrl.text) ?? 0;
      updates['wallet'] = {
        'balance': balance,
        'totalEarnings': _targetUser?.wallet.totalEarnings ?? 0,
        'withdrawn': _targetUser?.wallet.withdrawn ?? 0,
      };

      await db.collection('users').doc(widget.userId).update(updates);
      if (mounted) {
        await showAppAlert(context, 'تم حفظ كافة التعديلات الشاملة بنجاح');
        if (mounted) AppRouter.of(context).go('/admin/users');
      }
    } catch (e) {
      if (mounted) {
        showAppAlert(context, 'فشل حفظ التعديلات، يرجى التحقق من الاتصال');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Spinner(size: 48, color: C.emerald500)));
    }
    if (_targetUser == null) {
      return Center(
          child: Text('المستخدم غير موجود',
              style: T.s(14, T.w900, C.slate400)));
    }

    return Container(
      color: C.bgLight,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 160),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 896),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 20),
                    _quickNav(),
                    const SizedBox(height: 32),
                    _profileSection(),
                    const SizedBox(height: 32),
                    _authSection(),
                    if (_role == UserRole.driver) ...[
                      const SizedBox(height: 32),
                      _vehicleSection(),
                    ],
                    const SizedBox(height: 32),
                    _walletSection(),
                    const SizedBox(height: 32),
                    _statusSection(),
                    const SizedBox(height: 32),
                    _saveButton(),
                    const SizedBox(height: 48),
                    _securityNote(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 40,
            child: PressScale(
              onTap: () {
                if (_scrollDown) {
                  _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                } else {
                  _scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.slate900,
                  shape: BoxShape.circle,
                  border: Border.all(color: C.white, width: 4),
                  boxShadow: Sh.xxl(),
                ),
                child: Icon(
                    _scrollDown ? LucideIcons.arrowDown : LucideIcons.arrowUp,
                    size: 24,
                    color: C.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.slate900,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sh.xl(),
              ),
              child: const Icon(LucideIcons.shield,
                  size: 32, color: Color(0xFF34D399)),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('التعديل الشامل للعضو',
                    style: T.s(24, T.w900, C.slate900, letterSpacing: -0.6)),
                Text('تعديل كامل: ${_targetUser!.name}',
                    style: T.s(10, T.w700, C.slate400, letterSpacing: 1.2)),
              ],
            ),
          ],
        ),
        PressScale(
          onTap: () => AppRouter.of(context).go('/admin/users'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.slate100),
              boxShadow: Sh.sm(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.arrowRight, size: 20, color: C.slate400),
                const SizedBox(width: 8),
                Text('رجوع للقائمة', style: T.s(11, T.w900, C.slate500)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickNav() {
    final items = [
      ('البيانات الشخصية', _profileKey),
      ('الأمان والدخول', _authKey),
      if (_role == UserRole.driver) ('المركبة', _vehicleKey),
      ('المحفظة', _walletKey),
      ('الحالة والصلاحية', _statusKey),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.sm(),
      ),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => _scrollTo(item.$2),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.slate50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(item.$1, style: T.s(10, T.w900, C.slate500)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required Key key,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    bool dark = false,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: dark ? C.slate900 : C.white,
        borderRadius: BorderRadius.circular(56),
        border: dark ? null : Border.all(color: C.slate100),
        boxShadow: Sh.xl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title,
                  style: T.s(18, T.w900, dark ? C.white : C.slate800)),
              const SizedBox(width: 10),
              Icon(icon, size: 20, color: iconColor),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController c,
      {bool ltr = false, IconData? icon, Color focusColor = C.emerald500}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(label,
              textAlign: TextAlign.right, style: T.s(10, T.w900, C.slate400)),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: C.slate50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: c,
            textAlign: ltr ? TextAlign.left : TextAlign.right,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            style: T.s(13, T.w900, C.slate900),
            decoration: InputDecoration(
              border: InputBorder.none,
              prefixIcon: icon != null && !ltr
                  ? null
                  : (icon != null
                      ? Icon(icon, size: 16, color: C.slate300)
                      : null),
              suffixIcon: icon != null && !ltr
                  ? Icon(icon, size: 16, color: C.slate300)
                  : null,
              contentPadding: const EdgeInsets.all(18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileSection() {
    return _sectionCard(
      key: _profileKey,
      title: 'المعلومات الشخصية',
      icon: LucideIcons.user,
      iconColor: C.emerald500,
      child: LayoutBuilder(builder: (context, box) {
        final twoCol = box.maxWidth >= 500;
        final name = _labeledField('الاسم الرباعي', _nameCtrl);
        final phone = _labeledField('رقم الهاتف', _phoneCtrl, ltr: true);
        return twoCol
            ? Row(children: [
                Expanded(child: name),
                const SizedBox(width: 16),
                Expanded(child: phone)
              ])
            : Column(children: [name, const SizedBox(height: 16), phone]);
      }),
    );
  }

  Widget _authSection() {
    return _sectionCard(
      key: _authKey,
      title: 'بيانات الدخول والحماية',
      icon: LucideIcons.lock,
      iconColor: C.indigo500,
      child: LayoutBuilder(builder: (context, box) {
        final twoCol = box.maxWidth >= 500;
        final email = _labeledField('البريد الإلكتروني', _emailCtrl,
            ltr: true, icon: LucideIcons.mail);
        final password = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('كلمة المرور', style: T.s(10, T.w800, C.slate500)),
            const SizedBox(height: 6),
            PressScale(
              scale: 0.97,
              onTap: _sendingReset ? null : _sendResetEmail,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: C.slate50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.slate200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.mail, size: 16, color: C.indigo500),
                    const SizedBox(width: 8),
                    Text(
                        _sendingReset
                            ? 'جارٍ الإرسال...'
                            : 'إرسال رابط إعادة تعيين كلمة المرور',
                        style: T.s(11, T.w800, C.slate700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('سيصل المستخدم رابط على بريده لتعيين كلمة مرور جديدة.',
                  style: T.s(8, T.w700, C.slate400)),
            ),
          ],
        );
        return twoCol
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: email),
                const SizedBox(width: 16),
                Expanded(child: password)
              ])
            : Column(
                children: [email, const SizedBox(height: 16), password]);
      }),
    );
  }

  Widget _vehicleSection() {
    final items = [
      (VehicleType.toktok, 'توك توك', LucideIcons.zap),
      (VehicleType.motorcycle, 'موتوسيكل', LucideIcons.bike),
      (VehicleType.car, 'سيارة', LucideIcons.car),
    ];
    return _sectionCard(
      key: _vehicleKey,
      title: 'تفاصيل المركبة',
      icon: LucideIcons.car,
      iconColor: C.emerald400,
      dark: true,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: Builder(builder: (context) {
              final v = items[i];
              final active = _vehicleType == v.$1;
              return GestureDetector(
                onTap: () => setState(() => _vehicleType = v.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: active ? C.emerald500 : C.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: active ? C.white : Colors.transparent,
                        width: 3),
                  ),
                  child: Column(
                    children: [
                      Icon(v.$3,
                          size: 20,
                          color: active ? C.white : C.slate400),
                      const SizedBox(height: 6),
                      Text(v.$2,
                          style: T.s(10, T.w900,
                              active ? C.white : C.slate400)),
                    ],
                  ),
                ),
              );
            })),
          ],
        ],
      ),
    );
  }

  Widget _walletSection() {
    return _sectionCard(
      key: _walletKey,
      title: 'إدارة الرصيد',
      icon: LucideIcons.creditCard,
      iconColor: C.emerald500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('تعديل رصيد المحفظة الحالي (ج.م)',
                textAlign: TextAlign.right, style: T.s(10, T.w900, C.slate400)),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _balanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              textAlign: TextAlign.center,
              style: T.s(40, T.w900, C.slate900),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusSection() {
    return _sectionCard(
      key: _statusKey,
      title: 'الصلاحيات وحالة التفعيل',
      icon: LucideIcons.settings,
      iconColor: C.slate400,
      child: LayoutBuilder(builder: (context, box) {
        final twoCol = box.maxWidth >= 500;
        final roleField = _dropdownField<UserRole>(
          label: 'رتبة العضو',
          value: _role,
          items: const {
            UserRole.customer: 'عميل (Customer)',
            UserRole.driver: 'كابتن (Driver)',
            UserRole.operator: 'مشغل (Operator)',
            UserRole.admin: 'مدير (Admin)',
          },
          onChanged: (v) => setState(() => _role = v),
        );
        final Widget statusField = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropdownField<UserStatus>(
              label: 'حالة الحساب (Activation)',
              value: _status,
              items: {
                UserStatus.approved: 'مفعل (نشط الآن)',
                if (_canSuspend || _originallySuspended)
                  UserStatus.suspended: 'معطّل',
              },
              onChanged: (v) => setState(() => _status = v),
            ),
            if (_status == UserStatus.suspended && !_originallySuspended)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Text(
                    'تنبيه: لو عطّلت الحساب، المستخدم مش هيقدر يدخل التطبيق لحد ما تفعّله تاني.',
                    style: T.s(9, T.w800, C.rose500)),
              ),
            if (_originallySuspended && _status == UserStatus.approved)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Text(
                    'الحساب هيتفعّل بعد الضغط على "حفظ التعديلات الشاملة".',
                    style: T.s(9, T.w800, C.emerald600)),
              ),
          ],
        );
        return twoCol
            ? Row(children: [
                Expanded(child: roleField),
                const SizedBox(width: 16),
                Expanded(child: statusField)
              ])
            : Column(children: [
                roleField,
                const SizedBox(height: 16),
                statusField
              ]);
      }),
    );
  }

  Widget _dropdownField<V>({
    required String label,
    required V value,
    required Map<V, String> items,
    required void Function(V) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(label,
              textAlign: TextAlign.right, style: T.s(10, T.w900, C.slate400)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: C.slate50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<V>(
              value: value,
              isExpanded: true,
              alignment: AlignmentDirectional.centerEnd,
              icon: const Icon(LucideIcons.chevronDown,
                  size: 18, color: C.slate300),
              style: T.s(13, T.w900, C.slate900),
              items: [
                for (final e in items.entries)
                  DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, textAlign: TextAlign.right)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _saveButton() {
    return PressScale(
      onTap: _isSaving ? null : _handleUpdate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.emerald600,
          borderRadius: BorderRadius.circular(40),
          boxShadow: Sh.xxl(),
        ),
        child: _isSaving
            ? const Spinner(size: 32)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.save, size: 32, color: C.white),
                  const SizedBox(width: 16),
                  Text('حفظ التعديلات الشاملة',
                      style: T.s(24, T.w900, C.white)),
                ],
              ),
      ),
    );
  }

  Widget _securityNote() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.amber50,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
            color: C.amber200, width: 2, style: BorderStyle.solid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('تنبيه أمان للمسؤول',
                    style: T.s(13, T.w900, C.amber800)),
                const SizedBox(height: 4),
                Text(
                    'تغيير البريد الإلكتروني أو الهاتف قد يؤثر على تجربة دخول العضو. يرجى التأكد من صحة البيانات وتزويد العضو بالباسورد الجديد إذا قمت بتغييره.',
                    textAlign: TextAlign.right,
                    style: T.s(11, T.w700, const Color(0xFFB45309),
                        height: 1.6)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.amber500,
              borderRadius: BorderRadius.circular(16),
              boxShadow: Sh.lg(),
            ),
            child: const Icon(LucideIcons.alertTriangle,
                size: 24, color: C.white),
          ),
        ],
      ),
    );
  }
}
