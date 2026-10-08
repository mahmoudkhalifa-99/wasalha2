// طلب الأذونات المطلوبة مرة واحدة عند أول فتح للتطبيق.
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'notification_service.dart';

const _askedKey = 'permissions_intro_shown_v1';

class PermissionService {
  /// أول مرة بس: شاشة شرح + طلب الإشعارات والموقع.
  static Future<void> requestOnFirstLaunch(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return;
    if (!context.mounted) return;

    final go = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PermissionsSheet(),
    );
    await prefs.setBool(_askedKey, true);
    if (go != true) return;

    await NotificationService.requestPermission();
    await Permission.locationWhenInUse.request();
  }
}

class _PermissionsSheet extends StatelessWidget {
  const _PermissionsSheet();

  Widget _row(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: C.emerald50, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: C.emerald600, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: T.s(14, T.w900, C.slate900)),
                  const SizedBox(height: 2),
                  Text(sub, style: T.s(12, T.w500, C.slate500, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: C.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أذونات التطبيق',
                textAlign: TextAlign.center,
                style: T.s(20, T.w900, C.slate900)),
            const SizedBox(height: 6),
            Text('عشان وصلها يشتغل صح محتاجين الأذونات دي:',
                textAlign: TextAlign.center,
                style: T.s(12, T.w500, C.slate500)),
            const SizedBox(height: 12),
            _row(Icons.notifications_active_rounded, 'الإشعارات',
                'تنبيه الكابتن بالطلبات الجديدة، وتنبيه العميل بعروض الأسعار وحالة المشوار.'),
            _row(Icons.my_location_rounded, 'الموقع',
                'تحديد مكانك على الخريطة وتتبع الكابتن أثناء المشوار.'),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: C.emerald600,
                    borderRadius: BorderRadius.circular(16)),
                child: Text('السماح بالأذونات',
                    style: T.s(15, T.w900, C.white)),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('لاحقاً', style: T.s(12, T.w700, C.slate400)),
            ),
          ],
        ),
      ),
    );
  }
}
