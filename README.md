# وصلها — نسخة Flutter

نقل تطبيق وصلها (React/Capacitor) إلى Flutter بنفس الألوان والتصميم والمنطق ونفس مشروع Firebase (`sada-51292`).

## التشغيل
```bash
bash setup_android.sh          # مرة واحدة: يولّد مشروع الأندرويد ويطبّق الأيقونات والصلاحيات
flutterfire configure --project=sada-51292 --platforms=android --android-package-name=com.wasalah.app
flutter run
```
تسجيل الدخول بجوجل: لازم بصمة SHA-1 لمفتاح التوقيع تتسجل في Firebase Console (بدون Web Client ID، مطلوب فقط google-services.json).

## ملاحظة مهمة عن مصادر البيانات
الكود الأصلي فيه ملفين تعريفات مختلفين وغير متطابقين:
- `constants.ts` (بالجذر) — **غير مستخدم فعلياً** في أي شاشة حية، لكن قوائم
  `adminEmails` و`centers` فيه مطابقة لنفس القيم المكتوبة inline في
  `Login.tsx`/`App.tsx` الحقيقيين، فاستخدمناها كمرجع مريح لهذه القيم فقط
  (`lib/constants.dart`).
- `config/constants.ts` — **هو المصدر الحقيقي** المستخدم في كل الشاشات الحية
  (10 مراكز، تسعير مختلف تماماً) → منقول بالكامل في `lib/config_constants.dart`
  ومستخدم في `CustomerDashboard` وكل الشاشات المرتبطة به.

تم الإبقاء على هذا التناقض كما هو بالحرف الواحد التزاماً بطلب عدم تغيير أي منطق.

## حالة النقل
| الجزء | الحالة |
|---|---|
| الثيم (ألوان Tailwind، خط Cairo، ظلال، RTL) | ✅ |
| Models / constants (كلا المصدرين) / utils / order_service | ✅ |
| Firebase (Auth + Firestore + FCM) | ✅ |
| Onboarding + Login (كل التدفقات) | ✅ |
| App shell (الهيدر، الخروج، الإشعارات، التوجيه) | ✅ |
| **CustomerDashboard كاملة** (مشوار/مطاعم/صيدلية + تتبع حي + تقييم + خرائط) | ✅ |
| RestaurantMenuView / ManualRestaurantView / AdsSlider / AdDetailsView | ✅ |
| ChatView / WalletView / ProfileView / ActivityView | ✅ |
| **CourierDashboard كاملة** (أونلاين/أوفلاين + عروض الأسعار + تتبع GPS حي + خريطة كاملة الشاشة) | ✅ |
| Notifications (FCM حقيقي عبر firebase_messaging) / Support Views | ✅ |
| **كل شاشات الإدارة الـ 6** (SuperAdmin + Operator + إدارة المستخدمين/المطاعم/الإعلانات/الجغرافيا) | ✅ |

## المشروع مكتمل بالكامل الآن 🎉
كل الشاشات الـ 23 منقولة بمنطقها وتصميمها الأصلي حرفياً (~17,400 سطر Dart).

## اعتماديات جديدة (Dart packages فقط، بدون أي تعديل على النسخة الأصلية)
- `flutter_map` + `latlong2` بديل Leaflet
- `file_selector` لاختيار الصور (روشتة الصيدلية، صورة البروفايل)
- `geolocator` لتتبع موقع الكابتن الحي (بديل navigator.geolocation.watchPosition)
- `http` لطلبات OSRM (المسار الفعلي)

## الإشعارات والأذونات (تحديث)
- أول فتح للتطبيق: شاشة شرح ثم طلب إذن الإشعارات والموقع (`lib/services/permission_service.dart`).
- إشعارات محلية + FCM + مستمع Firestore (`lib/services/notification_service.dart`).
- العميل بيطلب مشوار ← الكباتن الأونلاين بيوصلهم إشعار. الكابتن يقدّم سعر ← العميل بيوصله إشعار ويختار الأنسب.
- للإشعارات والتطبيق مقفول: انشر الـ Cloud Function في `functions/` (شوف `functions/README.md`).

