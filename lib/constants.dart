// نسخة Dart من constants.ts — نفس القيم بالظبط.
import 'models/models.dart';

/// رسوم المنصة الثابتة على كل مشوار مكتمل (بالجنيه). مش نسبة مئوية.
const double platformFeePerTrip = 5;

/// القائمة الشاملة والنهائية لقرى وعزب مركز أشمون (المنوفية)
/// تم تجميعها بناءً على الوحدات المحلية لضمان التغطية الجغرافية الكاملة
const List<Village> ashmounVillages = [
  // مدينة أشمون
  Village(id: 'ash-city', name: 'أشمون (المدينة)', center: LatLngPoint(30.2986, 30.9753)),
  // وحدة شما
  Village(id: 'v-shamma', name: 'شما', center: LatLngPoint(30.3122, 30.9658)),
  Village(id: 'v-khadra', name: 'الخضرة', center: LatLngPoint(30.3200, 30.9700)),
  // وحدة سمادون
  Village(id: 'v-samadoun', name: 'سمادون', center: LatLngPoint(30.2858, 30.9636)),
  Village(id: 'v-ezbet-samadoun', name: 'عزبة سمادون', center: LatLngPoint(30.2916, 30.9709)),
  Village(id: 'v-smalay', name: 'سملاي', center: LatLngPoint(30.2750, 30.9550)),
  // وحدة سنتريس
  Village(id: 'v-santes', name: 'سنتريس', center: LatLngPoint(30.3008, 30.9439)),
  Village(id: 'v-mansh-santes', name: 'منشأة سنتريس', center: LatLngPoint(30.3050, 30.9400)),
  Village(id: 'v-kohafa', name: 'كفر قورص', center: LatLngPoint(30.3100, 30.9450)),
  Village(id: 'v-qours', name: 'قورص', center: LatLngPoint(30.3150, 30.9500)),
  // وحدة طهواي
  Village(id: 'v-tahway', name: 'طهواي', center: LatLngPoint(30.3089, 30.9322)),
  Village(id: 'v-dalhamou', name: 'دلهمو', center: LatLngPoint(30.3150, 30.9250)),
  Village(id: 'v-ezbet-tahway', name: 'عزبة طهواي', center: LatLngPoint(30.3050, 30.9250)),
  // وحدة ساقية أبو شعرة
  Village(id: 'v-saqia', name: 'ساقية أبو شعرة', center: LatLngPoint(30.3256, 30.9394)),
  Village(id: 'v-shatanouf', name: 'شطانوف', center: LatLngPoint(30.3297, 30.9268)),
  Village(id: 'v-hallawsi', name: 'الحلواصي', center: LatLngPoint(30.3300, 30.9350)),
  Village(id: 'v-kfr-mansh', name: 'كفر منصور', center: LatLngPoint(30.3350, 30.9400)),
  // وحدة سبك الأحد
  Village(id: 'v-sabk', name: 'سبك الأحد', center: LatLngPoint(30.3219, 30.9981)),
  Village(id: 'v-shanshour', name: 'شنشور', center: LatLngPoint(30.2799, 30.9507)),
  Village(id: 'v-bra-shanshour', name: 'براهيم', center: LatLngPoint(30.2750, 30.9450)),
  Village(id: 'v-kfr-sabk', name: 'كفر سبك الأحد', center: LatLngPoint(30.3250, 31.0050)),
  // وحدة جريس
  Village(id: 'v-gris', name: 'جريس', center: LatLngPoint(30.3361, 30.9812)),
  Village(id: 'v-monsha-gris', name: 'منشأة جريس', center: LatLngPoint(30.3400, 30.9850)),
  Village(id: 'v-abu-raqaba', name: 'أبو رقبة', center: LatLngPoint(30.3450, 30.9750)),
  Village(id: 'v-kfr-abu-raqaba', name: 'كفر أبو رقبة', center: LatLngPoint(30.3500, 30.9800)),
  // وحدة منشأة سلطان
  Village(id: 'v-monsha-sultan', name: 'منشأة سلطان', center: LatLngPoint(30.3550, 31.0100)),
  Village(id: 'v-amreia', name: 'العامرية', center: LatLngPoint(30.3600, 31.0150)),
  Village(id: 'v-kfr-amreia', name: 'كفر العامرية', center: LatLngPoint(30.3650, 31.0200)),
  // وحدة رملة الأنجب
  Village(id: 'v-ramla-anjab', name: 'رملة الأنجب', center: LatLngPoint(30.3750, 30.9900)),
  Village(id: 'v-anjab', name: 'الأنجب', center: LatLngPoint(30.3800, 31.0000)),
  Village(id: 'v-kawadi', name: 'الكوادي', center: LatLngPoint(30.3850, 31.0100)),
  Village(id: 'v-lawaizeh', name: 'اللوايزة', center: LatLngPoint(30.3900, 31.0200)),
  // وحدة طليا
  Village(id: 'v-talia', name: 'طليا', center: LatLngPoint(30.2450, 30.9350)),
  Village(id: 'v-barania', name: 'البرانية', center: LatLngPoint(30.2400, 30.9250)),
  Village(id: 'v-kfr-barania', name: 'كفر البرانية', center: LatLngPoint(30.2350, 30.9150)),
  Village(id: 'v-el-kawady-talia', name: 'الكوادي (طليا)', center: LatLngPoint(30.2300, 30.9050)),
  // وحدة دروة
  Village(id: 'v-darwa', name: 'دروة', center: LatLngPoint(30.2500, 30.9800)),
  Village(id: 'v-khyria', name: 'الخيرية', center: LatLngPoint(30.2450, 30.9850)),
  Village(id: 'v-sandafeis', name: 'صندفيس', center: LatLngPoint(30.2400, 30.9900)),
  // مناطق وعزب متفرقة
  Village(id: 'v-ramla', name: 'الرملة', center: LatLngPoint(30.2700, 30.9900)),
  Village(id: 'v-ezbet-bakr', name: 'عزبة بكر', center: LatLngPoint(30.3000, 30.9850)),
  Village(id: 'v-ezbet-aly', name: 'عزبة علي', center: LatLngPoint(30.3050, 30.9900)),
  Village(id: 'v-ashma-village', name: 'أشما', center: LatLngPoint(30.2950, 30.9500)),
  Village(id: 'v-qanatir', name: 'منطقة القناطر', center: LatLngPoint(30.2200, 31.0100)),
];

