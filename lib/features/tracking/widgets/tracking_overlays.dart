import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/map/geo_utils.dart';
import '../../../core/map/map_config.dart';
import '../../../theme/app_colors.dart';
import '../controllers/location_picker_controller.dart';

/// عناصر الواجهة العايمة فوق الخريطة (Floating): الشريط العلوي، الأزرار،
/// الدبوس الثابت، كارت اختيار الموقع، والـ attribution.

const _shadow = [
  BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4)),
];

/// شريط علوي عايم: رجوع/إغلاق + عنوان + سطر حالة + زر اختياري.
class TrackingTopBar extends StatelessWidget {
  const TrackingTopBar({
    super.key,
    required this.title,
    this.status,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? status;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: _shadow,
      ),
      child: Row(
        children: [
          if (leading != null) leading!,
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: C.slate800)),
                if (status != null) ...[const SizedBox(height: 2), status!],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// زر دائري عايم (موقعي، عرض الكل، رجوع…).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.filled = false,
    this.size = 46,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: filled ? C.emerald600 : C.white,
          elevation: 4,
          shadowColor: const Color(0x44000000),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: 22, color: filled ? C.white : C.slate800),
            ),
          ),
        ),
      ),
    );
  }
}

/// الدبوس الثابت في منتصف الشاشة (الخريطة هي اللي بتتحرك تحته).
/// سن الدبوس بيقع على مركز الخريطة بالظبط. IgnorePointer عشان ما يمنعش اللمس.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key});

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // ظل صغير عند نقطة المركز.
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0x44000000),
                shape: BoxShape.circle,
              ),
            ),
            // الدبوس فوق المركز: سنّه عند المركز.
            const Padding(
              padding: EdgeInsets.only(bottom: _size),
              child: Icon(
                Icons.location_on_rounded,
                size: _size,
                color: C.rose600,
                shadows: [
                  Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// كارت اختيار الموقع (أسفل الشاشة في وضع الاختيار).
class PickLocationCard extends StatelessWidget {
  const PickLocationCard({
    super.key,
    required this.picker,
    required this.onConfirm,
  });

  final LocationPickerController picker;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<PickState>(
          valueListenable: picker.state,
          builder: (context, s, _) {
            final String address;
            switch (s.phase) {
              case PickPhase.idle:
              case PickPhase.moving:
                address = 'حرّك الخريطة لتحديد الموقع';
              case PickPhase.resolving:
                address = 'جاري تحديد العنوان…';
              case PickPhase.resolved:
                address = s.address ?? LocationPickerController.fallbackAddress;
            }
            final dist = s.distanceFromOriginMeters;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: C.rose600, size: 22),
                    SizedBox(width: 8),
                    Text('اختر موقع الوجهة',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: C.slate800)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: s.phase == PickPhase.resolved ? C.slate800 : C.slate500,
                    )),
                if (dist != null) ...[
                  const SizedBox(height: 6),
                  Text('المسافة من موقعك: ${formatDistance(dist)}',
                      style: const TextStyle(fontSize: 12, color: C.slate500)),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: picker.canConfirm ? onConfirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: C.emerald600,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('اختيار هذا الموقع',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// نص الـ attribution (مطلوب قانونيًا): قابل للضغط لفتح صفحة حقوق OSM.
/// متحط برّه الخريطة عشان يفضل ظاهر فوق الـ Bottom Sheet.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCCFFFFFF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => launchUrl(Uri.parse(MapConfig.osmCopyrightUrl),
            mode: LaunchMode.externalApplication),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(MapConfig.attribution,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: C.slate600)),
        ),
      ),
    );
  }
}