## تأكيد البريد الإلكتروني
حسابات الإيميل/الباسورد لازم تأكد بريدها (رابط من Firebase Auth) قبل دخول التطبيق. الحسابات في `verificationExemptEmails` (`lib/constants.dart`) وحسابات جوجل مستثناة. الشاشة: `lib/screens/verify_email_screen.dart`، والبوابة في `app_shell.dart`. تقدر تعدّل نص الإيميل واللغة من Firebase Console ← Authentication ← Templates.

## قواعد Firestore
ملف `firestore.rules` في جذر المشروع. انشره من Firebase Console ← Firestore Database ← Rules ← الصق المحتوى ← Publish.
أهم اللي بتفرضه:
- المستخدم ما يقدرش يغيّر رتبته أو حالته أو رصيد محفظته (المدير بس).
- الحساب الجديد يبدأ عميل/كابتن بمحفظة صفر. حساب ADMIN بيتعمل بس بإيميل أدمن متأكد (أو من الكونسول).
- كل الكتابات تتطلب بريد متأكد (حسابات جوجل وإيميلات الأدمن مستثناة) وحساب غير معطّل.
- الحساب المعطّل ما يتفعّلش من التطبيق: المطوّر بس من Firebase Console (غيّر `status` إلى `APPROVED` في وثيقة المستخدم).
- الرسائل الجماعية (`ADMIN_MESSAGE`) والإشعارات لـ `ALL` للمدير والمشغّل بس.
- السوبر أدمن: superadmin@ashmoun.com. المشغّل: admin@ashmoun.com (رتبته OPERATOR من إدارة الأعضاء). لو أضفت إيميل أدمن جديد: ضيفه في `adminEmails` في `lib/constants.dart` وفي دالة `adminEmails()` داخل القواعد.

## الرسائل الجماعية
المدير (من لوحة التحكم ← "رسالة للمستخدمين") والمشغّل (زر في رأس لوحة المشغّل) يقدروا يبعتوا لكل المستخدمين أو العملاء أو الكباتن.
بتتكتب نسخة إشعار لكل مستخدم، وبتوصل Push تلقائياً لو الـ Cloud Function متفعّلة (`functions/`).

## تعطيل الحساب
المدير يعطّل أي حساب غير أدمن من شاشة تعديل العضو. المستخدم بيشوف شاشة "تم تعطيل حسابك" وزر واتساب للمطوّر (`developerWhatsApp` في `lib/constants.dart`).

## المستثنون من تأكيد البريد ورقم الهاتف
`verificationExemptEmails` في `lib/constants.dart` (admin@ashmoun.com, superadmin@ashmoun.com). لو غيّرت القائمة، غيّر دالة `exemptEmails()` في `firestore.rules` كمان.

## تسجيل الدخول بجوجل (Native)
بيستخدم `google_sign_in` (قايمة حسابات جوجل جوه التطبيق من غير متصفح). لازم: `google-services.json` محدّث من Firebase بعد إضافة SHA-1 و SHA-256 للتوقيع، وتفعيل Google في Authentication.

## الإشعارات والتطبيق مقفول
- الـ relay (`apps_script/Code.gs`) والـ Cloud Function بيبعتوا FCM بـ notification + data، فأندرويد بيعرضه لوحده.
- بعد أي تعديل في `Code.gs`: Deploy ← Manage deployments ← Edit ← New version.
- الرسائل الجماعية: التطبيق بيكتب إشعار لكل مستخدم + طلب واحد للـ relay (`broadcast: true`) والـ relay بيتأكد إن المرسل ADMIN/OPERATOR.
- لو المستخدم عمل Force stop للتطبيق أو الموبايل بيقتل التطبيقات (بعض أجهزة شاومي/سامسونج): فعّل "Autostart" وشيل التطبيق من توفير البطارية.


