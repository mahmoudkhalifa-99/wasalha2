import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/common.dart';
import '../widgets/delete_account_dialog.dart';

/// نسخة Flutter من pages/ProfileView.tsx
class ProfileView extends StatefulWidget {
  final AppUser user;
  final void Function(AppUser) onUpdate;
  final VoidCallback onBack;
  final VoidCallback? onOpenWallet;
  const ProfileView({
    super.key,
    required this.user,
    required this.onUpdate,
    required this.onBack,
    this.onOpenWallet,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  bool _isEditing = false;
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.user.name);
  late final TextEditingController _phoneCtrl =
      TextEditingController(text: widget.user.phone);
  bool _isSaving = false;
  bool _isUploading = false;
  bool _showLogoutConfirm = false;
  String? _photoOverride;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleUpdateProfile() async {
    if (_nameCtrl.text.trim().isEmpty || !isValidPhone(_phoneCtrl.text)) {
      showAppAlert(context, 'يرجى التأكد من الاسم ورقم هاتف صحيح (010, 011, 012, 015)');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await db.collection('users').doc(widget.user.id).update({
        'name': _nameCtrl.text,
        'phone': _phoneCtrl.text,
      });
      setState(() => _isEditing = false);
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في التحديث');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleImageChange() async {
    try {
      const typeGroup =
          XTypeGroup(label: 'images', extensions: ['jpg', 'jpeg', 'png', 'webp']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      setState(() => _isUploading = true);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime =
          file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final dataUrl = 'data:$mime;base64,$b64';
      await db.collection('users').doc(widget.user.id).update({'photoURL': dataUrl});
      if (mounted) setState(() => _photoOverride = dataUrl);
    } catch (e) {
      if (mounted) showAppAlert(context, 'فشل في حفظ الصورة');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleLogout() async {
    try {
      setState(() => _showLogoutConfirm = false);
      await auth.signOut();
      // App shell بيسمع authStateChanges ويرجع تلقائياً لشاشة الدخول
      // (نفس أثر window.location.reload() في نسخة الويب).
    } catch (error) {
      debugPrint('Logout error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final photo = _photoOverride ?? user.photoURL;

    return Stack(
      children: [
        Container(
          color: C.slate50,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 672),
                child: Padding(
                  padding: const EdgeInsets.all(20),
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
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: C.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: C.slate200.withOpacity(0.7)),
                                boxShadow: Sh.sm(),
                              ),
                              child: const Icon(LucideIcons.chevronRight,
                                  size: 20, color: C.slate700),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('حسابي الشخصي',
                                  style: T.s(24, T.w900, C.slate900,
                                      letterSpacing: -0.5)),
                              const SizedBox(height: 2),
                              Text('إدارة بيانات حسابك وتفاصيل محفظتك',
                                  style: T.s(11, T.w500, C.slate500)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _heroCard(photo),
                      const SizedBox(height: 16),
                      if (widget.onOpenWallet != null) ...[
                        _walletButton(),
                        const SizedBox(height: 16),
                      ],
                      _basicInfoCard(),
                      const SizedBox(height: 16),
                      _logoutButton(),
                      const SizedBox(height: 12),
                      _deleteAccountButton(),
                      const SizedBox(height: 24),
                      Column(
                        children: [
                          Text('تطبيق وصلها • محافظة المنوفية',
                              style: T.s(11, T.w700, C.slate400)),
                          const SizedBox(height: 4),
                          Text('الإصدار الذكي 2.0 • كل الحقوق محفوظة',
                              style: T.s(9, T.w400, C.slate400)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showLogoutConfirm) _logoutModal(),
      ],
    );
  }

  Widget _heroCard(String? photo) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.emerald600, C.teal700, C.slate900],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: Sh.xl(),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              top: -80, right: -80,
              child: Blob(size: 256, color: C.white.withOpacity(0.10))),
          Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: C.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: C.white.withOpacity(0.3), width: 4),
                      boxShadow: Sh.xl(),
                    ),
                    child: Stack(
                      children: [
                        if (photo != null)
                          Positioned.fill(
                            child: photo.startsWith('data:image')
                                ? Image.memory(
                                    base64Decode(photo.split(',').last),
                                    fit: BoxFit.cover)
                                : SmartImage(photo, fit: BoxFit.cover),
                          )
                        else
                          Center(
                            child: Text(
                                user_firstChar(widget.user.name),
                                style: T.s(36, T.w900, C.white)),
                          ),
                        if (_isUploading)
                          Positioned.fill(
                            child: Container(
                              color: C.black.withOpacity(0.4),
                              child: const Center(child: Spinner(size: 32)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: -4,
                    child: PressScale(
                      scale: 0.75,
                      onTap: _handleImageChange,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: C.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: C.emerald600, width: 2),
                          boxShadow: Sh.lg(),
                        ),
                        child: const Icon(LucideIcons.camera,
                            size: 16, color: C.emerald700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(widget.user.name,
                  textAlign: TextAlign.center,
                  style: T.s(24, T.w900, C.white, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(widget.user.phone,
                    style: T.s(11, T.w700, C.white.withOpacity(0.8))),
              ),
              if (widget.user.status == UserStatus.approved) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: C.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('حساب معتمد وموثق',
                          style: T.s(11, T.w700, C.emerald100)),
                      const SizedBox(width: 6),
                      const Icon(LucideIcons.shieldCheck,
                          size: 16, color: C.emerald300),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletButton() {
    return PressScale(
      scale: 0.99,
      onTap: widget.onOpenWallet,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: C.slate900,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.slate800),
          boxShadow: Sh.md(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: C.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('إدارة', style: T.s(11, T.w700, C.emerald400)),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronLeft,
                      size: 16, color: C.emerald400),
                ],
              ),
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('رصيد المحفظة',
                        style: T.s(11, T.w700, C.emerald400)),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('ج.م',
                            style: T.s(11, T.w700,
                                C.white.withOpacity(0.6))),
                        const SizedBox(width: 4),
                        Text(widget.user.wallet.balance.toStringAsFixed(2),
                            style: T.s(24, T.w900, C.white)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [C.emerald600, C.emerald700]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Sh.md(color: C.emerald900.withOpacity(0.4)),
                  ),
                  child: const Icon(LucideIcons.wallet,
                      size: 24, color: C.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _basicInfoCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.slate200.withOpacity(0.6)),
        boxShadow: Sh.sm(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PressScale(
                onTap: _isSaving
                    ? null
                    : (_isEditing ? _handleUpdateProfile : () => setState(() => _isEditing = true)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isEditing ? C.emerald600 : C.slate100,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _isEditing ? Sh.md() : null,
                  ),
                  child: _isSaving
                      ? const Spinner(size: 16, color: C.white)
                      : Text(_isEditing ? 'حفظ التعديلات' : 'تعديل البيانات',
                          style: T.s(11, T.w700,
                              _isEditing ? C.white : C.slate700)),
                ),
              ),
              Row(
                children: [
                  Text('البيانات الأساسية',
                      style: T.s(15, T.w800, C.slate900)),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.edit3,
                      size: 20, color: C.emerald600),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _field('الاسم الكامل', _nameCtrl, ltr: false),
          const SizedBox(height: 16),
          _field('رقم الهاتف المسجل', _phoneCtrl,
              ltr: true, maxLength: 11),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {required bool ltr, int? maxLength}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(label, style: T.s(11, T.w700, C.slate600)),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _isEditing ? C.white : C.slate50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _isEditing
                    ? C.emerald500
                    : C.slate200.withOpacity(0.8),
                width: _isEditing ? 2 : 1),
          ),
          child: TextField(
            controller: c,
            enabled: _isEditing,
            maxLength: maxLength,
            textAlign: ltr ? TextAlign.left : TextAlign.right,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            style: T.s(13, T.w700, C.slate800),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _logoutButton() {
    return PressScale(
      scale: 0.99,
      onTap: () => setState(() => _showLogoutConfirm = true),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: C.rose50.withOpacity(0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.rose200.withOpacity(0.7)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(LucideIcons.chevronRight,
                size: 20, color: C.rose400),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('تسجيل الخروج',
                        style: T.s(15, T.w800, C.rose700)),
                    const SizedBox(height: 2),
                    Text('الخروج بأمان من هذا الجهاز',
                        style: T.s(11, T.w500, C.rose500.withOpacity(0.8))),
                  ],
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Sh.sm(),
                  ),
                  child: const Icon(LucideIcons.logOut,
                      size: 20, color: C.rose600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _deleteAccountButton() {
    return PressScale(
      scale: 0.99,
      onTap: () => showDeleteAccountDialog(context, widget.user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: C.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.rose200.withOpacity(0.7)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.trash2, size: 18, color: C.rose600),
            const SizedBox(width: 10),
            Text('حذف حسابي نهائياً', style: T.s(14, T.w800, C.rose600)),
          ],
        ),
      ),
    );
  }

  Widget _logoutModal() {
    return Positioned.fill(
      child: GlassBox(
        sigma: 12,
        color: C.slate950.withOpacity(0.6),
        borderRadius: BorderRadius.zero,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: C.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: C.slate100),
                    boxShadow: Sh.xxl(),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: C.rose50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Transform.rotate(
                          angle: 3.14159265,
                          child: const Icon(LucideIcons.logOut,
                              size: 36, color: C.rose600),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('تأكيد الخروج',
                          style: T.s(24, T.w900, C.slate900)),
                      const SizedBox(height: 4),
                      Text('هل تريد حقاً تسجيل الخروج من حسابك في وصلها؟',
                          textAlign: TextAlign.center,
                          style: T.s(11, T.w500, C.slate500)),
                      const SizedBox(height: 20),
                      PressScale(
                        onTap: _handleLogout,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.rose600,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: Sh.md(),
                          ),
                          child: Text('نعم، تسجيل الخروج',
                              style: T.s(14, T.w700, C.white)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PressScale(
                        onTap: () => setState(() => _showLogoutConfirm = false),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.slate100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('إلغاء والتراجع',
                              style: T.s(14, T.w700, C.slate700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String user_firstChar(String name) =>
    name.isNotEmpty ? name.substring(0, 1) : 'ع';
