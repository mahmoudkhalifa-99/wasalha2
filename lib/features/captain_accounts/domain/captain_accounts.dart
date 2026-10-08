import 'package:intl/intl.dart' as intl;

import '../../../config_constants.dart' show platformFeePerTrip;
import '../../../models/models.dart' show OrderStatus;

/// حسابات الكباتن: عدد المشاوير والمستحق للمنصة (رسوم ثابتة على كل مشوار). كل المنطق هنا نقي (من غير
/// Firestore) عشان يتختبر.
///
/// أساس العد: الطلب اللي حالته DELIVERED ومعيّن عليه كابتن، ووقته (`updatedAt`
/// وقت التسليم) جوه الفترة. السعر = سعر العرض اللي العميل وافق عليه (`price`).

/// رسوم المشوار الافتراضية (من الثابت العام للمنصة) بالجنيه: 5 جنيه.
double get kDefaultFeePerTrip => platformFeePerTrip;

enum PeriodPreset { thisMonth, lastMonth, last30Days, custom }

extension PeriodPresetLabel on PeriodPreset {
  String get label => switch (this) {
        PeriodPreset.thisMonth => 'هذا الشهر',
        PeriodPreset.lastMonth => 'الشهر الماضي',
        PeriodPreset.last30Days => 'آخر 30 يوم',
        PeriodPreset.custom => 'فترة مخصصة',
      };
}

/// فترة زمنية: [start] شاملة و[end] غير شاملة (بالتوقيت المحلي).
class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);

  int get startMs => start.millisecondsSinceEpoch;
  int get endMs => end.millisecondsSinceEpoch;

  bool containsMs(int ms) => ms >= startMs && ms < endMs;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// بيحسب الفترة. للفترة المخصصة: [customFirstDay] و[customLastDay] أيام كاملة
/// وشاملة الاتنين (النهاية = بداية اليوم اللي بعد آخر يوم).
DateRange rangeFor(
  PeriodPreset p,
  DateTime now, {
  DateTime? customFirstDay,
  DateTime? customLastDay,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  switch (p) {
    case PeriodPreset.thisMonth:
      return DateRange(DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1));
    case PeriodPreset.lastMonth:
      return DateRange(DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 1));
    case PeriodPreset.last30Days:
      final today = day(now);
      return DateRange(
          DateTime(today.year, today.month, today.day - 29),
          DateTime(today.year, today.month, today.day + 1));
    case PeriodPreset.custom:
      final a = day(customFirstDay ?? now);
      final b = day(customLastDay ?? now);
      final first = a.isAfter(b) ? b : a;
      final last = a.isAfter(b) ? a : b;
      return DateRange(first, DateTime(last.year, last.month, last.day + 1));
  }
}

/// سطر مشوار (نسخة خفيفة من الطلب).
class TripRow {
  final String orderId;
  final String? driverId;
  final OrderStatus status;
  final double price;
  final int atMs; // updatedAt
  final String from;
  final String to;

  const TripRow({
    required this.orderId,
    required this.driverId,
    required this.status,
    required this.price,
    required this.atMs,
    this.from = '',
    this.to = '',
  });
}

/// حساب كابتن واحد في فترة.
class CaptainStats {
  final String driverId;

  /// مشاوير مكتملة (DELIVERED).
  final List<TripRow> delivered;

  /// طلبات اتعيّنت عليه واتلغت بعد كده (CANCELLED وفيها driverId).
  final int cancelledAfterAssign;

  const CaptainStats({
    required this.driverId,
    this.delivered = const [],
    this.cancelledAfterAssign = 0,
  });

  int get deliveredCount => delivered.length;

  double get totalFares => delivered.fold(0.0, (a, t) => a + t.price);

  double get averageFare => deliveredCount == 0 ? 0 : totalFares / deliveredCount;
}

/// بيجمّع الطلبات حسب الكابتن للفترة. الطلبات بدون كابتن أو برّه الفترة بتتجاهل.
/// النتيجة مرتبة بالأكتر مشاوير أولًا.
List<CaptainStats> buildCaptainStats(Iterable<TripRow> rows, DateRange range) {
  final delivered = <String, List<TripRow>>{};
  final cancelled = <String, int>{};
  for (final r in rows) {
    final id = r.driverId;
    if (id == null || id.isEmpty) continue;
    if (!range.containsMs(r.atMs)) continue;
    if (r.status == OrderStatus.delivered) {
      delivered.putIfAbsent(id, () => []).add(r);
    } else if (r.status == OrderStatus.cancelled) {
      cancelled[id] = (cancelled[id] ?? 0) + 1;
    }
  }
  final ids = {...delivered.keys, ...cancelled.keys};
  final out = [
    for (final id in ids)
      CaptainStats(
        driverId: id,
        delivered: (delivered[id] ?? const <TripRow>[])
            .toList()
          ..sort((a, b) => b.atMs.compareTo(a.atMs)),
        cancelledAfterAssign: cancelled[id] ?? 0,
      ),
  ];
  out.sort((a, b) {
    final c = b.deliveredCount.compareTo(a.deliveredCount);
    return c != 0 ? c : a.driverId.compareTo(b.driverId);
  });
  return out;
}

/// المستحق للمنصة = عدد المشاوير المكتملة × رسوم المشوار، مقرّب لأقرب قرش.
double feeDue(int trips, double feePerTrip) {
  if (trips <= 0 || feePerTrip <= 0) return 0;
  return (trips * feePerTrip * 100).round() / 100;
}

/// أقصى رسوم مشوار مقبولة في الإدخال (حماية من خطأ كتابة).
const double kMaxFeePerTrip = 1000;

/// بيحوّل نص المبلغ (بيقبل الأرقام العربية و"," و"ج.م") لرقم من 0 لـ [kMaxFeePerTrip]، أو null.
double? parseFee(String raw) {
  // أي علامة سالب = إدخال غلط (مش بنحوّله لموجب بالغلط).
  if (raw.contains('-') || raw.contains('−') || raw.contains('–')) return null;
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in raw.runes) {
    final c = String.fromCharCode(r);
    final i = ar.indexOf(c);
    if (i >= 0) {
      b.write(i);
    } else if (c == '٫' || c == ',' || c == '،') {
      b.write('.');
    } else if ((r >= 0x30 && r <= 0x39) || c == '.') {
      b.write(c);
    }
  }
  final v = double.tryParse(b.toString());
  if (v == null || v.isNaN || v < 0 || v > kMaxFeePerTrip) return null;
  return v;
}

/// مبلغ بالجنيه: من غير كسور لو صحيح، وإلا خانتين. مثال: 1,250 أو 1,250.5 → 1,250.50
String formatMoney(double v) {
  final isWhole = (v - v.roundToDouble()).abs() < 0.005;
  return intl.NumberFormat(isWhole ? '#,##0' : '#,##0.00', 'en').format(v);
}