## Firebase Storage (صور الروشتة)
صورة الروشتة بتترفع على `prescriptions/{uid}/...` ويتحفظ رابطها في الطلب (بدل base64 جوه الوثيقة).
فعّل Storage من Firebase Console، وانشر `storage.rules`:
`firebase deploy --only storage` (أو Console ← Storage ← Rules).
لو الرفع فشل والصورة أكبر من ~700 ك حرف، الطلب مبيتبعتش ويظهر للعميل رسالة.

## تقييم الكابتن وآراء العملاء (v22)
- بعد ما العميل يضغط "تم الاستلام بالفعل" بيظهر له تقييم (نجوم + تعليق اختياري) في نفس الكارت.
  لو ما قيّمش لحد ما الكابتن يأكد التسليم، شاشة "وصلت بالسلامة" بتفضل ظاهرة (لحد 7 أيام) فيها
  إرسال التقييم أو "تخطي التقييم".
- التقييم بيتخزن في `reviews/{orderId}` (تقييم واحد لكل طلب، مفيش تعديل) وبيتحدّث الطلب
  (`rating`/`feedback`/`ratedAt`) في نفس الـ batch.
- واجهة الآراء: تبويب "الآراء" عند المشغّل، وبطاقة "آراء وتقييمات العملاء" عند السوبر أدمن:
  ملخص، فلتر بالنجوم/بتعليق/كابتن، بحث، كباتن الأقل تقييمًا. حذف التعليق للسوبر أدمن بس.
- لازم تنشر `firestore.rules` الجديدة (فيها `match /reviews/{orderId}`).

## توثيق الكباتن (v23)
نظام توثيق متعدد الطبقات **داخل التطبيق** بدون مزوّد KYC خارجي، والقرار النهائي دايمًا **مراجعة بشرية من السوبر أدمن**
(مش AI). أي فحص آلي هنا مؤشر مساعد، وليس إثباتًا قانونيًا لأصالة البطاقة أو كشفًا للتزوير.

**الكود:** `lib/features/verification/` (domain: المنطق القابل للاختبار، data: Firestore/Storage، ui: شاشة الكابتن + الكاميرا + لوحة الأدمن) و`functions/verification.js`.

**الطبقات**
| الطبقة | الحالة |
|---|---|
| 1 تصوير من داخل التطبيق (إطار إرشادي، بدون معرض) | مُنفّذ |
| 2 جودة الصورة (دقة، وضوح، سطوع، انعكاس) | مُنفّذ (عتبات تقديرية: اضبطها على أجهزة حقيقية) |
| 3 OCR + مطابقة البيانات | **NOT AVAILABLE WITH CURRENT DEPENDENCIES** (الدالة `compareIdentity` جاهزة لما يتوفر OCR) |
| 4 مؤشر خطر المستند | جودة/شكل الصورة + تكرار نفس الصورة بين حسابات. أفضل نتيجة ممكنة `UNABLE_TO_DETERMINE` (مفيش LOW_RISK) |
| 5 سيلفي + Liveness | سيلفي بالبطاقة + إطارين (يمين/يسار) للمراجعة البشرية. `LIVENESS = UNABLE_TO_VERIFY` (مفيش Liveness آلي) |
| 6 Face Match | **NOT AVAILABLE** (`UNAVAILABLE`) |
| 7 مراجعة الأدمن | مُنفّذ: اعتماد / تصحيح / رفض / تعليق / إعادة تفعيل بسبب مسجّل |

**المتطلبات حسب المركبة:** `requiredDocuments(vehicleType)` في `document_requirements.dart` هي المصدر الوحيد
(سيارة = رخصة قيادة + رخصة مركبة بتاريخ انتهاء + صورة مركبة بلوحة). لإضافة نوع: أضفه في `kVehicleDocs`
**وفي** `VEHICLE_DOCS` داخل `functions/verification.js` (والقاعدة `docsComplete` في `firestore.rules` لو يحتاج مستندات).