final List<Zone> ashmounZones = [
  Zone(
    id: 'zone_ashmoun_full',
    name: 'منظومة مشوار أشمون',
    operatorId: 'op_ashmoun_main',
    pricing: Pricing(
      basePrice: 12,
      pricePerKm: 6,
      minPrice: 25,
      maxPrice: 400,
      sameVillagePrice: 15,
      multipliers: {
        VehicleType.motorcycle: 0.85,
        VehicleType.toktok: 1.0,
        VehicleType.car: 1.75,
      },
    ),
    center: LatLngPoint(30.2986, 30.9753),
  ),
];

class StorageKeys {
  StorageKeys._();
  static const orders = 'meshwar_ashmoun_v3_orders';
  static const users = 'meshwar_ashmoun_v3_users';
  static const zones = 'meshwar_ashmoun_v3_zones';
  static const currentUser = 'meshwar_ashmoun_v3_auth';
}

final Pricing defaultPricing = ashmounZones.isNotEmpty
    ? ashmounZones.first.pricing
    : Pricing(
        basePrice: 12,
        pricePerKm: 6,
        minPrice: 25,
        maxPrice: 400,
        sameVillagePrice: 15,
        multipliers: {
          VehicleType.motorcycle: 0.85,
          VehicleType.toktok: 1.0,
          VehicleType.car: 1.75,
        },
      );

/// المراكز المتاحة في شاشة التسجيل (من Login.tsx)
const List<String> centers = [
  'شبين الكوم',
  'منوف',
  'أشمون',
  'الباجور',
  'قويسنا',
  'بركة السبع',
  'تلا',
  'السادات',
  'الشهداء',
];

/// إيميلات الأدمن (السوبر أدمن بس). admin@ashmoun.com حساب مشغّل (OPERATOR)
/// ورتبته بتتظبط من إدارة الأعضاء، مش من هنا.
const List<String> adminEmails = [
  'superadmin@ashmoun.com',
];

/// حسابات مستثناة من تأكيد البريد الإلكتروني ومن إلزام رقم الهاتف.
/// (لازم تطابق دالة exemptEmails() في firestore.rules)
const List<String> verificationExemptEmails = [
  'admin@ashmoun.com',
  'superadmin@ashmoun.com',
];

bool isExemptEmail(String? email) =>
    verificationExemptEmails.contains((email ?? '').trim().toLowerCase());

/// رقم واتساب المطوّر: الحسابات المعطّلة بيرجع لها بس عن طريقه.
const String developerWhatsApp = '201065019364';

/// رقم افتراضي كان بيتحط تلقائياً للحسابات الجديدة: مش رقم حقيقي.
const String placeholderPhone = '01000000000';

/// رقم موبايل مصري صحيح (010 / 011 / 012 / 015) وليس الرقم الافتراضي.
bool isValidPhone(String? phone) {
  final p = (phone ?? '').trim();
  if (p == placeholderPhone) return false;
  return RegExp(r'^(010|011|012|015)[0-9]{8}$').hasMatch(p);
}
