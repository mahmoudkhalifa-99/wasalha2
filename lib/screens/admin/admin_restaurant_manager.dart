import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app_router.dart';
import '../../config_constants.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../utils.dart' as utils;
import '../../widgets/common.dart';

/// نسخة Flutter من pages/AdminRestaurantManager.tsx
class AdminRestaurantManager extends StatefulWidget {
  final AppUser user;
  const AdminRestaurantManager({super.key, required this.user});

  @override
  State<AdminRestaurantManager> createState() => _AdminRestaurantManagerState();
}

class _AdminRestaurantManagerState extends State<AdminRestaurantManager> {
  List<Restaurant> _restaurants = [];
  bool _isAdding = false;
  String? _editingId;
  bool _loading = false;
  final _searchCtrl = TextEditingController();

  District? _selectedDistrict;
  Village? _selectedVillage;

  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController(text: 'مشويات');
  String _photoURL = '';
  String _menuImageURL = '';

  final Map<String, TextEditingController> _itemNameCtrls = {};
  final Map<String, TextEditingController> _itemPriceCtrls = {};
  final Map<String, String> _itemPhotoURLs = {};

  final _scrollController = ScrollController();
  bool _scrollDown = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = db
        .collection('restaurants')
        .orderBy('name')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _restaurants = snap.docs
            .map((d) => Restaurant.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
    });
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      final down = pos.pixels + pos.viewportDimension < pos.maxScrollExtent - 150;
      if (down != _scrollDown) setState(() => _scrollDown = down);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _scrollController.dispose();
    for (final c in _itemNameCtrls.values) c.dispose();
    for (final c in _itemPriceCtrls.values) c.dispose();
    super.dispose();
  }

  TextEditingController _nameCtrlFor(String restId) =>
      _itemNameCtrls.putIfAbsent(restId, () => TextEditingController());
  TextEditingController _priceCtrlFor(String restId) =>
      _itemPriceCtrls.putIfAbsent(restId, () => TextEditingController());

  Future<String?> _pickCompressedImage() async {
    try {
      const typeGroup =
          XTypeGroup(label: 'images', extensions: ['jpg', 'jpeg', 'png', 'webp']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime =
          file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      return await utils.compressImage('data:$mime;base64,$b64');
    } catch (_) {
      return null;
    }
  }

  void _resetForm() {
    _nameCtrl.clear();
    _categoryCtrl.text = 'مشويات';
    _photoURL = '';
    _menuImageURL = '';
    _selectedDistrict = null;
    _selectedVillage = null;
  }

  void _startEdit(Restaurant r) {
    setState(() {
      _editingId = r.id;
      _nameCtrl.text = r.name;
      _categoryCtrl.text = r.category;
      _photoURL = r.photoURL ?? '';
      _menuImageURL = r.menuImageURL ?? '';
      _isAdding = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  Future<void> _saveRestaurant() async {
    if (_nameCtrl.text.isEmpty || _selectedVillage == null) {
      showAppAlert(context, 'يرجى إكمال البيانات');
      return;
    }
    setState(() => _loading = true);
    try {
      final id = _editingId ?? 'rest_${DateTime.now().millisecondsSinceEpoch}';
      Restaurant? existing;
      for (final r in _restaurants) {
        if (r.id == id) existing = r;
      }
      final cleanData = Restaurant(
        id: id,
        name: _nameCtrl.text,
        category: _categoryCtrl.text,
        address: _selectedVillage!.name,
        lat: _selectedVillage!.center.lat,
        lng: _selectedVillage!.center.lng,
        photoURL: _photoURL.isEmpty ? null : _photoURL,
        menuImageURL: _menuImageURL.isEmpty ? null : _menuImageURL,
        menu: existing?.menu ?? [],
        isOpen: existing?.isOpen ?? true,
      ).toMap();

      await db.collection('restaurants').doc(id).set(cleanData);
      setState(() {
        _isAdding = false;
        _editingId = null;
        _resetForm();
      });
      if (mounted) showAppAlert(context, 'تم الحفظ');
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMenuItem(String restId) async {
    final name = _nameCtrlFor(restId).text;
    final price = double.tryParse(_priceCtrlFor(restId).text) ?? 0;
    if (name.isEmpty || price <= 0) return;
    Restaurant? rest;
    for (final r in _restaurants) {
      if (r.id == restId) rest = r;
    }
    if (rest == null) return;
    try {
      final menu = [
        ...rest.menu,
        MenuItem(
            id: 'item_${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            price: price,
            photoURL: _itemPhotoURLs[restId]),
      ];
      await db
          .collection('restaurants')
          .doc(restId)
          .update({'menu': menu.map((e) => e.toMap()).toList()});
      _nameCtrlFor(restId).clear();
      _priceCtrlFor(restId).clear();
      setState(() => _itemPhotoURLs.remove(restId));
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ');
    }
  }

  Future<void> _deleteMenuItem(Restaurant rest, MenuItem item) async {
    final menu = rest.menu.where((i) => i.id != item.id).toList();
    await db
        .collection('restaurants')
        .doc(rest.id)
        .update({'menu': menu.map((e) => e.toMap()).toList()});
  }

  Future<void> _deleteRestaurant(Restaurant r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('حذف؟', style: T.s(16, T.w900, C.slate900)),
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
      await db.collection('restaurants').doc(r.id).delete();
    }
  }

  List<Restaurant> get _filtered =>
      _restaurants.where((r) => r.name.contains(_searchCtrl.text)).toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bgLight,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 160),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1152),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 32),
                    _searchAndAddBar(),
                    if (_isAdding) ...[
                      const SizedBox(height: 24),
                      _addEditForm(),
                    ],
                    const SizedBox(height: 32),
                    _restaurantsGrid(context),
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
                color: C.emerald600,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sh.xl(),
              ),
              child: const Icon(LucideIcons.store, size: 28, color: C.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إدارة المطاعم',
                    style: T.s(24, T.w900, C.slate900, letterSpacing: -0.6)),
                Text('تعديل الوجبات والقوائم',
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

  Widget _searchAndAddBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: C.slate50),
        boxShadow: Sh.sm(),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 320,
            child: Container(
              decoration: BoxDecoration(
                color: C.slate50,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _searchCtrl,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: T.s(12, T.w900, C.slate800),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(LucideIcons.search, size: 18, color: C.slate300),
                  ),
                  hintText: 'بحث...',
                  hintStyle: T.s(12, T.w900, C.gray400),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          if (!_isAdding)
            PressScale(
              onTap: () => setState(() => _isAdding = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: C.slate900,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.plusCircle,
                        size: 16, color: C.white),
                    const SizedBox(width: 10),
                    Text('إضافة مطعم', style: T.s(11, T.w900, C.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addEditForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.emerald50, width: 4),
        boxShadow: Sh.xxl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _isAdding = false;
                  _editingId = null;
                  _resetForm();
                }),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.slate100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(LucideIcons.x, size: 20, color: C.slate400),
                ),
              ),
              Text(_editingId != null ? 'تعديل مطعم' : 'مطعم جديد',
                  style: T.s(20, T.w900, C.slate800)),
            ],
          ),
          const SizedBox(height: 24),
          _imagePickerRow(),
          const SizedBox(height: 16),
          _plainField(_nameCtrl, 'اسم المطعم'),
          const SizedBox(height: 12),
          _plainField(_categoryCtrl, 'التصنيف'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _districtVillageDropdown(
                  placeholder: 'اختر المركز',
                  value: _selectedDistrict?.name,
                  options: menofiaData.map((d) => d.name).toList(),
                  onSelect: (name) => setState(() {
                    _selectedDistrict =
                        menofiaData.firstWhere((d) => d.name == name);
                    _selectedVillage = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _districtVillageDropdown(
                  placeholder: 'اختر القرية',
                  value: _selectedVillage?.name,
                  enabled: _selectedDistrict != null,
                  options:
                      _selectedDistrict?.villages.map((v) => v.name).toList() ??
                          [],
                  onSelect: (name) => setState(() {
                    _selectedVillage = _selectedDistrict!.villages
                        .firstWhere((v) => v.name == name);
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PressScale(
            onTap: _loading ? null : _saveRestaurant,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.emerald600,
                borderRadius: BorderRadius.circular(32),
              ),
              child: _loading
                  ? const Spinner()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.save, size: 20, color: C.white),
                        const SizedBox(width: 12),
                        Text('حفظ', style: T.s(16, T.w900, C.white)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePickerRow() {
    Widget tile(String label, String url, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 100,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: C.slate50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.slate100),
            ),
            child: url.isNotEmpty
                ? Image.memory(base64Decode(url.split(',').last),
                    fit: BoxFit.cover)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.camera,
                          size: 20, color: C.slate300),
                      const SizedBox(height: 4),
                      Text(label, style: T.s(9, T.w700, C.slate400)),
                    ],
                  ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('صورة المطعم', _photoURL, () async {
          final img = await _pickCompressedImage();
          if (img != null) setState(() => _photoURL = img);
        }),
        const SizedBox(width: 12),
        tile('صورة المنيو', _menuImageURL, () async {
          final img = await _pickCompressedImage();
          if (img != null) setState(() => _menuImageURL = img);
        }),
      ],
    );
  }

  Widget _plainField(TextEditingController c, String hint) {
    return Container(
      decoration: BoxDecoration(
        color: C.slate50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: c,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        style: T.s(13, T.w900, C.slate900),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: T.s(13, T.w900, C.gray400),
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _districtVillageDropdown({
    required String placeholder,
    required String? value,
    required List<String> options,
    required void Function(String) onSelect,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: C.slate50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(placeholder,
                textAlign: TextAlign.right,
                style: T.s(13, T.w900, C.gray400)),
            alignment: AlignmentDirectional.centerEnd,
            icon: const Icon(LucideIcons.chevronDown,
                size: 18, color: C.slate300),
            style: T.s(13, T.w900, C.slate900),
            items: [
              for (final o in options)
                DropdownMenuItem(
                    value: o, child: Text(o, textAlign: TextAlign.right)),
            ],
            onChanged: enabled
                ? (v) {
                    if (v != null) onSelect(v);
                  }
                : null,
          ),
        ),
      ),
    );
  }

  Widget _restaurantsGrid(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 2 : 1;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final r in _filtered)
          SizedBox(
            width: cols == 2 ? (width - 32 - 16) / 2 : width - 32,
            child: _restaurantCard(r),
          ),
      ],
    );
  }

  Widget _restaurantCard(Restaurant r) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.slate100),
        boxShadow: Sh.xl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PressScale(
                    scale: 0.9,
                    onTap: () => _deleteRestaurant(r),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: C.rose50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(LucideIcons.trash2,
                          size: 18, color: C.rose500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressScale(
                    onTap: () => _startEdit(r),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: C.slate50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(LucideIcons.edit3,
                          size: 18, color: C.slate400),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(r.name,
                        overflow: TextOverflow.ellipsis,
                        style: T.s(20, T.w900, C.slate950)),
                    Text(r.category,
                        style: T.s(10, T.w700, C.slate400)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: C.slate900,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: (r.photoURL != null)
                    ? SmartImage(r.photoURL, fit: BoxFit.cover)
                    : const Icon(LucideIcons.building2,
                        size: 32, color: Color(0xFF34D399)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 256),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in r.menu)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: C.slate50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _deleteMenuItem(r, item),
                            child: const Icon(LucideIcons.x,
                                size: 16, color: Color(0xFFFDA4AF)),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(item.name,
                                  style: T.s(13, T.w900, C.slate800)),
                              const SizedBox(width: 10),
                              Text('${item.price.toInt()} ج.م',
                                  style: T.s(10, T.w700, C.emerald600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: C.slate950,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: C.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    controller: _nameCtrlFor(r.id),
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: T.s(11, T.w700, C.white),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'اسم الوجبة',
                      hintStyle: T.s(11, T.w700, C.slate500),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: C.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: C.white.withOpacity(0.1)),
                        ),
                        child: TextField(
                          controller: _priceCtrlFor(r.id),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: T.s(11, T.w700, C.white),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'السعر',
                            hintStyle: T.s(11, T.w700, C.slate500),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _addMenuItem(r.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.emerald600,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('إضافة',
                            style: T.s(11, T.w900, C.white)),
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
