import 'dart:ui';

/// ألوان Tailwind الافتراضية (نفس القيم المستخدمة في نسخة الويب بالظبط)
class C {
  C._();

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  // slate
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // emerald
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);
  static const emerald900 = Color(0xFF064E3B);
  static const emerald950 = Color(0xFF022C22);

  // teal
  static const teal500 = Color(0xFF14B8A6);
  static const teal700 = Color(0xFF0F766E);
  static const teal900 = Color(0xFF134E4A);

  // amber
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber800 = Color(0xFF92400E);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber950 = Color(0xFF451A03);

  // rose
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);

  // blue
  static const blue600 = Color(0xFF2563EB);

  // indigo
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo500 = Color(0xFF6366F1);

  // gray (لون الـ placeholder في Tailwind preflight)
  static const gray400 = Color(0xFF9CA3AF);

  // ألوان البراند من styles/index.css
  static const brandPrimary = Color(0xFF2D9469); // --emerald-primary / theme-color
  static const brandAmber = Color(0xFFF59E0B);
  static const brandCoral = Color(0xFFFF6B4A);
  static const bgLight = Color(0xFFF8FAFC);

  /// نفس مبدأ `bg-emerald-500/20` في Tailwind
  static Color a(Color c, double opacity) => c.withOpacity(opacity);
}
