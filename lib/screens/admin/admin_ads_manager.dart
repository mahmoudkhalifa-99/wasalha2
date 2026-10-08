import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app_router.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../utils.dart' as utils;
import '../../widgets/common.dart';

/// نسخة Flutter من pages/AdminAdsManager.tsx
class AdminAdsManager extends StatefulWidget {
  final AppUser user;
  const AdminAdsManager({super.key, required this.user});

  @override
  State<AdminAdsManager> createState() => _AdminAdsManagerState();
}

class _AdminAdsManagerState extends State<AdminAdsManager> {
  List<Ad> _ads = [];
  bool _isAdding = false;
  String? _editingId;
  bool _loading = false;
  StreamSubscription? _sub;
  final _scrollController = ScrollController();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ctaCtrl = TextEditingController(text: 'استفد من العرض الآن');
  final _whatsappCtrl = TextEditingController();
  String _imageUrl = '';
  // المطعم المربوط بالإعلان (زر "اطلب الآن" بيفتح صفحته) — null = من غير ربط
  String? _restaurantId;
  List<Restaurant> _restaurants = [];
  StreamSubscription? _subRestaurants;
  int _views = 0;
  int _clicks = 0;
  int? _createdAt;

  @override
  void initState() {
    super.initState();
    _subRestaurants =
        db.collection('restaurants').orderBy('name').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _restaurants = snap.docs
            .map((d) => Restaurant.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    }, onError: (e) => debugPrint('restaurants stream: $e'));
    _sub = db.collection('ads').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _ads = snap.docs
            .map((d) => Ad.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subRestaurants?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _ctaCtrl.dispose();
    _whatsappCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelForm() {
    setState(() {
      _isAdding = false;
      _editingId = null;
      _titleCtrl.clear();
      _descCtrl.clear();
      _ctaCtrl.text = 'استفد من العرض الآن';
      _whatsappCtrl.clear();
      _restaurantId = null;
      _imageUrl = '';
      _views = 0;
      _clicks = 0;
      _createdAt = null;
    });
  }

  void _startEdit(Ad ad) {
    setState(() {
      _editingId = ad.id;
      _titleCtrl.text = ad.title;
      _descCtrl.text = ad.description;
      _ctaCtrl.text = ad.ctaText;
      _whatsappCtrl.text = ad.whatsappNumber ?? '';
      _restaurantId = ad.type == 'restaurant' ? ad.targetId : null;
      _imageUrl = ad.imageUrl;
      _views = ad.views;
      _clicks = ad.clicks;
      _createdAt = ad.createdAt;
      _isAdding = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  Future<void> _pickImage() async {
    try {
      const typeGroup =
          XTypeGroup(label: 'images', extensions: ['jpg', 'jpeg', 'png', 'webp']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime =
          file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final compressed = await utils.compressImage('data:$mime;base64,$b64');
      if (mounted) setState(() => _imageUrl = compressed);
    } catch (e) {
      debugPrint('pick image failed: $e');
      if (mounted) await showAppAlert(context, 'تعذر اختيار الصورة، حاول مرة أخرى');
    }
  }

  Future<void> _saveAd() async {
    if (_titleCtrl.text.isEmpty || _imageUrl.isEmpty) {
      showAppAlert(context, 'يرجى ملء العنوان وصورة الإعلان');
      return;
    }
    setState(() => _loading = true);
    try {
      final id = _editingId ?? 'ad_${DateTime.now().millisecondsSinceEpoch}';
      final ad = Ad(
        id: id,
        title: _titleCtrl.text,
        description: _descCtrl.text,
        imageUrl: _imageUrl,
        ctaText: _ctaCtrl.text.isEmpty ? 'استفد من العرض الآن' : _ctaCtrl.text,
        type: _restaurantId != null ? 'restaurant' : 'special_offer',
        targetId: _restaurantId,
        whatsappNumber: _whatsappCtrl.text.replaceAll(RegExp(r'\s'), '').isEmpty
            ? null
            : _whatsappCtrl.text.replaceAll(RegExp(r'\s'), ''),
        isActive: true,
        displayOrder: 0,
        views: _views,
        clicks: _clicks,
        createdAt: _createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      await db.collection('ads').doc(id).set(ad.toMap());
      _cancelForm();
      if (mounted) {
        showAppAlert(context,
            _editingId != null ? 'تم تحديث الإعلان بنجاح' : 'تم نشر الإعلان بنجاح');
      }
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في العملية: تأكد من صغر حجم الصورة المرفوعة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAd(Ad ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('حذف الإعلان؟', style: T.s(16, T.w900, C.slate900)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('تراجع', style: T.s(13, T.w700, C.slate500))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('حذف', style: T.s(13, T.w900, C.rose600))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await db.collection('ads').doc(ad.id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bgLight,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1152),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: 32),
                if (!_isAdding)
                  PressScale(
                    onTap: () => setState(() => _isAdding = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.slate900,
                        borderRadius: BorderRadius.circular(48),
                        boxShadow: Sh.xxl(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.plusCircle,
                              size: 32, color: C.amber400),
                          const SizedBox(width: 16),
                          Text('إضافة إعلان جديد الآن',
                              style: T.s(20, T.w900, C.white)),
                        ],
                      ),
                    ),
                  )
                else
                  _form(),
                const SizedBox(height: 32),
                _adsGrid(context),
              ],
            ),
          ),
        ),
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
                color: C.amber500,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sh.xl(),
              ),
              child: const Icon(LucideIcons.megaphone,
                  size: 28, color: C.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إدارة الإعلانات',
                    style: T.s(24, T.w900, C.slate900, letterSpacing: -0.6)),
                Text('إضافة وتعديل السلايدر العلوي والعروض الخاصة',
                    style: T.s(10, T.w700, C.slate400, letterSpacing: 1.2)),
              ],
            ),
          ],
        ),
        PressScale(
          onTap: () => AppRouter.of(context).go('/'),
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
                Text('رجوع', style: T.s(11, T.w900, C.slate500)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _form() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.amber50, width: 4),
        boxShadow: Sh.xxl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _cancelForm,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.slate100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(LucideIcons.x, size: 20, color: C.slate400),
                ),
              ),
              Text(_editingId != null ? 'تعديل الإعلان الحالي' : 'تصميم إعلان جديد',
                  style: T.s(20, T.w900, C.slate800)),
            ],
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _pickImage,
            child: AspectRatio(
              aspectRatio: 21 / 9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: C.slate50,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                      color: C.amber200, width: 4, style: BorderStyle.solid),
                ),
                child: _imageUrl.isNotEmpty
                    ? Image.memory(base64Decode(_imageUrl.split(',').last),
                        fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.camera,
                              size: 48, color: C.amber200),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text('قياس مثالي 21:9 (عرض السلايدر)',
                                textAlign: TextAlign.center,
                                style: T.s(10, T.w900, C.amber300,
                                    letterSpacing: 1.2)),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _titleCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: T.s(13, T.w900, C.slate900),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'عنوان الإعلان الرئيسي',
                hintStyle: T.s(13, T.w900, C.gray400),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _descCtrl,
              maxLines: null,
              minLines: 4,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: T.s(13, T.w700, C.slate800),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'وصف العرض بالتفصيل...',
                hintStyle: T.s(13, T.w700, C.gray400),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _labeledSmallField('نص زر التحرك', _ctaCtrl)),
              const SizedBox(width: 12),
              Expanded(
                  child: _labeledSmallField('رقم واتساب الطلب', _whatsappCtrl,
                      ltr: true, hint: '2010...')),
            ],
          ),
          const SizedBox(height: 16),
          _restaurantPicker(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: C.amber50,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: C.amber100),
            ),
            child: Column(
              children: [
                Text('الإحصائيات الحالية',
                    style: T.s(10, T.w900, C.amber600, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Icon(LucideIcons.eye,
                            size: 24, color: C.amber500),
                        const SizedBox(height: 4),
                        Text('$_views', style: T.s(18, T.w900, C.slate900)),
                        Text('مشاهدة', style: T.s(8, T.w700, C.slate400)),
                      ],
                    ),
                    Column(
                      children: [
                        const Icon(LucideIcons.mousePointer2,
                            size: 24, color: C.emerald500),
                        const SizedBox(height: 4),
                        Text('$_clicks', style: T.s(18, T.w900, C.slate900)),
                        Text('نقرة', style: T.s(8, T.w700, C.slate400)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _cancelForm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.slate100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text('إلغاء', style: T.s(16, T.w900, C.slate500)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: PressScale(
                  onTap: _loading ? null : _saveAd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.amber500,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: Sh.xl(),
                    ),
                    child: _loading
                        ? const Spinner()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.save,
                                  size: 20, color: C.white),
                              const SizedBox(width: 12),
                              Text(
                                  _editingId != null
                                      ? 'حفظ التعديلات'
                                      : 'نشر الإعلان الآن',
                                  style: T.s(16, T.w900, C.white)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// اختيار مطعم لربط الإعلان بيه: زر "اطلب الآن" في الإعلان بيفتح صفحة المطعم.
  Widget _restaurantPicker() {
    // لو المطعم المربوط اتحذف، نعرض "من غير ربط" بدل ما الـ Dropdown يقع.
    final value = _restaurants.any((r) => r.id == _restaurantId)
        ? _restaurantId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('ربط الإعلان بمطعم (زر اطلب الآن)',
              textAlign: TextAlign.right, style: T.s(10, T.w900, C.slate400)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: C.slate50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: value,
              style: T.s(12, T.w900, C.slate900),
              items: [
                DropdownMenuItem<String?>(
                    value: null,
                    child: Text('من غير ربط بمطعم',
                        style: T.s(12, T.w700, C.slate500))),
                for (final r in _restaurants)
                  DropdownMenuItem<String?>(
                      value: r.id,
                      child: Text(r.name,
                          overflow: TextOverflow.ellipsis,
                          style: T.s(12, T.w900, C.slate900))),
              ],
              onChanged: (v) => setState(() {
                _restaurantId = v;
                if (v != null &&
                    (_ctaCtrl.text.isEmpty ||
                        _ctaCtrl.text == 'استفد من العرض الآن')) {
                  _ctaCtrl.text = 'اطلب الآن';
                }
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labeledSmallField(String label, TextEditingController c,
      {bool ltr = false, String? hint}) {
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: c,
            textAlign: ltr ? TextAlign.left : TextAlign.right,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            style: T.s(12, T.w900, C.slate900),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _adsGrid(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 640 ? 2 : 1);
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: [
        for (final ad in _ads)
          SizedBox(
            width: (width - 32 - 20 * (cols - 1)) / cols,
            child: _adCard(ad),
          ),
      ],
    );
  }

  Widget _adCard(Ad ad) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 21 / 9,
                child: ad.imageUrl.startsWith('data:image')
                    ? Image.memory(base64Decode(ad.imageUrl.split(',').last),
                        fit: BoxFit.cover)
                    : Image.network(ad.imageUrl, fit: BoxFit.cover),
              ),
              if (!ad.isActive)
                Positioned.fill(
                  child: Container(
                    color: C.slate900.withOpacity(0.6),
                    alignment: Alignment.center,
                    child: Text('غير نشط',
                        style: T.s(11, T.w900, C.white, letterSpacing: 1.2)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ad.title,
                    textAlign: TextAlign.right,
                    style: T.s(18, T.w900, C.slate900)),
                const SizedBox(height: 8),
                Text(ad.description,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.s(11, T.w700, C.slate400, height: 1.6)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _startEdit(ad),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.slate50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.edit3,
                                  size: 14, color: C.slate600),
                              const SizedBox(width: 8),
                              Text('تعديل',
                                  style: T.s(11, T.w900, C.slate600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _deleteAd(ad),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: C.rose50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(LucideIcons.trash2,
                            size: 16, color: C.rose500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
