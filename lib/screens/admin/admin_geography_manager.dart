import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app_router.dart';
import '../../config_constants.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';

/// نسخة Flutter من pages/AdminGeographyManager.tsx
class AdminGeographyManager extends StatefulWidget {
  final AppUser user;
  const AdminGeographyManager({super.key, required this.user});

  @override
  State<AdminGeographyManager> createState() => _AdminGeographyManagerState();
}

class _AdminGeographyManagerState extends State<AdminGeographyManager> {
  List<District> _districts = [];
  bool _loading = true;
  String? _selectedDistId;
  final _newVillCtrl = TextEditingController();
  bool _isSubmitting = false;

  String? _editingVillageId;
  final _editLatCtrl = TextEditingController();
  final _editLngCtrl = TextEditingController();
  bool _isUpdatingCoords = false;

  StreamSubscription? _sub;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _sub = db.collection('geo_config').snapshots().listen((snap) async {
      if (snap.docs.isEmpty) {
        if (_seeded) return;
        _seeded = true;
        for (final dist in menofiaData) {
          await db.collection('geo_config').doc(dist.id).set(dist.toMap());
        }
      } else {
        if (!mounted) return;
        setState(() {
          _districts = snap.docs
              .map((d) => District.fromMap(
                  stripFirestore(d.data()) as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _newVillCtrl.dispose();
    _editLatCtrl.dispose();
    _editLngCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAddVillage() async {
    if (_selectedDistId == null || _newVillCtrl.text.trim().isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final newVill = Village(
        id: 'v_${DateTime.now().millisecondsSinceEpoch}',
        name: _newVillCtrl.text.trim(),
        center: const LatLngPoint(30.556, 31.008),
      );
      final dist = _districts.firstWhere((d) => d.id == _selectedDistId);
      final updatedVillages = [...dist.villages, newVill];
      await db.collection('geo_config').doc(_selectedDistId).update(
          {'villages': updatedVillages.map((v) => v.toMap()).toList()});
      _newVillCtrl.clear();
      if (mounted) showAppAlert(context, 'تم إضافة القرية بنجاح لمخطط المنوفية');
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في الإضافة');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleRemoveVillage(String distId, Village village) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('هل أنت متأكد من حذف قرية "${village.name}"؟',
              style: T.s(14, T.w900, C.slate900)),
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
    if (confirmed != true) return;
    try {
      final dist = _districts.firstWhere((d) => d.id == distId);
      final updatedVillages =
          dist.villages.where((v) => v.id != village.id).toList();
      await db.collection('geo_config').doc(distId).update(
          {'villages': updatedVillages.map((v) => v.toMap()).toList()});
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في الحذف');
    }
  }

  void _startEditingCoords(Village v) {
    setState(() {
      _editingVillageId = v.id;
      _editLatCtrl.text = v.center.lat.toString();
      _editLngCtrl.text = v.center.lng.toString();
    });
  }

  Future<void> _handleUpdateCoords(String distId, Village village) async {
    final newLat = double.tryParse(_editLatCtrl.text);
    final newLng = double.tryParse(_editLngCtrl.text);
    if (newLat == null || newLng == null) {
      showAppAlert(context, 'يرجى إدخال أرقام صحيحة للإحداثيات');
      return;
    }
    setState(() => _isUpdatingCoords = true);
    try {
      final dist = _districts.firstWhere((d) => d.id == distId);
      final updatedVillages = dist.villages.map((v) {
        if (v.id == village.id) {
          return Village(
              id: v.id, name: v.name, center: LatLngPoint(newLat, newLng));
        }
        return v;
      }).toList();
      await db.collection('geo_config').doc(distId).update(
          {'villages': updatedVillages.map((v) => v.toMap()).toList()});
      setState(() => _editingVillageId = null);
      if (mounted) showAppAlert(context, 'تم تحديث إحداثيات القرية بنجاح');
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في تحديث الإحداثيات');
    } finally {
      if (mounted) setState(() => _isUpdatingCoords = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bgLight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1152),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: 32),
                _addVillageForm(),
                const SizedBox(height: 32),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: Spinner(size: 48, color: C.rose500)),
                  )
                else
                  _districtsGrid(context),
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
                color: C.rose500,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sh.xl(),
              ),
              child: const Icon(LucideIcons.map, size: 28, color: C.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إدارة النطاق الجغرافي',
                    style: T.s(24, T.w900, C.slate900, letterSpacing: -0.6)),
                Text('توسيع تغطية وصـــلــهــا وتعديل المواقع',
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

  Widget _addVillageForm() {
    final canSubmit = !_isSubmitting &&
        _selectedDistId != null &&
        _newVillCtrl.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: C.slate950,
        borderRadius: BorderRadius.circular(56),
        boxShadow: Sh.xxl(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('إضافة قرية جديدة لمخطط المحافظة',
                  style: T.s(18, T.w900, C.white)),
              const SizedBox(width: 10),
              const Icon(LucideIcons.plusCircle, size: 20, color: C.rose400),
            ],
          ),
          const SizedBox(height: 4),
          Text('سيتم تفعيل القرية فوراً لجميع العملاء والكباتن',
              textAlign: TextAlign.right,
              style: T.s(9, T.w700, C.white.withOpacity(0.4),
                  letterSpacing: 1.2)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: C.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.white.withOpacity(0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDistId,
                isExpanded: true,
                dropdownColor: C.white,
                hint: Text('اختر المركز...',
                    textAlign: TextAlign.right,
                    style: T.s(13, T.w900, C.slate400)),
                alignment: AlignmentDirectional.centerEnd,
                icon: const Icon(LucideIcons.chevronDown,
                    size: 18, color: C.slate400),
                style: T.s(13, T.w900, C.white),
                items: [
                  for (final d in _districts)
                    DropdownMenuItem(
                        value: d.id,
                        child: Text(d.name,
                            textAlign: TextAlign.right,
                            style: T.s(13, T.w900, C.slate900))),
                ],
                onChanged: (v) => setState(() => _selectedDistId = v),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: C.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _newVillCtrl,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: T.s(13, T.w900, C.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'مثال: عزبة فرج الله',
                hintStyle: T.s(13, T.w900, C.slate500),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          PressScale(
            onTap: canSubmit ? _handleAddVillage : null,
            child: Opacity(
              opacity: canSubmit ? 1 : 0.2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.rose500,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: Sh.xl(),
                ),
                child: _isSubmitting
                    ? const Spinner()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.save,
                              size: 20, color: C.white),
                          const SizedBox(width: 12),
                          Text('تأكيد الإضافة للمنظومة',
                              style: T.s(14, T.w900, C.white)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _districtsGrid(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1024 ? 3 : (width >= 640 ? 2 : 1);
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: [
        for (final dist in _districts)
          SizedBox(
            width: (width - 32 - 20 * (cols - 1)) / cols,
            child: _districtCard(dist),
          ),
      ],
    );
  }

  Widget _districtCard(District dist) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: C.rose50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${dist.villages.length} قرية',
                    style: T.s(10, T.w900, C.rose600)),
              ),
              Row(
                children: [
                  Text('مركز ${dist.name}',
                      style: T.s(18, T.w900, C.slate900)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: C.slate50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(LucideIcons.building2,
                        size: 20, color: C.rose500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 384),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final v in dist.villages) _villageRow(dist, v),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _villageRow(District dist, Village v) {
    final isEditing = _editingVillageId == v.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEditing ? C.rose50 : C.slate50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isEditing ? C.rose200 : Colors.transparent),
      ),
      child: isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _editingVillageId = null),
                      child: const Icon(LucideIcons.x,
                          size: 16, color: C.slate400),
                    ),
                    Text('تعديل إحداثيات: ${v.name}',
                        style: T.s(11, T.w900, C.rose600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _coordField('Latitude', _editLatCtrl)),
                    const SizedBox(width: 10),
                    Expanded(child: _coordField('Longitude', _editLngCtrl)),
                  ],
                ),
                const SizedBox(height: 10),
                PressScale(
                  onTap: _isUpdatingCoords
                      ? null
                      : () => _handleUpdateCoords(dist.id, v),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.rose600,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: Sh.lg(),
                    ),
                    child: _isUpdatingCoords
                        ? const Spinner(size: 14)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.check,
                                  size: 12, color: C.white),
                              const SizedBox(width: 6),
                              Text('حفظ الإحداثيات',
                                  style: T.s(10, T.w900, C.white)),
                            ],
                          ),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _startEditingCoords(v),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(LucideIcons.edit2,
                            size: 16, color: C.slate400),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _handleRemoveVillage(dist.id, v),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(LucideIcons.trash2,
                            size: 16, color: C.slate400),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(v.name, style: T.s(12, T.w900, C.slate800)),
                        const SizedBox(height: 2),
                        Opacity(
                          opacity: 0.4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  '${v.center.lat.toStringAsFixed(4)}, ${v.center.lng.toStringAsFixed(4)}',
                                  style: T.s(8, T.w700, C.slate600)),
                              const SizedBox(width: 4),
                              const Icon(LucideIcons.navigation,
                                  size: 10, color: C.slate400),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFDA4AF), shape: BoxShape.circle)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _coordField(String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(label, style: T.s(8, T.w700, C.slate400)),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.rose100),
          ),
          child: TextField(
            controller: c,
            textAlign: TextAlign.center,
            style: T.s(10, T.w900, C.slate900),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(10),
            ),
          ),
        ),
      ],
    );
  }
}
