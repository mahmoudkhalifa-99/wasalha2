import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/map/geo_utils.dart';
import '../../../theme/app_colors.dart';
import '../controllers/tracking_controller.dart';
import '../models/tracking_models.dart';

/// محتوى الـ Bottom Sheet (من غير الحاوية/المقبض — دي مسؤولية الشاشة).
/// كل حالة (مباشر/قديم/انتظار/GPS/نت/مسار…) ليها رسالة واضحة.
class TrackingSheetContent extends StatelessWidget {
  const TrackingSheetContent({
    super.key,
    required this.controller,
    this.customerAddress,
    this.onFitRoute,
  });

  final TrackingController controller;

  /// عنوان العميل لو الشاشة الأم عارفه (اختياري).
  final String? customerAddress;
  final VoidCallback? onFitRoute;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: Listenable.merge([
        c.status,
        c.driver,
        c.me,
        c.route,
        c.progress,
        c.destination,
        c.freshness,
        c.networkOk,
        c.routeUnavailable,
        c.routeLoading,
        c.locationIssue,
        c.gpsAccuracyLow,
      ]),
      builder: (context, _) {
        final status = c.status.value;
        final issue = c.locationIssue.value;
        final dest = c.destination.value;
        final offline = !c.networkOk.value;
        final routeFailed = c.routeUnavailable.value && c.networkOk.value;
        final routeLoading = c.routeLoading.value;
        final progress = c.progress.value;
        final fresh = c.freshness.value;
        final driverFix = c.driver.value;
        final sharingPaused = c.isDriverMode && issue != null && driverFix != null;
        final gpsLoading = status == TrackingStatus.starting &&
            c.me.value == null &&
            issue == null &&
            !c.gpsAccuracyLow.value;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (routeLoading || gpsLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ),
              if (gpsLoading)
                const _Banner(
                  color: C.slate100,
                  textColor: C.slate600,
                  icon: Icons.gps_not_fixed_rounded,
                  text: 'جاري تحديد موقعك…',
                ),
              if (offline)
                const _Banner(
                  color: C.amber100,
                  textColor: C.amber800,
                  icon: Icons.wifi_off_rounded,
                  text: 'لا يوجد اتصال بالإنترنت. بنعرض آخر مسار معروف '
                      'وهنكمّل التحديث أوتوماتيك لما النت يرجع.',
                ),
              if (routeFailed)
                const _Banner(
                  color: C.amber100,
                  textColor: C.amber800,
                  icon: Icons.alt_route_rounded,
                  text: 'تعذّر حساب المسار حاليًا. هنعيد المحاولة تلقائيًا.',
                ),
              if (issue != null)
                _Banner(
                  color: C.rose100,
                  textColor: C.rose700,
                  icon: Icons.location_off_rounded,
                  text: issue.message,
                  actionLabel: issue.actionLabel,
                  onAction: c.openLocationSettings,
                ),
              if (sharingPaused)
                const _Banner(
                  color: C.amber100,
                  textColor: C.amber800,
                  icon: Icons.pause_circle_outline_rounded,
                  text: 'مشاركة موقعك متوقفة مؤقتًا لحد ما الـ GPS يرجع.',
                ),
              if (c.gpsAccuracyLow.value)
                const _Banner(
                  color: C.amber100,
                  textColor: C.amber800,
                  icon: Icons.gps_off_rounded,
                  text: 'دقة الـ GPS ضعيفة حاليًا. بنستخدم آخر موقع دقيق لحد '
                      'ما الإشارة تتحسن.',
                ),
              _DriverRow(
                title: c.isDriverMode ? 'موقعي (السائق)' : 'السائق',
                freshness: fresh,
                fix: driverFix,
              ),
              const SizedBox(height: 10),
              _CustomerRow(destination: dest != null, address: customerAddress),
              if (dest != null) ...[
                const SizedBox(height: 12),
                _Summary(
                  isDriverMode: c.isDriverMode,
                  progress: progress,
                  straightMeters: c.straightDistanceMeters,
                  hasDriver: driverFix != null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        icon: Icons.straighten_rounded,
                        label: 'المسافة',
                        value: _distanceText(progress, c.straightDistanceMeters),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Metric(
                        icon: Icons.schedule_rounded,
                        label: 'الوقت المتوقع',
                        value: progress == null
                            ? '—'
                            : formatEta(progress.durationSeconds),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onFitRoute,
                  icon: const Icon(Icons.alt_route_rounded, size: 18),
                  label: const Text('عرض الطريق',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: C.emerald600,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _distanceText(RouteProgress? p, double? straight) {
    if (p != null) return formatDistance(p.distanceMeters);
    if (straight != null) return '≈ ${formatDistance(straight)}';
    return '—';
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.title, required this.freshness, required this.fix});
  final String title;
  final Freshness freshness;
  final GeoFix? fix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _CircleIcon(icon: Icons.directions_car_filled_rounded, color: C.emerald600),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: C.slate800)),
              const SizedBox(height: 2),
              LastUpdateText(fix: fix, freshness: freshness),
            ],
          ),
        ),
        FreshnessChip(freshness: freshness),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.destination, this.address});
  final bool destination;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final text = !destination
        ? 'موقع العميل غير محدد'
        : (address != null && address!.trim().isNotEmpty
            ? address!.trim()
            : 'موقع التسليم محدد على الخريطة');
    return Row(
      children: [
        _CircleIcon(
          icon: Icons.location_on_rounded,
          color: destination ? C.rose600 : C.slate400,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('العميل',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: C.slate800)),
              const SizedBox(height: 2),
              Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: destination ? C.slate600 : C.slate500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.isDriverMode,
    required this.progress,
    required this.straightMeters,
    required this.hasDriver,
  });
  final bool isDriverMode;
  final RouteProgress? progress;
  final double? straightMeters;
  final bool hasDriver;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final dist = p != null
        ? formatDistance(p.distanceMeters)
        : (straightMeters != null ? '≈ ${formatDistance(straightMeters!)}' : null);
    String text;
    if (!hasDriver || dist == null) {
      text = isDriverMode ? 'بنحدد موقعك…' : 'في انتظار موقع السائق…';
    } else if (isDriverMode) {
      text = 'أنت على بعد $dist من العميل';
      if (p != null) text += ' · الوصول خلال ${formatEta(p.durationSeconds)}';
    } else {
      text = 'السائق على بعد $dist منك';
      if (p != null) text += ' · يصل خلال ${formatEta(p.durationSeconds)}';
    }
    return Text(text,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: C.slate700));
  }
}