**الحماية في السيرفر (مش بس Flutter)**
- `firestore.rules`: `driverGateOk()` بتمنع إنشاء عرض وتعيين `driverId/assignedTo` لكابتن بدون بوابة سليمة.
- البوابة `gate` بتحسبها Cloud Function (`emailVerified` من Auth + VERIFIED + المستندات المعتمدة + الصلاحية + الحساب نشط + عدم التكرار) والكلاينت ما يقدرش يكتبها. `gate.validUntil` = أقرب انتهاء، فالمنع بيحصل في وقته حتى لو الـ Function واقفة.
- `config/verification.enforced` مفتاح التشغيل (افتراضيًا **مقفول** عشان الكباتن الحاليين ما يتوقفوش). فعّله من لوحة "توثيق الكباتن" **بعد** نشر الـ Functions.
- منع الازدواج (رقم قومي، موبايل، رخصة، لوحة): `unique_keys/{type_hash}` بتكتبها الـ Function فقط، ولو القيمة عند كابتن تاني بتظهر علامة `DUPLICATE_*` وتمنع الاستقبال.
- المستندات في `captain_docs/{uid}/{type}/vN.jpg` خاصة، إنشاء فقط (بدون استبدال/حذف)، والأدمن بيقرأها بـ `getData` (من غير روابط تحميل). المشغّل (OPERATOR) **ممنوع** من بيانات الهوية.
- سجل المراجعة `…/audit` إضافة فقط. تسجيل فتح الملف (`DOCUMENT_ACCESSED`) بيتم من الكلاينت، فهو مش مانع لأدمن بيقرأ Storage مباشرة.

**الصلاحية:** الدالة المجدولة `verificationExpirySweep` (يوميًا 03:00 القاهرة): تذكير قبل 30 يوم، وتذكير عاجل قبل 7 أيام، وبعد الانتهاء الحالة `EXPIRED`. النسخ القديمة بتفضل محفوظة (v1, v2, ...).

**النشر (بالترتيب)**
1. `cd functions && npm install && npm test` ثم `firebase deploy --only functions` (محتاج Blaze).
2. فعّل فهرس collection-group على `documents.sha256` (`firestore.indexes.json`) أو من الكونسول. (لو ناقص، فحص الصور المكررة بيتخطى ولا يكسر باقي الحسابات.)
3. `firebase deploy --only firestore:rules,storage` (قاعدة Storage بتقرأ دور المستخدم من Firestore: وافق على منح الصلاحية لو الكونسول طلبها).
4. وزّع التطبيق، ولما معظم الكباتن يوثّقوا فعّل الإلزام.

**الإقرار:** نص مسودة تشغيلية (ليست رأيًا قانونيًا). بيتحفظ `captainId + termsVersion + acceptedAt + acceptedDocumentHash`. النسخة 1.1 فيها بند رسوم المنصة (5 جنيه ثابتة على كل مشوار مكتمل). مفيش بيانات ضامن في التوثيق. راجع الإقرار والاحتفاظ بالبيانات مع محامٍ ومع قانون حماية البيانات الشخصية رقم 151 لسنة 2020.

## قواعد تسعير المشوار

- `Final Fare = MAX(Calculated Fare, 25)` — الحد الأدنى 25 ج.م لكل المركبات.
- عمولة التطبيق ثابتة 5 ج.م (مش نسبة) وبتتخصم من قيمة الرحلة، مش بتتضاف على العميل.
- `Driver Earnings = Final Fare - 5`.
- كل الحساب في `lib/pricing.dart` (`finalFare`, `driverEarnings`, `tripFareOf`)، والعميل بيشوف السعر النهائي بس.
- الاختبار: `flutter test test/pricing/pricing_test.dart`.
