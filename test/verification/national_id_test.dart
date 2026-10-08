import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/verification/domain/national_id.dart';
import 'package:wasalha/features/verification/domain/unique_keys.dart';

void main() {
  final now = DateTime(2026, 10, 4);

  group('parseNationalId', () {
    test('رقم صحيح من القرن العشرين', () {
      final i = parseNationalId('29001011234567', now: now)!;
      expect(i.birthDate, DateTime(1990, 1, 1));
      expect(i.governorateCode, '12');
    });

    test('النوع من الخانة 13 (فردي = ذكر، زوجي = أنثى)', () {
      expect(parseNationalId('29001011234577', now: now)!.isMale, isTrue); // الخانة 13 = 7
      expect(parseNationalId('29001011234567', now: now)!.isMale, isFalse); // الخانة 13 = 6
    });

    test('القرن 21', () {
      expect(parseNationalId('30501011234567', now: now)!.birthDate, DateTime(2005, 1, 1));
    });

    test('أرقام عربية ومسافات', () {
      expect(isValidNationalId('٢٩٠٠١٠١١٢٣٤٥٦٧', now: now), isTrue);
      expect(isValidNationalId('2900 1011 2345 67', now: now), isTrue);
    });

    test('أخطاء: الطول، القرن، التاريخ، المحافظة، المستقبل', () {
      expect(isValidNationalId('2900101123456', now: now), isFalse); // 13 رقم
      expect(isValidNationalId('19001011234567', now: now), isFalse); // قرن غلط
      expect(isValidNationalId('29002301234567', now: now), isFalse); // 30 فبراير... شهر 02 يوم 30
      expect(isValidNationalId('29013011234567', now: now), isFalse); // شهر 13
      expect(isValidNationalId('29001019934567', now: now), isFalse); // محافظة 99
      expect(isValidNationalId('32701011234567', now: now), isFalse); // ميلاد في المستقبل
    });
  });

  test('ageOn', () {
    final b = DateTime(2000, 10, 5);
    expect(ageOn(b, DateTime(2026, 10, 4)), 25);
    expect(ageOn(b, DateTime(2026, 10, 5)), 26);
  });

  test('maskNationalId يظهر أول رقمين وآخر رقمين فقط', () {
    final m = maskNationalId('29001011234567');
    expect(m.startsWith('29'), isTrue);
    expect(m.endsWith('67'), isTrue);
    expect(m.length, 14);
    expect(m.substring(2, 12).replaceAll('•', ''), isEmpty);
  });

  group('الهاتف', () {
    test('تطبيع الصيغ المختلفة', () {
      for (final p in ['01012345678', '+201012345678', '00201012345678', '٠١٠١٢٣٤٥٦٧٨', '1012345678']) {
        expect(normalizeEgyptPhone(p), '01012345678', reason: p);
      }
    });
    test('صحة الموبايل المصري', () {
      expect(isValidEgyptMobile('01512345678'), isTrue);
      expect(isValidEgyptMobile('01312345678'), isFalse);
      expect(isValidEgyptMobile('0101234'), isFalse);
    });
  });

  test('تطبيع الاسم للمقارنة', () {
    expect(normalizeArabicName('  أَحمد   مُحمّد '), normalizeArabicName('احمد محمد'));
    expect(normalizeArabicName('فاطمة'), normalizeArabicName('فاطمه'));
  });

  group('منع الازدواج: المفاتيح الفريدة (نفس نتائج functions/verification.js)', () {
    const nid = 'nid_e35fb85ab07e0a5d2dd025c5875bbef7775878acabfeaef5bd9e98fd69b3d184';
    const phone = 'phone_e60124f2fe2045215abda1ae912aa80bb66dab5fc231a758387682c9c0e70c01';

    test('نفس القيمة بصيغ مختلفة = نفس المفتاح', () {
      expect(uniqueKeyId(UniqueKeyType.nid, '29001011234567'), nid);
      expect(uniqueKeyId(UniqueKeyType.nid, '٢٩٠٠١٠١١٢٣٤٥٦٧'), nid);
      expect(uniqueKeyId(UniqueKeyType.nid, '2900 1011 2345 67'), nid);
      for (final p in ['01012345678', '+201012345678', '00201012345678']) {
        expect(uniqueKeyId(UniqueKeyType.phone, p), phone);
      }
    });

    test('قيم مختلفة = مفاتيح مختلفة، والفاضي = null', () {
      expect(uniqueKeyId(UniqueKeyType.nid, '29001011234568'), isNot(nid));
      expect(uniqueKeyId(UniqueKeyType.nid, ''), isNull);
    });

    test('اللوحة والرخصة: تجاهل المسافات والشرطات وتوحيد الأرقام', () {
      expect(uniqueKeyId(UniqueKeyType.plate, 'أ ب ج 123'), uniqueKeyId(UniqueKeyType.plate, 'ا-ب-ج ١٢٣'));
      expect(uniqueKeyId(UniqueKeyType.license, 'AB-123 456'), uniqueKeyId(UniqueKeyType.license, 'ab123456'));
    });

    test('نوع المفتاح جزء من المعرّف (نفس القيمة بنوعين مختلفين لا تتصادم)', () {
      expect(uniqueKeyId(UniqueKeyType.license, '12345678'), isNot(uniqueKeyId(UniqueKeyType.plate, '12345678')));
    });
  });
}
