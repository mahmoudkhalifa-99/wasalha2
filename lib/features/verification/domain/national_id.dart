/// أدوات الرقم القومي المصري (14 رقم). الفحص هنا هيكلي فقط:
/// صحة الشكل وتاريخ الميلاد. ما بيثبتش إن البطاقة أصلية ولا إن الرقم مسجّل فعلًا.
class NationalIdInfo {
  final DateTime birthDate;
  final bool isMale;
  final String governorateCode;
  const NationalIdInfo(this.birthDate, this.isMale, this.governorateCode);
}

/// أكواد المحافظات في الرقم القومي (خانتا 8-9) + 88 للمولودين بالخارج.
const Set<String> kGovernorateCodes = {
  '01', '02', '03', '04', '11', '12', '13', '14', '15', '16', '17', '18', '19',
  '21', '22', '23', '24', '25', '26', '27', '28', '29', '31', '32', '33', '34',
  '35', '88',
};

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// بيحوّل الأرقام العربية لإنجليزية ويشيل أي حاجة مش رقم.
String normalizeDigits(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    final c = String.fromCharCode(r);
    final i = _arabicDigits.indexOf(c);
    if (i >= 0) {
      b.write(i);
    } else if (r >= 0x30 && r <= 0x39) {
      b.write(c);
    }
  }
  return b.toString();
}

/// بيفك الرقم القومي، أو null لو الشكل غلط.
NationalIdInfo? parseNationalId(String raw, {DateTime? now}) {
  final id = normalizeDigits(raw);
  if (id.length != 14) return null;
  final century = id[0];
  if (century != '2' && century != '3') return null; // 1900s / 2000s
  final yy = int.parse(id.substring(1, 3));
  final mm = int.parse(id.substring(3, 5));
  final dd = int.parse(id.substring(5, 7));
  final year = (century == '2' ? 1900 : 2000) + yy;
  final birth = DateTime(year, mm, dd);
  // DateTime بيعدّل التواريخ الغلط (٣٠ فبراير) فنتأكد إنه ما اتغيرش.
  if (birth.year != year || birth.month != mm || birth.day != dd) return null;
  if (birth.isAfter(now ?? DateTime.now())) return null;
  final gov = id.substring(7, 9);
  if (!kGovernorateCodes.contains(gov)) return null;
  final isMale = int.parse(id[12]).isOdd;
  return NationalIdInfo(birth, isMale, gov);
}

bool isValidNationalId(String raw, {DateTime? now}) =>
    parseNationalId(raw, now: now) != null;

/// العمر بالسنين في تاريخ [now].
int ageOn(DateTime birth, DateTime now) {
  var a = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) a--;
  return a;
}

/// إخفاء الرقم القومي في أي واجهة عامة: أول رقمين وآخر رقمين بس.
String maskNationalId(String raw) {
  final id = normalizeDigits(raw);
  if (id.length < 6) return '•' * id.length;
  return '${id.substring(0, 2)}${'•' * (id.length - 4)}${id.substring(id.length - 2)}';
}

/// رقم موبايل مصري: 01X + 8 أرقام. بيقبل +20 / 0020 / 20.
String normalizeEgyptPhone(String raw) {
  var d = normalizeDigits(raw);
  if (d.startsWith('0020')) d = d.substring(4);
  if (d.startsWith('20') && d.length == 12) d = d.substring(2);
  if (d.length == 10 && d.startsWith('1')) d = '0$d';
  return d;
}

bool isValidEgyptMobile(String raw) =>
    RegExp(r'^01[0125]\d{8}$').hasMatch(normalizeEgyptPhone(raw));

/// توحيد الأسماء للمقارنة: حذف التشكيل والمسافات الزايدة وتوحيد الهمزات والياء/التاء المربوطة.
String normalizeArabicName(String s) {
  var t = s.replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
