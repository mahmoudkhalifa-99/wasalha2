import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'national_id.dart';

/// أنواع المفاتيح الفريدة (منع الازدواج). الـ Cloud Function هي اللي بتنشئها وتفرضها؛
/// التعريف ده لازم يطابق functions/verification.js (نفس التطبيع ونفس الـ hash).
enum UniqueKeyType { nid, phone, license, plate }

String _normalize(UniqueKeyType t, String raw) {
  switch (t) {
    case UniqueKeyType.nid:
      return normalizeDigits(raw);
    case UniqueKeyType.phone:
      return normalizeEgyptPhone(raw);
    case UniqueKeyType.license:
      // رقم الرخصة: حروف وأرقام بس، بدون مسافات أو شرطات.
      return normalizeDigitsAndLetters(raw);
    case UniqueKeyType.plate:
      return normalizeDigitsAndLetters(raw);
  }
}

/// بيشيل أي حاجة غير حروف/أرقام (عربي أو إنجليزي) ويوحّد الأرقام والهمزات.
String normalizeDigitsAndLetters(String raw) {
  final digitsFixed = StringBuffer();
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  for (final r in raw.runes) {
    final c = String.fromCharCode(r);
    final i = arabicDigits.indexOf(c);
    digitsFixed.write(i >= 0 ? '$i' : c);
  }
  return normalizeArabicName(digitsFixed.toString())
      .replaceAll(RegExp(r'[^0-9a-z\u0621-\u064A]'), '');
}

/// معرّف وثيقة unique_keys: {type}_{sha256(value المطبّع)}. null لو القيمة فاضية.
String? uniqueKeyId(UniqueKeyType t, String raw) {
  final v = _normalize(t, raw);
  if (v.isEmpty) return null;
  return '${t.name}_${sha256.convert(utf8.encode(v))}';
}
