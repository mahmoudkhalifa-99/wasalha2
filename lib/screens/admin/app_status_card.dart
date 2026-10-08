import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/models.dart';
import '../../services/app_status_service.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_text.dart';
import '../../widgets/common.dart';

/// كارت تشغيل/إيقاف التطبيق للسوبر أدمن.
/// لما التطبيق يتوقف كل المستخدمين (عملاء/كباتن/مشغّلين) بيشوفوا شاشة صيانة،
/// والسوبر أدمن بس هو اللي بيكمّل شغل عادي.
class AppStatusCard extends StatefulWidget {
  final AppUser admin;
  const AppStatusCard({super.key, required this.admin});

  @override
  State<AppStatusCard> createState() => _AppStatusCardState();
}

class _AppStatusCardState extends State<AppStatusCard> {
  bool _busy = false;

  Future<void> _toggle(AppStatus current) async {
    if (_busy) return;
    final turningOff = current.enabled;
    String message = current.message;

    if (turningOff) {
      final ctrl = TextEditingController(text: current.message);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('إيقاف التطبيق؟', style: T.s(18, T.w900, C.slate900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'كل المستخدمين ما عدا السوبر أدمن هيشوفوا شاشة "التطبيق متوقف" ومش هيقدروا يستخدموه لحد ما تشغّله تاني.',
                    style: T.s(12, T.w500, C.slate500)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'رسالة تظهر للمستخدمين (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('إيقاف التطبيق',
                      style: T.s(14, T.w800, C.rose600))),
            ],
          ),
        ),
      );
      message = ctrl.text;
      ctrl.dispose();
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await AppStatusService.set(
        enabled: !turningOff,
        message: turningOff ? message : '',
        adminId: widget.admin.id,
      );
    } catch (e) {
      if (mounted) showAppAlert(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppStatus>(
      stream: AppStatusService.watch(),
      initialData: AppStatus.on,
      builder: (context, snap) {
        final st = snap.data ?? AppStatus.on;
        final on = st.enabled;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: on ? C.white : C.rose50,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: on ? C.slate100 : C.rose200),
            boxShadow: Sh.sm(),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: on ? C.emerald50 : C.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(LucideIcons.power,
                    size: 22, color: on ? C.emerald600 : C.rose600),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(on ? 'التطبيق شغّال' : 'التطبيق متوقف',
                        style: T.s(16, T.w900, C.slate900)),
                    const SizedBox(height: 2),
                    Text(
                        on
                            ? 'اضغط الزر لإيقافه لكل المستخدمين'
                            : 'المستخدمين شايفين شاشة الصيانة',
                        style: T.s(11, T.w500, C.slate500)),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                Switch(
                  value: on,
                  activeColor: C.emerald600,
                  onChanged: (_) => _toggle(st),
                ),
            ],
          ),
        );
      },
    );
  }
}
