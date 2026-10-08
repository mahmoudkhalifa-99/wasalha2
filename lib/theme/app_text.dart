import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// أحجام الخطوط وارتفاعات الأسطر بنفس جدول Tailwind
/// (text-xs = 12/16 ، text-sm = 14/20 ، ...) مع خط Cairo.
class T {
  T._();

  static double _lh(double size) {
    switch (size.round()) {
      case 12:
        return 16 / 12;
      case 14:
        return 20 / 14;
      case 16:
        return 24 / 16;
      case 18:
        return 28 / 18;
      case 20:
        return 28 / 20;
      case 24:
        return 32 / 24;
      case 30:
        return 36 / 30;
      case 36:
        return 40 / 36;
      case 48:
        return 1.0;
      default:
        // النصوص المخصصة مثل text-[10px] بتاخد line-height = 1.5 تقريباً
        return 1.5;
    }
  }

  static const w400 = FontWeight.w400;
  static const w500 = FontWeight.w500; // font-medium
  static const w600 = FontWeight.w600; // font-semibold
  static const w700 = FontWeight.w700; // font-bold
  static const w800 = FontWeight.w800; // font-extrabold
  static const w900 = FontWeight.w900; // font-black

  static TextStyle s(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.cairo(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height ?? _lh(size),
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
  }
}
