import 'package:flutter/material.dart';

import '../models/models.dart';
import '../pricing.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'common.dart';
import 'fare_breakdown.dart';

/// معاينة صورة (روشتة/علبة دواء) مع تكبير بملء الشاشة عند الضغط.
class PrescriptionPreview extends StatelessWidget {
  const PrescriptionPreview({super.key, required this.image, this.height = 190});

  final String image;
  final double height;

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xF2000000),
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: const Color(0xFF000000),
        shape: const RoundedRectangleBorder(),
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(child: SmartImage(image, fit: BoxFit.contain)),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 12,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: C.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        size: 26, color: C.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: height,
          width: double.infinity,
          color: C.slate100,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartImage(image, fit: BoxFit.cover),
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xB3000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_in_rounded,
                          size: 14, color: C.white),
                      const SizedBox(width: 4),
                      Text('اضغط للتكبير', style: T.s(9, T.w800, C.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _categoryLabel(OrderCategory c) {
  switch (c) {
    case OrderCategory.taxi:
      return 'مشوار 🚕';
    case OrderCategory.food:
      return 'طلب مطعم 🍔';
    case OrderCategory.pharmacy:
      return 'صيدلية 💊';
    case OrderCategory.grocery:
      return 'بقالة 🛒';
    case OrderCategory.parcel:
      return 'توصيل طرد 📦';
  }
}

String _placeText(OrderPlace p) {
  final parts = <String>[];
  for (final s in [p.address, p.villageName]) {
    final t = (s ?? '').trim();
    if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
  }
  return parts.join(' — ');
}

/// تفاصيل الطلب كاملة للكابتن (قبل تقديم العرض وبعده): النوع، من/إلى،
/// الملاحظات، المسافة والسعر، الأصناف، الطلب الخاص، وصورة الروشتة.
class OrderDetailsPanel extends StatelessWidget {
  const OrderDetailsPanel({super.key, required this.order});

  final Order order;

  Widget _row(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$label: ',
                    style: T.s(11, T.w900, color ?? C.slate400)),
                TextSpan(text: value, style: T.s(12, T.w700, C.slate800)),
              ]),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 15, color: color ?? C.slate400),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    // الصيدلية مالهاش إحداثيات (0,0) لكن نص "صيدلية" لسه بيتعرض للكابتن.
    final pickupHasRealPlace = (o.pickup.lat != 0 || o.pickup.lng != 0) ||
        o.category == OrderCategory.pharmacy;
    final from = (o.restaurantName != null && o.restaurantName!.isNotEmpty)
        ? [o.restaurantName!, if ((o.pickup.villageName ?? '').isNotEmpty && o.restaurantId != null) o.pickup.villageName!].join(' — ')
        : (pickupHasRealPlace ? _placeText(o.pickup) : '');
    final to = _placeText(o.dropoff);
    final pNotes = (o.pickupNotes ?? '').trim();
    final dNotes = (o.dropoffNotes ?? '').trim();
    final items = o.foodItems ?? const <CartItem>[];
    final special = (o.specialRequest ?? '').trim();
    final rx = o.prescriptionImage;
    final hasRx = rx != null && rx.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.slate50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تفاصيل الطلب',
              textAlign: TextAlign.right,
              style: T.s(12, T.w900, C.slate900)),
          const SizedBox(height: 10),
          _row(Icons.category_rounded, 'النوع', _categoryLabel(o.category)),
          if (from.isNotEmpty)
            _row(Icons.storefront_rounded, 'الاستلام من', from,
                color: C.rose500),
          if (to.isNotEmpty)
            _row(Icons.location_on_rounded, 'التوصيل إلى', to,
                color: C.emerald600),
          if (pNotes.isNotEmpty)
            _row(Icons.sticky_note_2_rounded, 'ملاحظات الاستلام', pNotes),
          if (dNotes.isNotEmpty)
            _row(Icons.sticky_note_2_rounded, 'ملاحظات التوصيل', dNotes),
          if (o.distance > 0)
            _row(Icons.straighten_rounded, 'المسافة',
                '${o.distance.toStringAsFixed(1)} كم'),
          if (o.foodItems != null && o.foodItems!.isNotEmpty)
            _row(Icons.payments_rounded, 'إجمالي الطلب (أصناف + توصيل)',
                '${o.price.toInt()} ج.م'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FareBreakdownView(fare: finalFare(tripFareOf(o))),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('الأصناف:',
                textAlign: TextAlign.right,
                style: T.s(11, T.w900, C.amber500)),
            const SizedBox(height: 4),
            for (final i in items)
              Text(
                  '- ${i.name} (${i.quantity}x) — ${(i.price * i.quantity).toInt()} ج.م',
                  textAlign: TextAlign.right,
                  style: T.s(12, T.w700, C.slate700)),
            const SizedBox(height: 6),
          ],
          if (special.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.blue600.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.blue600.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      o.category == OrderCategory.pharmacy
                          ? 'الأدوية المطلوبة / ملاحظات العميل:'
                          : 'طلب خاص من العميل:',
                      style: T.s(10, T.w900, C.blue600)),
                  const SizedBox(height: 4),
                  Text(special,
                      textAlign: TextAlign.right,
                      style: T.s(12, T.w700, C.slate700, height: 1.5)),
                ],
              ),
            ),
          ],
          if (hasRx) ...[
            const SizedBox(height: 10),
            Text('صورة الروشتة / الدواء:',
                textAlign: TextAlign.right,
                style: T.s(11, T.w900, C.rose500)),
            const SizedBox(height: 6),
            PrescriptionPreview(image: rx),
          ],
        ],
      ),
    );
  }
}
