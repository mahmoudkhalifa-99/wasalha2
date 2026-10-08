import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// breakpoint `md:` في Tailwind (768px)
bool isMd(BuildContext c) => MediaQuery.of(c).size.width >= 768;

/// breakpoint `sm:` في Tailwind (640px)
bool isSm(BuildContext c) => MediaQuery.of(c).size.width >= 640;

/// مكافئ `active:scale-95`
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PressScale(
      {super.key, required this.child, this.onTap, this.scale = 0.95});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

/// دائرة ضبابية (مكافئ `rounded-full bg-x blur-3xl`)
class Blob extends StatelessWidget {
  final double size;
  final Color color;
  final double blur; // قيمة الـ blur بالـ px (sigma)
  const Blob({super.key, required this.size, required this.color, this.blur = 64});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// دائرة بحدود فقط (الحلقات المتحدة المركز)
class Ring extends StatelessWidget {
  final double size;
  final Color color;
  const Ring({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1),
        ),
      ),
    );
  }
}

/// مكافئ `backdrop-blur-*` مع خلفية شفافة وحدود
class GlassBox extends StatelessWidget {
  final double sigma;
  final Color color;
  final BorderRadius borderRadius;
  final Border? border;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  final Widget? child;
  const GlassBox({
    super.key,
    this.sigma = 12,
    required this.color,
    required this.borderRadius,
    this.border,
    this.shadows,
    this.padding,
    this.gradient,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // لما الخلفية شبه معتمة (>= 85%) البلور مش بيبان وبيتقّل الأداء، فبنتخطاه.
    final skipBlur = sigma <= 0 || (gradient == null && color.opacity >= 0.85);
    Widget blurred(Widget c) => skipBlur
        ? c
        : BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: c);
    final inner = ClipRRect(
      borderRadius: borderRadius,
      child: blurred(
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: gradient == null ? color : null,
            gradient: gradient,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
    if (shadows == null) return inner;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: inner,
    );
  }
}

/// مكافئ `animate-ping`
class PingDot extends StatefulWidget {
  final double size;
  final Color color;
  const PingDot({super.key, required this.size, required this.color});

  @override
  State<PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 1))
    ..repeat();
  static const _curve = Cubic(0, 0, 0.2, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _curve.transform(_c.value);
        return Opacity(
          opacity: 1 - t,
          child: Transform.scale(
            scale: 1 + t,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration:
                  BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }
}

/// مكافئ `animate-pulse` (شفافية 1 → 0.5 → 1 كل ثانيتين)
class Pulse extends StatefulWidget {
  final Widget child;
  const Pulse({super.key, required this.child});

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 1))
    ..repeat(reverse: true);
  static const _curve = Cubic(0.4, 0, 0.6, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) =>
          Opacity(opacity: 1 - 0.5 * _curve.transform(_c.value), child: child),
      child: widget.child,
    );
  }
}

/// مكافئ `<Loader2 className="animate-spin" />`
class Spinner extends StatefulWidget {
  final double size;
  final Color color;
  const Spinner({super.key, this.size = 20, this.color = C.white});

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Icon(LucideIcons.loader2, size: widget.size, color: widget.color),
    );
  }
}

/// مكافئ `animate-reveal` من index.html:
/// fade + slide-up 30px + scale 0.95→1 خلال 0.6s
class Reveal extends StatefulWidget {
  final Widget child;
  const Reveal({super.key, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..forward();
  static const _curve = Cubic(0.16, 1, 0.3, 1);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _curve.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - t)),
            child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// خلفية التطبيق: slate-50 + إشعاعين خفيفين (من body في styles/index.css)
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final diag = (Offset(w, h)).distance;
      final short = w < h ? w : h;
      // "at corner ... transparent 50%" مع farthest-corner
      final radius = short == 0 ? 1.0 : diag * 0.5 / short;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: C.bgLight),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: radius,
                colors: [C.emerald500.withOpacity(0.05), const Color(0x0010B981)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomRight,
                radius: radius,
                colors: [C.amber500.withOpacity(0.03), const Color(0x00F59E0B)],
              ),
            ),
          ),
          child,
        ],
      );
    });
  }
}

/// مكافئ `alert()` في المتصفح
Future<void> showAppAlert(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: C.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Text(message,
            style: T.s(14, T.w700, C.slate900)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('حسناً', style: T.s(14, T.w900, C.emerald600)),
          ),
        ],
      ),
    ),
  );
}


/// صورة بتدعم الروابط (http) والصور المحفوظة base64 (data:image/...) —
/// الأدمن بيحفظ صور المطاعم والمنيو كـ base64، و Image.network مش بيعرضها.
class SmartImage extends StatelessWidget {
  final String? src;
  final BoxFit fit;
  final Widget? placeholder;
  const SmartImage(this.src,
      {super.key, this.fit = BoxFit.cover, this.placeholder});

  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _decode(String s) {
    final hit = _cache[s];
    if (hit != null) return hit;
    try {
      final comma = s.indexOf(',');
      final raw = comma >= 0 ? s.substring(comma + 1) : s;
      final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      return _cache[s] = bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder ??
        const Center(child: Icon(LucideIcons.image, size: 24, color: C.slate300));
    final s = src?.trim();
    if (s == null || s.isEmpty) return fallback;
    if (s.startsWith('data:')) {
      final bytes = _decode(s);
      if (bytes == null) return fallback;
      return Image.memory(bytes,
          fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback);
    }
    return Image.network(s,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, p) => p == null
            ? child
            : const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))));
  }
}
