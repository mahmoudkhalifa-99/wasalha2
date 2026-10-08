import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import 'common.dart';

enum BrandLogoSize { sm, md, lg, xl }

/// نسخة Flutter من components/BrandLogo.tsx
class BrandLogo extends StatelessWidget {
  final BrandLogoSize size;
  final bool showSubtitle;
  final bool inverted;
  const BrandLogo({
    super.key,
    this.size = BrandLogoSize.md,
    this.showSubtitle = true,
    this.inverted = false,
  });

  double get _icon {
    switch (size) {
      case BrandLogoSize.sm:
        return 36; // w-9 h-9
      case BrandLogoSize.md:
        return 48;
      case BrandLogoSize.lg:
        return 80;
      case BrandLogoSize.xl:
        return 112;
    }
  }

  double get _title {
    switch (size) {
      case BrandLogoSize.sm:
        return 18;
      case BrandLogoSize.md:
        return 24;
      case BrandLogoSize.lg:
        return 36;
      case BrandLogoSize.xl:
        return 48;
    }
  }

  double get _subtitle {
    switch (size) {
      case BrandLogoSize.sm:
        return 8;
      case BrandLogoSize.md:
        return 10;
      case BrandLogoSize.lg:
        return 12;
      case BrandLogoSize.xl:
        return 14;
    }
  }

  @override
  Widget build(BuildContext context) {
    final md = isMd(context);
    final radius = md ? 28.0 : 20.0; // rounded-[1.75rem] / rounded-[1.25rem]

    final emblem = Container(
      width: _icon,
      height: _icon,
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          ...Sh.md(
              color: inverted
                  ? C.white.withOpacity(0.2)
                  : C.emerald500.withOpacity(0.2)),
          // ring-2 / ring-1
          inverted
              ? Sh.ring(C.white.withOpacity(0.3), width: 2)
              : Sh.ring(C.slate200.withOpacity(0.8), width: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/images/icon-192.png', fit: BoxFit.cover),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start, // text-right في RTL = start
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'وصـــلــهــا',
              style: T.s(_title, T.w900, inverted ? C.white : C.slate900,
                  height: 1.25, letterSpacing: -0.4),
            ),
            const SizedBox(width: 6),
            const PingDot(size: 8, color: C.emerald500),
          ],
        ),
        if (showSubtitle)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'توصيل ذكي • المنوفية',
              style: T.s(
                  _subtitle,
                  T.w900,
                  inverted ? C.emerald100.withOpacity(0.9) : C.slate400,
                  height: 1.25,
                  letterSpacing: 0.4),
            ),
          ),
      ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        const SizedBox(width: 14), // gap-3.5
        text,
      ],
    );
  }
}
