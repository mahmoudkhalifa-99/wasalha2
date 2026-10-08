import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import 'common.dart';

/// حقل إدخال بأيقونة على اليمين — مكافئ:
/// `bg-slate-50 rounded-2xl py-4 pr-12 pl-4 font-bold text-sm border border-slate-200
///  focus:border-emerald-500 focus:bg-white`
class IconField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool ltr; // dir="ltr" + text-left
  final bool obscure;
  final TextInputType keyboardType;
  final double fontSize;
  final FontWeight weight;
  final double leftPadding; // pl-4 = 16 ، pl-10 = 40
  final double rightPadding; // pr-12 = 48 ، pr-11 = 44
  final Widget? suffix; // زر العين (على اليسار)
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  const IconField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.ltr = false,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.fontSize = 14,
    this.weight = T.w700,
    this.leftPadding = 16,
    this.rightPadding = 48,
    this.suffix,
    this.focusNode,
    this.onChanged,
  });

  @override
  State<IconField> createState() => _IconFieldState();
}

class _IconFieldState extends State<IconField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _focused ? C.white : C.slate50,
            borderRadius: radius,
            border: Border.all(
                color: _focused ? C.emerald500 : C.slate200, width: 1),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _node,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            textDirection: widget.ltr ? TextDirection.ltr : TextDirection.rtl,
            textAlign: widget.ltr ? TextAlign.left : TextAlign.right,
            cursorColor: C.emerald600,
            style: T.s(widget.fontSize, widget.weight, C.slate900),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintTextDirection:
                  widget.ltr ? TextDirection.ltr : TextDirection.rtl,
              hintStyle: T.s(widget.fontSize, widget.weight, C.gray400),
              contentPadding: EdgeInsets.fromLTRB(
                  widget.leftPadding, 16, widget.rightPadding, 16),
            ),
          ),
        ),
        Positioned(
          right: 16,
          child: IgnorePointer(
            child: Icon(widget.icon, size: 20, color: C.slate400),
          ),
        ),
        if (widget.suffix != null)
          Positioned(left: 12, child: widget.suffix!),
      ],
    );
  }
}

/// زر إظهار/إخفاء كلمة المرور (Eye / EyeOff)
class EyeToggle extends StatelessWidget {
  final bool shown;
  final VoidCallback onTap;
  const EyeToggle({super.key, required this.shown, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(shown ? LucideIcons.eyeOff : LucideIcons.eye,
            size: 16, color: C.slate400),
      ),
    );
  }
}

/// قائمة اختيار (مكافئ `<select>`) بنفس شكل الحقول
class SelectField extends StatefulWidget {
  final String value; // '' = لا شيء
  final String placeholder;
  final List<String> options;
  final IconData icon;
  final ValueChanged<String> onChanged;
  const SelectField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.options,
    required this.icon,
    required this.onChanged,
  });

  @override
  State<SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<SelectField> {
  bool _open = false;

  Future<void> _pick() async {
    setState(() => _open = true);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: const BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final o in widget.options)
                  ListTile(
                    title: Text(o,
                        textAlign: TextAlign.right,
                        style: T.s(
                            14,
                            T.w900,
                            o == widget.value ? C.emerald600 : C.slate700)),
                    onTap: () => Navigator.of(ctx).pop(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _open = false);
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.value.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pick,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 56,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 44, 0),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: _open ? C.white : C.slate50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _open ? C.emerald500 : C.slate200, width: 1),
            ),
            child: Text(
              has ? widget.value : widget.placeholder,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: T.s(12, T.w900, has ? C.slate900 : C.gray400),
            ),
          ),
          Positioned(
            right: 16,
            child: Icon(widget.icon, size: 20, color: C.slate400),
          ),
        ],
      ),
    );
  }
}

/// مربع اختيار صغير (w-4 h-4 rounded border-slate-300)
class MiniCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const MiniCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: value ? C.emerald600 : C.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: value ? C.emerald600 : C.slate300, width: 1),
        ),
        child: value
            ? const Icon(Icons.check, size: 12, color: C.white)
            : null,
      ),
    );
  }
}

/// تبديل شريحي (Segmented): تسجيل الدخول / إنشاء حساب — أو عميل / كابتن
class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final Color background;
  final Border? border;
  final double verticalPadding; // py-3 = 12 ، py-2.5 = 10
  final double gap;
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.background,
    this.border,
    this.verticalPadding = 12,
    this.gap = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: border,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == i ? C.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: selected == i ? Sh.sm() : null,
                  ),
                  child: Text(
                    labels[i],
                    style: T.s(12, T.w900,
                        selected == i ? C.emerald700 : C.slate500),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// زر رئيسي أخضر بعرض كامل (bg-emerald-600 rounded-2xl font-black shadow ...)
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double verticalPadding;
  const PrimaryButton({
    super.key,
    required this.onTap,
    required this.child,
    this.verticalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.emerald600,
          borderRadius: BorderRadius.circular(16),
          boxShadow: Sh.lg(color: C.emerald600.withOpacity(0.25)),
        ),
        child: child,
      ),
    );
  }
}

/// أرقام فقط + حرف واحد (لخانات الـ OTP)
final otpInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(1),
];
