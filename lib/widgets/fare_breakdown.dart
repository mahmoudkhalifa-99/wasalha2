import 'package:flutter/material.dart';

import '../pricing.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

String _money(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// ملخص للكابتن: قيمة الرحلة ← عمولة التطبيق ← صافي المستحق.
/// [fare] هو السعر النهائي للمشوار (العميل بيشوفه هو بس).
class FareBreakdownView extends StatelessWidget {
  const FareBreakdownView({super.key, required this.fare});

  final double fare;

  Widget _row(String label, String value,
      {Color? color, bool bold = false, double size = 13}) {
    final w = bold ? T.w900 : T.w700;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(value, style: T.s(size, w, color ?? C.slate900)),
        Text(label, style: T.s(size, w, color ?? C.slate600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.emerald50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.emerald100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('قيمة الرحلة', '${_money(fare)} ج.م'),
          const SizedBox(height: 6),
          _row('عمولة التطبيق', '- ${_money(platformCommission)} ج.م',
              color: C.rose500),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: C.emerald100),
          ),
          _row('صافي مستحقك', '${_money(driverEarnings(fare))} ج.م',
              color: C.emerald700, bold: true, size: 15),
        ],
      ),
    );
  }
}
