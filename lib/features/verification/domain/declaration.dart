import 'dart:convert';

import 'package:crypto/crypto.dart';

/// نسخة نص الإقرار الحالية. أي تغيير في النص = نسخة جديدة (1.1، 1.2، 2.0...).
/// 1.1: إضافة بند رسوم المنصة (5 جنيه على كل مشوار) وحذف بيانات الضامن.
/// مسودة تشغيلية وليست رأيًا قانونيًا: لازم يراجعها محامٍ قبل الاعتماد.
const String kTermsVersion = '1.1';

/// نص الإقرار حرفيًا كما اعتمده صاحب المنتج.
const String kDeclarationText =
    'أقر أنا الكابتن بأن جميع البيانات والمستندات التي قدمتها إلى منصة Waselha صحيحة وسارية، وأتعهد بعدم تقديم مستندات غير صحيحة أو استخدام حساب أو بيانات شخص آخر.\n\n'
    'أتعهد بالمحافظة على صلاحية المستندات المطلوبة وتحديثها عند انتهاء صلاحيتها، وعدم مشاركة حسابي أو تمكين أي شخص آخر من استخدامه.\n\n'
    'كما أتعهد بالمحافظة على الطلبات والبضائع والأموال والعهد التي يتم تسليمها إليّ، وتنفيذ الطلبات وفق البيانات والتعليمات المعتمدة من المنصة، وعدم تسجيل أي طلب كمُسلَّم إلا بعد إتمام التسليم فعليًا.\n\n'
    'أوافق على استخدام بيانات الموقع أثناء تنفيذ الطلبات بالقدر اللازم لتشغيل الخدمة وتتبع الطلب وإثبات مراحل التنفيذ وحماية حقوق الأطراف ومعالجة الشكاوى والنزاعات.\n\n'
    'كما أوافق على جمع ومعالجة وحفظ بياناتي ومستنداتي اللازمة للتحقق من هويتي وأهليتي واستخدام خدمات المنصة، وفقًا للقوانين والسياسات المعمول بها.\n\n'
    'وأتعهد بعدم التلاعب بالمنصة أو بيانات الموقع أو الطلبات أو محاولة تجاوز أنظمة الحماية أو الحصول على مبالغ أو مزايا بطرق غير مشروعة.\n\n'
    'وأقر بعلمي وموافقتي على أن للمنصة رسومًا ثابتة قدرها 5 جنيهات (خمسة جنيهات مصرية) عن كل مشوار يتم تسليمه فعليًا، وليست نسبة من أجرة المشوار، وتُحتسب على أساس عدد المشاوير المكتملة، وألتزم بسدادها للمنصة وفقًا لما تحدده المنصة.\n\n'
    'وأقر بأن للمنصة، وفقًا للقانون وشروط الاستخدام، الحق في تعليق أو تقييد الحساب أو منع استقبال الطلبات عند وجود مخالفة أو انتهاء مستند أو وجود مشكلة في التوثيق.\n\n'
    'أقر بأنني قرأت وفهمت ما سبق، وأوافق عليه إلكترونيًا.';

const String kDeclarationCheckboxLabel = 'أوافق على الإقرار والتعهد';

/// SHA-256 (hex) لنص الإقرار مع رقم النسخة: بيثبت بالظبط أنهي نص الكابتن وافق عليه.
String declarationHash({String text = kDeclarationText, String version = kTermsVersion}) =>
    sha256.convert(utf8.encode('$version\n$text')).toString();

/// SHA-256 (hex) لأي بايتات (بصمة الصورة).
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// موافقة الكابتن المسجّلة. مش مجرد accepted=true.
class DeclarationAcceptance {
  final String captainId;
  final String termsVersion;
  final int acceptedAt; // millis
  final String acceptedDocumentHash;

  const DeclarationAcceptance({
    required this.captainId,
    required this.termsVersion,
    required this.acceptedAt,
    required this.acceptedDocumentHash,
  });

  /// موافقة على النص الحالي.
  factory DeclarationAcceptance.now(String captainId, {DateTime? at}) =>
      DeclarationAcceptance(
        captainId: captainId,
        termsVersion: kTermsVersion,
        acceptedAt: (at ?? DateTime.now()).millisecondsSinceEpoch,
        acceptedDocumentHash: declarationHash(),
      );

  /// الموافقة دي على النص والنسخة الحاليين بالظبط؟
  bool get isCurrent =>
      termsVersion == kTermsVersion && acceptedDocumentHash == declarationHash();

  Map<String, dynamic> toMap() => {
        'captainId': captainId,
        'termsVersion': termsVersion,
        'acceptedAt': acceptedAt,
        'acceptedDocumentHash': acceptedDocumentHash,
      };

  static DeclarationAcceptance? fromMap(Object? m) {
    if (m is! Map) return null;
    final at = m['acceptedAt'];
    if (m['captainId'] is! String ||
        m['termsVersion'] is! String ||
        m['acceptedDocumentHash'] is! String ||
        at is! num) {
      return null;
    }
    return DeclarationAcceptance(
      captainId: m['captainId'] as String,
      termsVersion: m['termsVersion'] as String,
      acceptedAt: at.toInt(),
      acceptedDocumentHash: m['acceptedDocumentHash'] as String,
    );
  }
}
