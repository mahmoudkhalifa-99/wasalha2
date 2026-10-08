# موديول الخريطة والتتبع (Map + Live Tracking)

موديول مستقل: ما بيعتمدش على أي شاشة في التطبيق وما فيش شاشة حالية بتستخدمه
(لحد ما الـ build يتأكد). كل حاجة جوه `lib/features/tracking/` و`lib/core/map/`.

## الطبقات
- `core/map/routing_service.dart` — واجهة `RoutingService` (استبدل OSRM بأي مزوّد).
- `core/map/osrm_routing_service.dart` — OSRM (بدون API key).
- `core/map/map_config.dart` — التايلز والمركز الافتراضي.
- `services/location_service.dart` — الصلاحيات وGPS (geolocator).
- `services/driver_location_source.dart` — قراءة/بث موقع السائق عبر `driver_locations/{id}` (مش users/{id}).
- `controllers/tracking_controller.dart` — الحالة (ValueNotifiers) + throttle المسار.
- `widgets/` + `screens/tracking_screen.dart` — الواجهة.

## الاستخدام
```dart
// العميل بيتابع السائق
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => TrackingScreen(
    role: TrackingRole.customerWatchingDriver,
    driverId: order.driverId,
    customerLocation: LatLng(order.dropoff.lat, order.dropoff.lng),
  ),
));

// السائق (الجهاز بيبث موقعه) — ما تشغّلوش مع courier_dashboard لنفس السائق
TrackingScreen(role: TrackingRole.driverSharing, driverId: user.id,
    customerLocation: LatLng(...));
```

## القواعد المطبّقة
- المسار بيتحسب تاني بس لما السائق يتحرك ≥ 75 متر، أو يبعد ≥ 60 متر عن الخط،
  وبحد أدنى 10 ثواني بين الطلبات، وطلب واحد في نفس الوقت.
- عند فشل الشبكة بنحتفظ بآخر مسار، وبنعيد المحاولة تلقائيًا كل 10 ثواني.
- اشتراك GPS واحد، واشتراك سائق واحد، ومؤقت واحد — كلهم بيتقفلوا في `dispose()`.
- مفيش مفاتيح API. لو غيّرت لمزوّد بمفتاح، مرّره عبر `--dart-define` مش في الكود.

## الواجهة والمعمارية (v11)
```
TrackingScreen (UI)  →  TrackingController / LocationPickerController
                     →  Services: LocationService · RoutingService · GeocodingService · DriverLocationSource
```
- **الكاميرا:** الـ `TrackingController` بيصدر `CameraCommand` (fitBounds / centerOnDriver /
  centerOnMe / centerOnSelectedLocation) والـ `TrackingMap` بس هو اللي بينفّذها بـ `MapController`.
  fitBounds مرة واحدة عند الفتح، وبعد ما المستخدم يحرّك الخريطة مفيش تحريك أوتوماتيك.
- **اختيار موقع:** `TrackingScreenMode.pickLocation` أو زر الشريط العلوي. Pin ثابت، debounce 500ms،
  Reverse Geocoding بعد التوقف فقط، ورقم نسخة بيتجاهل أي رد قديم. الاعتماد بيستدعي
  `onLocationSelected(SelectedLocation)` وبعدها (لو `applySelectionAsDestination`) `setDestination`
  — ودي الحالة الوحيدة اللي اختيار موقع بيتحول فيها لطلب Routing.
- **الحداثة:** `Freshness` = LIVE / STALE / WAITING / UNAVAILABLE بعتبات في `TrackingConfig`
  (30 ثانية / 10 دقائق). **دقة GPS:** `maxAcceptedAccuracyMeters` (افتراضي 50 م) — النقطة السيئة بتتجاهل
  والتتبع بيكمّل.
- **التايلز الافتراضية:** OpenStreetMap الرسمية (CARTO بقت تطلب مفتاح وبتظهر "API KEY REQUIRED"). للإنتاج الكثيف استخدم مزوّد بمفتاح عبر `MAP_TILE_URL`.
- **إعدادات وقت البناء (`--dart-define`):** `MAP_TILE_URL`, `MAP_TILE_ATTRIBUTION`, `GEOCODER_URL`.
  الـ Geocoder الافتراضي (Nominatim العام) **للتجربة فقط**.

TODO BEFORE PRODUCTION:
Firestore location.updatedAt should use serverTimestamp rather than relying on driver device clock.

## خصوصية موقع الكابتن وتحصين الكتابة (v21)
- الموقع بقى في `driver_locations/{driverId}` = `{ lat, lng, updatedAt, viewers[] }`.
  القراءة: الكابتن، الإدارة، أو عميل موجود في `viewers`. تطبيق الكابتن بيضيف عميل أي
  طلب قدّم عليه عرض (أو اتعيّن عليه) وبيشيله لما الطلب يخلص أو يروح لكابتن تاني.
  لازم تنشر `firestore.rules` الجديدة.
- كتابة الموقع من شاشة الكابتن بتمر على `DriverLocationPublisher` (كتابة واحدة في
  نفس الوقت وآخر موقع بس): أوفلاين مفيش طابور كتابات بيتراكم.
- المسار (OSRM) في شاشتي الكابتن والعميل: طلب واحد في نفس الوقت، وبعد الفشل/429
  تباعد 10 ← 20 ← 40 ← 80 ← 160 ث (`RouteBackoff` في `lib/utils.dart`).
- أخطاء GPS في شاشة الكابتن: إعادة محاولة بتباعد (5 ← 80 ث) لو الخدمة مقفولة أو الخطأ
  مؤقت، ورسالة مرة واحدة لو الإذن مرفوض (من غير تكرار).
- الصيدلية والطلب اليدوي: إحداثيات الاستلام `0,0` = غير معروفة، ومفيش علامة استلام
  ولا مسار لها (الطلبات القديمة بالنقطة الوهمية بتتعامل نفس الشكل).
