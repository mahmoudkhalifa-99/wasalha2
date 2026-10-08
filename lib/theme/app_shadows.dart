import 'package:flutter/material.dart';

/// ظلال Tailwind (shadow-sm / md / lg / xl / 2xl) مع إمكانية تلوينها
/// مثل `shadow-emerald-600/25`.
class Sh {
  Sh._();

  static List<BoxShadow> sm({Color? color}) => [
        BoxShadow(
            color: color ?? const Color(0x0D000000),
            offset: const Offset(0, 1),
            blurRadius: 2),
      ];

  static List<BoxShadow> md({Color? color}) => [
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 4),
            blurRadius: 6,
            spreadRadius: -1),
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 2),
            blurRadius: 4,
            spreadRadius: -2),
      ];

  static List<BoxShadow> lg({Color? color}) => [
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 10),
            blurRadius: 15,
            spreadRadius: -3),
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 4),
            blurRadius: 6,
            spreadRadius: -4),
      ];

  static List<BoxShadow> xl({Color? color}) => [
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 20),
            blurRadius: 25,
            spreadRadius: -5),
        BoxShadow(
            color: color ?? const Color(0x1A000000),
            offset: const Offset(0, 8),
            blurRadius: 10,
            spreadRadius: -6),
      ];

  static List<BoxShadow> xxl({Color? color}) => [
        BoxShadow(
            color: color ?? const Color(0x40000000),
            offset: const Offset(0, 25),
            blurRadius: 50,
            spreadRadius: -12),
      ];

  /// `ring-4` بلون معين (box-shadow 0 0 0 4px)
  static BoxShadow ring(Color color, {double width = 4}) =>
      BoxShadow(color: color, spreadRadius: width);
}
