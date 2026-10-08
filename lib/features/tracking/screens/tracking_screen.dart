import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/osrm_routing_service.dart';
import '../../../core/map/routing_service.dart';
import '../../../theme/app_colors.dart';
import '../controllers/location_picker_controller.dart';
import '../controllers/tracking_controller.dart';
import '../models/selected_location.dart';
import '../models/tracking_models.dart';
import '../services/driver_location_source.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../widgets/tracking_info_card.dart';
import '../widgets/tracking_map.dart';
import '../widgets/tracking_overlays.dart';

/// الوضع الابتدائي للشاشة.
enum TrackingScreenMode {
  /// تتبع السائق + المسار + Bottom Sheet.
  tracking,

  /// اختيار موقع بـ Pin ثابت في المنتصف.
  pickLocation,
}

/// شاشة "الخريطة والتتبع": خريطة Full Screen + عناصر عايمة. مستقلة تمامًا:
/// بتاخد بياناتها من الـ constructor وبتنشئ Controller خاص بيها وتقفله في
/// dispose (GPS، Timers، Streams). **مش متوصّلة بأي شاشة حالية.**
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => TrackingScreen(
///     role: TrackingRole.customerWatchingDriver,
///     driverId: order.driverId,
///     customerLocation: LatLng(order.dropoff.lat, order.dropoff.lng),
///     onLocationSelected: (loc) => debugPrint('$loc'),
///   ),
/// ));
/// ```
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    super.key,
    required this.role,
    this.driverId,
    this.customerLocation,
    this.customerAddress,
    this.title = 'الخريطة والتتبع',
    this.initialMode = TrackingScreenMode.tracking,
    this.allowLocationPicking = true,
    this.applySelectionAsDestination = true,
    this.onLocationSelected,
    this.routingService,
    this.locationService,
    this.geocodingService,
    this.config = const TrackingConfig(),
    this.controller,
  });

  final TrackingRole role;

  /// العميل: id السائق المراد تتبعه (users/{driverId}). مطلوب في وضع العميل.
  /// السائق: id حسابه عشان يبث موقعه (اختياري؛ null = عرض بدون بث).
  final String? driverId;

  /// موقع العميل/الوجهة، وعنوانه لو معروف (للعرض فقط).
  final LatLng? customerLocation;
  final String? customerAddress;
  final String title;

  final TrackingScreenMode initialMode;

  /// يظهر زر "اختيار موقع من الخريطة" في الشريط العلوي.
  final bool allowLocationPicking;

  /// true: لما المستخدم يعتمد موقع، بيتحوّل لوجهة ويتحسب المسار ليه.
  /// false: بنبلّغ الشاشة الأم بس عن طريق [onLocationSelected].
  final bool applySelectionAsDestination;

  /// بيتنادى لما المستخدم يضغط "اختيار هذا الموقع".
  final ValueChanged<SelectedLocation>? onLocationSelected;

  /// للاستبدال (اختبارات أو مزوّد آخر).
  final RoutingService? routingService;
  final LocationService? locationService;
  final GeocodingService? geocodingService;
  final TrackingConfig config;

  /// لو اتمرر Controller جاهز، الشاشة ما بتقفلوش (صاحبه هو المسؤول).
  final TrackingController? controller;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  late final TrackingController _controller;
  late final bool _ownsController;
  late final LocationPickerController _picker;
  NominatimGeocodingService? _ownedGeocoder;

  late final ValueNotifier<bool> _picking;

  /// ارتفاع الـ Sheet كنسبة من الشاشة (عشان الأزرار تفضل فوقها).
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(_sheetInitial);

  static const double _sheetMin = 0.16;
  static const double _sheetInitial = 0.38;
  static const double _sheetMax = 0.62;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected;
      _ownsController = false;
    } else {
      _ownsController = true;
      _controller = _buildController();
    }

    GeocodingService geocoder;
    if (widget.geocodingService != null) {
      geocoder = widget.geocodingService!;
    } else {
      geocoder = _ownedGeocoder = NominatimGeocodingService();
    }
    _picker = LocationPickerController(
      geocoder: geocoder,
      origin: () => _controller.me.value,
      debounce: widget.config.pickDebounce,
    );
    _picking = ValueNotifier<bool>(
        widget.initialMode == TrackingScreenMode.pickLocation);

    _controller.start();
  }

  TrackingController _buildController() {
    final isDriver = widget.role == TrackingRole.driverSharing;
    final id = widget.driverId;
    return TrackingController(
      location: widget.locationService ?? const GeolocatorLocationService(),
      routing: widget.routingService ?? OsrmRoutingService(),
      customerLocation: widget.customerLocation,
      config: widget.config,
      driverSource: (!isDriver && id != null)
          ? FirestoreDriverLocationSource(id)
          : (!isDriver ? _EmptyDriverSource() : null),
      publisher: (isDriver && id != null) ? DriverLocationPublisher(id) : null,
    );
  }

  // لما المستخدم يرجع من إعدادات الموقع/الصلاحيات، نعيد المحاولة تلقائيًا.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _controller.locationIssue.value != null) {
      _controller.retryLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _picker.dispose();
    _ownedGeocoder?.close();
    _picking.dispose();
    _sheetExtent.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  // ---------------- اختيار الموقع ----------------
  void _enterPick() {
    _sheetExtent.value = _sheetInitial;
    _picking.value = true;
  }

  void _exitPick() {
    _sheetExtent.value = _sheetInitial; // الـ Sheet بترجع لحجمها الابتدائي
    _picking.value = false;
    _picker.reset();
  }

  void _confirmPick() {
    final sel = _picker.confirm();
    if (sel == null) return;
    widget.onLocationSelected?.call(sel);
    final backToTracking = widget.initialMode == TrackingScreenMode.tracking;
    if (widget.applySelectionAsDestination) {
      // هنا بس بيتحسب مسار للموقع الجديد. في شاشة الاختيار فقط ما بنحرّكش
      // الكاميرا عشان الـ Pin يفضل على الموقع المعتمد.
      _controller.setDestination(sel.latLng, moveCamera: backToTracking);
    }
    // لو الشاشة اتفتحت للتتبع، نرجع لوضع التتبع. لو اتفتحت للاختيار فقط،
    // الشاشة الأم هي اللي بتقفلها.
    if (backToTracking) _exitPick();
  }

  void _onCenterChanged(LatLng c) => _picker.onCenterChanged(c);

  // ---------------- البناء ----------------
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: C.bgLight,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // خريطة واحدة طول الوقت (مفيش إعادة إنشاء عند تغيير الوضع).
            Positioned.fill(
              child: TrackingMap(
                controller: _controller,
                pickMode: _picking,
                onCenterChanged: _onCenterChanged,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _picking,
              builder: (context, picking, _) =>
                  picking ? const CenterPin() : const SizedBox.shrink(),
            ),
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _picking,
                    builder: (context, picking, _) => _topBar(picking),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _picking,
                builder: (context, picking, _) =>
                    picking ? _pickBottom() : _trackingBottom(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(bool picking) {
    if (picking) {
      return TrackingTopBar(
        title: 'اختر موقع الوجهة',
        leading: widget.initialMode == TrackingScreenMode.tracking
            ? MapRoundButton(
                icon: Icons.close_rounded,
                tooltip: 'إلغاء الاختيار',
                size: 40,
                onTap: _exitPick,
              )
            : _backButton(),
      );
    }
    return TrackingTopBar(
      title: widget.title,
      leading: _backButton(),
      status: AnimatedBuilder(
        animation: Listenable.merge([_controller.freshness, _controller.driver]),
        builder: (context, _) => Row(
          children: [
            FreshnessChip(freshness: _controller.freshness.value),
            const SizedBox(width: 8),
            Flexible(
              child: LastUpdateText(
                fix: _controller.driver.value,
                freshness: _controller.freshness.value,
              ),
            ),
          ],
        ),
      ),
      trailing: widget.allowLocationPicking
          ? MapRoundButton(
              icon: Icons.add_location_alt_rounded,
              tooltip: 'اختيار موقع من الخريطة',
              size: 40,
              onTap: _enterPick,
            )
          : null,
    );
  }

  Widget _backButton() => MapRoundButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'رجوع',
        size: 40,
        onTap: () => Navigator.of(context).maybePop(),
      );

  /// أزرار عايمة (موقعي + عرض الكل) + الـ attribution.
  Widget _floating() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MapRoundButton(
              icon: Icons.fit_screen_rounded,
              tooltip: 'عرض الطريق كاملًا',
              onTap: _controller.fitAll,
            ),
            const SizedBox(height: 10),
            MapRoundButton(
              icon: Icons.my_location_rounded,
              tooltip: 'موقعي',
              filled: true,
              onTap: _controller.focusMyLocation,
            ),
          ],
        ),
        const Spacer(),
        const MapAttribution(),
      ],
    );
  }

  Widget _trackingBottom() {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        return Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, e, _) => PositionedDirectional(
                start: 12,
                end: 12,
                bottom: e * h + 10,
                child: _floating(),
              ),
            ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                _sheetExtent.value = n.extent;
                return false;
              },
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DraggableScrollableSheet(
                    initialChildSize: _sheetInitial,
                    minChildSize: _sheetMin,
                    maxChildSize: _sheetMax,
                    snap: true,
                    snapSizes: const [_sheetInitial],
                    builder: (context, scroll) => Container(
                      decoration: const BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x26000000),
                              blurRadius: 20,
                              offset: Offset(0, -4)),
                        ],
                      ),
                      child: SingleChildScrollView(
                        controller: scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _SheetHandle(),
                              TrackingSheetContent(
                                controller: _controller,
                                customerAddress: widget.customerAddress,
                                onFitRoute: _controller.fitAll,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pickBottom() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _floating(),
            ),
            PickLocationCard(
              picker: _picker,
              onConfirm: _confirmPick,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: C.slate300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// وضع العميل بدون driverId: مفيش سائق نتابعه لسه (الخريطة بتشتغل عادي).
class _EmptyDriverSource implements DriverLocationSource {
  @override
  Stream<GeoFix> watch() => const Stream<GeoFix>.empty();
}