/// شارة الحالة: مباشر / قديم / في انتظار / غير متاح.
class FreshnessChip extends StatelessWidget {
  const FreshnessChip({super.key, required this.freshness});
  final Freshness freshness;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (freshness) {
      case Freshness.live:
        bg = C.emerald50;
        fg = C.emerald700;
      case Freshness.stale:
        bg = C.amber100;
        fg = C.amber800;
      case Freshness.waiting:
        bg = C.slate100;
        fg = C.slate600;
      case Freshness.unavailable:
        bg = C.rose100;
        fg = C.rose700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(freshness.label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// "آخر تحديث منذ 25 ثانية" — بيتحدث كل ثانية لوحده (setState على النص ده بس).
class LastUpdateText extends StatefulWidget {
  const LastUpdateText({super.key, required this.fix, required this.freshness});
  final GeoFix? fix;
  final Freshness freshness;

  @override
  State<LastUpdateText> createState() => _LastUpdateTextState();
}

class _LastUpdateTextState extends State<LastUpdateText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.fix != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fix;
    final String text;
    if (f == null) {
      text = widget.freshness == Freshness.unavailable
          ? 'موقع غير متاح'
          : 'لسه موقع السائق ما وصلش';
    } else {
      text = formatLastUpdate(DateTime.now().difference(f.updatedAt));
    }
    return Text(text, style: const TextStyle(fontSize: 12, color: C.slate500));
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.slate200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: C.emerald600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: C.slate500)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: C.slate800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.textColor,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final Color textColor;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: textColor,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}
