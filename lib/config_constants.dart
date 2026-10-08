// نسخة Dart من config/constants.ts — هذا هو الملف الفعلي المستخدم في كل
// شاشات التطبيق الحية (CustomerDashboard, ProfileView, ActivityView,
// OperatorDashboard, AdminGeographyManager, AdminRestaurantManager).
// ملاحظة: يختلف عن lib/constants.dart (المقابل لـ constants.ts بالجذر وهو
// ملف غير مستخدم فعلياً في نسخة الويب الحية) — تم الإبقاء عليهما منفصلين
// عمداً لمطابقة التناقض الموجود في الكود الأصلي بالحرف الواحد.
import 'models/models.dart';

/// رسوم المنصة الثابتة على كل مشوار مكتمل (بالجنيه). مش نسبة مئوية.
const double platformFeePerTrip = 5;

/// البيانات الجغرافية الشاملة لمحافظة المنوفية (10 مراكز)
final List<District> menofiaData = [
  District(id: 'd-ashmoun', name: 'أشمون', villages: [
      Village(id: 'ash-city', name: 'مدينة أشمون', center: LatLngPoint(30.2931, 30.9863)),
      Village(id: 'v-shamma', name: 'شما', center: LatLngPoint(30.3340, 30.9420)),
      Village(id: 'v-tahway', name: 'طهواي', center: LatLngPoint(30.3420, 30.8350)),
      Village(id: 'v-samadoun', name: 'سمادون', center: LatLngPoint(30.2858, 30.9636)),
      Village(id: 'v-santes', name: 'سنتريس', center: LatLngPoint(30.3008, 30.9439)),
      Village(id: 'v-saqia', name: 'ساقية أبو شعرة', center: LatLngPoint(30.3256, 30.9394)),
      Village(id: 'v-sabk', name: 'سبك الأحد', center: LatLngPoint(30.3219, 30.9981)),
      Village(id: 'v-gris', name: 'جريس', center: LatLngPoint(30.3361, 30.9812)),
      Village(id: 'v-shatanouf', name: 'شطانوف', center: LatLngPoint(30.3297, 30.9268)),
      Village(id: 'v-darwa', name: 'دروة', center: LatLngPoint(30.2500, 30.9800)),
      Village(id: 'v-shanshour', name: 'شنشور', center: LatLngPoint(30.2799, 30.9507)),
      Village(id: 'v-talia', name: 'طليا', center: LatLngPoint(30.2450, 30.9350)),
      Village(id: 'v-anjab', name: 'الأنجب', center: LatLngPoint(30.3700, 30.9900)),
      Village(id: 'v-ramla', name: 'رملة الأنجب', center: LatLngPoint(30.3750, 30.9850)),
      Village(id: 'v-khadra', name: 'الخضرة', center: LatLngPoint(30.3200, 30.9700)),
      Village(id: 'v-el-kawady', name: 'الكوادي', center: LatLngPoint(30.3800, 31.0000)),
      Village(id: 'v-monsha-sultan', name: 'منشأة سلطان', center: LatLngPoint(30.3550, 31.0100)),
  ]),
  District(id: 'd-shebin', name: 'شبين الكوم', villages: [
      Village(id: 'shebin-city', name: 'مدينة شبين الكوم', center: LatLngPoint(30.5612, 31.0125)),
      Village(id: 'v-elmay', name: 'الماي', center: LatLngPoint(30.5200, 30.9500)),
      Village(id: 'v-elbetanoun', name: 'البتانون', center: LatLngPoint(30.6100, 31.0500)),
      Village(id: 'v-shanawan', name: 'شنوان', center: LatLngPoint(30.5100, 31.0100)),
      Village(id: 'v-milia', name: 'مليج', center: LatLngPoint(30.6000, 31.0000)),
      Village(id: 'v-bakhati', name: 'بخاتي', center: LatLngPoint(30.5800, 30.9400)),
      Village(id: 'v-shobrabas', name: 'شبرا باص', center: LatLngPoint(30.5400, 30.9700)),
      Village(id: 'v-el-moselha', name: 'المصيلحة', center: LatLngPoint(30.5400, 31.0500)),
      Village(id: 'v-zowat-el-ghazal', name: 'زاوية الغزال', center: LatLngPoint(30.5700, 31.0300)),
      Village(id: 'v-meet-khalaf', name: 'ميت خلف', center: LatLngPoint(30.5300, 31.0400)),
      Village(id: 'v-tobloha', name: 'تبلوها', center: LatLngPoint(30.6300, 31.0200)),
  ]),
  District(id: 'd-menouf', name: 'منوف', villages: [
      Village(id: 'menouf-city', name: 'مدينة منوف', center: LatLngPoint(30.4667, 30.9333)),
      Village(id: 'sers-city', name: 'سرس الليان', center: LatLngPoint(30.4333, 30.9167)),
      Village(id: 'v-feisha', name: 'فيشا الكبرى', center: LatLngPoint(30.4000, 30.9667)),
      Village(id: 'v-barahim', name: 'براهيم', center: LatLngPoint(30.4833, 30.9500)),
      Village(id: 'v-al-haswa', name: 'الحصوة', center: LatLngPoint(30.4500, 30.9000)),
      Village(id: 'v-zowat-rabein', name: 'زاوية رزين', center: LatLngPoint(30.4100, 30.8800)),
      Village(id: 'v-barhoum', name: 'برهيم', center: LatLngPoint(30.4800, 30.9400)),
      Village(id: 'v-tamalay', name: 'تتلا', center: LatLngPoint(30.4900, 30.9100)),
      Village(id: 'v-sanhour', name: 'سنهور', center: LatLngPoint(30.5100, 30.9200)),
      Village(id: 'v-deberky', name: 'دبركي', center: LatLngPoint(30.4200, 30.9800)),
  ]),
  District(id: 'd-sadat', name: 'مدينة السادات', villages: [
      Village(id: 'sadat-center', name: 'مركز المدينة', center: LatLngPoint(30.3833, 30.5000)),
      Village(id: 'v-khatatba', name: 'الخطاطبة', center: LatLngPoint(30.3167, 30.8000)),
      Village(id: 'v-kafr-dawood', name: 'كفر داود', center: LatLngPoint(30.4667, 30.7333)),
      Village(id: 'v-el-akhmas', name: 'الأخماس', center: LatLngPoint(30.4000, 30.6000)),
      Village(id: 'v-el-breigat', name: 'البريجات', center: LatLngPoint(30.3500, 30.7500)),
      Village(id: 'v-el-tahra', name: 'الطاهرة', center: LatLngPoint(30.4200, 30.5500)),
  ]),
  District(id: 'd-bagour', name: 'الباجور', villages: [
      Village(id: 'bagour-city', name: 'مدينة الباجور', center: LatLngPoint(30.4333, 31.0333)),
      Village(id: 'v-meet-afifi', name: 'ميت عفيف', center: LatLngPoint(30.4167, 31.0667)),
      Village(id: 'v-estra', name: 'أسطرنط', center: LatLngPoint(30.4500, 31.0500)),
      Village(id: 'v-behalshai', name: 'بهناي', center: LatLngPoint(30.4000, 31.0000)),
      Village(id: 'v-shonoha', name: 'شنوان (الباجور)', center: LatLngPoint(30.4400, 31.0100)),
      Village(id: 'v-el-khatatba-bagour', name: 'الخضرة (الباجور)', center: LatLngPoint(30.4600, 31.0400)),
      Village(id: 'v-meshirf', name: 'مشيرف', center: LatLngPoint(30.4200, 31.0800)),
      Village(id: 'v-feisha-soghra', name: 'فيشا الصغرى', center: LatLngPoint(30.4100, 31.0200)),
  ]),
  District(id: 'd-quesna', name: 'قويسنا', villages: [
      Village(id: 'quesna-city', name: 'مدينة قويسنا', center: LatLngPoint(30.5500, 31.1333)),
      Village(id: 'v-arab-raml', name: 'عرب الرمل', center: LatLngPoint(30.5167, 31.1500)),
      Village(id: 'v-meet-berra', name: 'ميت برة', center: LatLngPoint(30.5000, 31.1167)),
      Village(id: 'v-taha-shobra', name: 'طه شبرا', center: LatLngPoint(30.5833, 31.1500)),
      Village(id: 'v-ashlim', name: 'أشليم', center: LatLngPoint(30.5300, 31.1800)),
      Village(id: 'v-el-koramia', name: 'الكرامية', center: LatLngPoint(30.5600, 31.1000)),
      Village(id: 'v-shobra-qabala', name: 'شبرا قبالة', center: LatLngPoint(30.5400, 31.1400)),
      Village(id: 'v-meet-sirag', name: 'ميت سراج', center: LatLngPoint(30.5700, 31.1200)),
  ]),
  District(id: 'd-berket', name: 'بركة السبع', villages: [
      Village(id: 'berket-city', name: 'مدينة بركة السبع', center: LatLngPoint(30.6333, 31.0833)),
      Village(id: 'v-horin', name: 'هورين', center: LatLngPoint(30.6167, 31.1167)),
      Village(id: 'v-abu-mashhour', name: 'أبو مشهور', center: LatLngPoint(30.6667, 31.1000)),
      Village(id: 'v-toukh-dalaka', name: 'طوخ طنبشا', center: LatLngPoint(30.6000, 31.0667)),
      Village(id: 'v-el-ghouri', name: 'الغوري', center: LatLngPoint(30.6500, 31.0700)),
      Village(id: 'v-el-dabia', name: 'الضبعة', center: LatLngPoint(30.6200, 31.1000)),
      Village(id: 'v-kafr-el-sheikh-shehata', name: 'كفر الشيخ شحاتة', center: LatLngPoint(30.6400, 31.0900)),
  ]),
  District(id: 'd-tala', name: 'تلا', villages: [
      Village(id: 'tala-city', name: 'مدينة تلا', center: LatLngPoint(30.6833, 30.9500)),
      Village(id: 'v-babel', name: 'بابل', center: LatLngPoint(30.6500, 30.9333)),
      Village(id: 'v-kafr-arab', name: 'كفر العرب', center: LatLngPoint(30.7000, 30.9667)),
      Village(id: 'v-zenara', name: 'زنارة', center: LatLngPoint(30.7167, 30.9167)),
      Village(id: 'v-shobrakhalaf', name: 'شبرا خلفون', center: LatLngPoint(30.6700, 30.9000)),
      Village(id: 'v-el-kawady-tala', name: 'الكوادي (تلا)', center: LatLngPoint(30.7300, 30.9400)),
      Village(id: 'v-meet-abu-el-koum', name: 'ميت أبو الكوم', center: LatLngPoint(30.7500, 30.9200)),
  ]),
  District(id: 'd-shohadaa', name: 'الشهداء', villages: [
      Village(id: 'shohadaa-city', name: 'مدينة الشهداء', center: LatLngPoint(30.6000, 30.8167)),
      Village(id: 'v-zawyat-naura', name: 'زاوية الناعورة', center: LatLngPoint(30.6333, 30.7833)),
      Village(id: 'v-meet-shahala', name: 'ميت شهالة', center: LatLngPoint(30.5833, 30.8333)),
      Village(id: 'v-denashwai', name: 'دنشواي', center: LatLngPoint(30.6167, 30.7500)),
      Village(id: 'v-el-shohada-village', name: 'عزبة الشهداء', center: LatLngPoint(30.5900, 30.8200)),
      Village(id: 'v-kafr-el-sheikh-mansour', name: 'كفر الشيخ منصور', center: LatLngPoint(30.6200, 30.8000)),
      Village(id: 'v-el-atf', name: 'العطف', center: LatLngPoint(30.6400, 30.7700)),
  ]),
];

final List<Village> ashmounVillagesFull =
    menofiaData.expand((d) => d.villages).toList();

class ConfigPricing {
  final double basePrice;
  final double pricePerKm;
  final double minPrice;
  final double maxPrice;
  final double sameVillagePrice;
  final double deliveryBasePrice;
  final double foodOutsidePricePerKm;
  final Map<VehicleType, double> multipliers;
  const ConfigPricing({
    required this.basePrice,
    required this.pricePerKm,
    required this.minPrice,
    required this.maxPrice,
    required this.sameVillagePrice,
    required this.deliveryBasePrice,
    required this.foodOutsidePricePerKm,
    required this.multipliers,
  });
}

const configDefaultPricing = ConfigPricing(
  basePrice: 5,
  pricePerKm: 4,
  minPrice: 25, // = minTripFare في pricing.dart
  maxPrice: 900,
  sameVillagePrice: 25,
  deliveryBasePrice: 30,
  foodOutsidePricePerKm: 3,
  multipliers: {
    VehicleType.motorcycle: 0.85,
    VehicleType.toktok: 1.0,
    VehicleType.car: 2.2,
  },
);
