import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/tracking/models/tracking_models.dart' show GeoFix;
import '../features/tracking/services/driver_location_source.dart';
import '../features/verification/ui/verification_banner.dart';
import '../models/models.dart';
import '../pricing.dart';
import '../services/back_interceptor.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/order_service.dart' as order_service;
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../utils.dart' as utils;
import '../widgets/captains_offers_map.dart' show orderPickupPoint, orderDropoffPoint;
import '../widgets/common.dart';
import '../widgets/fare_breakdown.dart';
import '../widgets/leaflet_map.dart';
import '../widgets/order_details_panel.dart';
import 'activity_view.dart';
import 'chat_view.dart';
import 'profile_view.dart';

enum _CourierView { home, map, activity, profile }

/// نسخة Flutter من pages/CourierDashboard.tsx — نفس المنطق والتصميم بالظبط.
class CourierDashboard extends StatefulWidget {
  final AppUser user;
  const CourierDashboard({super.key, required this.user});

  @override
  State<CourierDashboard> createState() => _CourierDashboardState();
}

class _CourierDashboardState extends State<CourierDashboard> {
  _CourierView _activeView = _CourierView.home;
  Order? _activeOrder;
  List<Order> _availableOrders = [];
  bool _isOnline = true;
  bool _isSubmitting = false;
  String? _showOfferInputFor;
  final _offerPriceCtrl = TextEditingController();
  bool _showChat = false;

  ll.LatLng _currentLocation = const ll.LatLng(30.556, 31.008);
  ll.LatLng? _customerLocation;
  List<ll.LatLng> _routeGeometry = [];

  StreamSubscription<Position>? _posSub;
  StreamSubscription? _subCustomer, _subAvailable, _subActive, _subMyOffers;

  // بث الموقع: كتابة واحدة في نفس الوقت وآخر موقع بس (مفيش طابور أوفلاين بيتراكم).
  late final DriverLocationPublisher _publisher =
      DriverLocationPublisher(widget.user.id);

  // إعادة محاولة GPS بتباعد تصاعدي (5 ث ← 10 ← 20 ← 40 ← 80 حد أقصى).
  Timer? _gpsRetryTimer;
  int _gpsFailures = 0;
  bool _gpsStarting = false;
  String? _lastGpsIssue;

  // المسار: طلب واحد في نفس الوقت + تباعد تصاعدي بعد الفشل/429.
  final utils.RouteBackoff _routeBackoff = utils.RouteBackoff();
  bool _routeInFlight = false;
  Timer? _routeRetryTimer;

  // مين يقدر يشوف موقعي: عملاء الطلبات اللي قدّمت عليها عرض + عميل مشواري النشط.
  Set<String> _myOfferOrderIds = {};
  Set<String>? _publishedViewers; // null = لسه ما كتبناش (بنكتب أول مرة عشان نمسح القديم)
  // ما نكتبش قائمة المشاهدين قبل ما العروض والطلبات يحمّلوا (وإلا هنمسحها غلط).
  bool _offersLoaded = false, _pendingLoaded = false, _activeLoaded = false;
  bool _viewersSyncing = false;
  bool _viewersDirty = false;
  Timer? _viewersRetryTimer;

  AppUser get user => widget.user;

  @override
  void initState() {
    super.initState();
    BackInterceptor.register(_onBack);
    _setOnlineFlag(_isOnline);
    _scrubLegacyLocation();
    _startLocationWatch();
    _listenMyOffers();
    _listenOrders();
    // أول ما الكابتن يدخل حسابه: لو التوثيق ناقص تتفتح شاشة التوثيق علطول.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) promptVerificationIfNeeded(context, widget.user);
    });
  }

  bool _onBack() {
    if (_showChat) {
      setState(() => _showChat = false);
      return true;
    }
    if (_activeView != _CourierView.home) {
      setState(() => _activeView = _CourierView.home);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    BackInterceptor.unregister(_onBack);
    _posSub?.cancel();
    _gpsRetryTimer?.cancel();
    _routeRetryTimer?.cancel();
    _viewersRetryTimer?.cancel();
    _publisher.close();
    _subCustomer?.cancel();
    _subAvailable?.cancel();
    _subActive?.cancel();
    _subMyOffers?.cancel();
    _offerPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLocationWatch() async {
    if (!_isOnline || _gpsStarting || !mounted) return;
    _gpsStarting = true;
    _gpsRetryTimer?.cancel();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _reportGpsIssue('خدمة الموقع (GPS) مقفولة. شغّلها عشان العملاء يشوفوك.');
        _scheduleGpsRetry(); // ممكن يشغّلها وهو فاتح التطبيق
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // محتاج المستخدم يغيّرها بإيده: مفيش تكرار تلقائي.
        _reportGpsIssue('إذن الموقع مرفوض. فعّله من إعدادات التطبيق.');
        return;
      }
      await _posSub?.cancel();
      if (!mounted || !_isOnline) return;
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_onPosition, onError: _onGpsError, cancelOnError: true);
    } catch (err) {
      debugPrint('location watch failed: $err');
      _scheduleGpsRetry();
    } finally {
      _gpsStarting = false;
    }
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    _gpsFailures = 0;
    _lastGpsIssue = null;
    final newLoc = ll.LatLng(pos.latitude, pos.longitude);
    setState(() => _currentLocation = newLoc);
    // الـ publisher بيحدّ المعدل وبيكتب موقع واحد في المرة (حتى أوفلاين).
    _publisher.publish(
        GeoFix(position: newLoc, updatedAt: DateTime.now(), accuracy: pos.accuracy));
    _recalcRoute();
  }

  void _onGpsError(Object err) {
    debugPrint('location error: $err');
    _posSub = null; // cancelOnError: الاشتراك اتقفل
    if (!mounted || !_isOnline) return;
    if (err is PermissionDeniedException) {
      _reportGpsIssue('إذن الموقع مرفوض. فعّله من إعدادات التطبيق.');
      return;
    }
    if (err is LocationServiceDisabledException) {
      _reportGpsIssue('خدمة الموقع (GPS) مقفولة. شغّلها عشان العملاء يشوفوك.');
    }
    _scheduleGpsRetry();
  }

  void _scheduleGpsRetry() {
    if (!mounted || !_isOnline) return;
    _gpsFailures++;
    final exp = _gpsFailures - 1 > 4 ? 4 : _gpsFailures - 1;
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer =
        Timer(Duration(seconds: 5 * (1 << exp)), _startLocationWatch);
  }

  /// بيظهر كل رسالة مرة واحدة بس (لحد ما الـ GPS يشتغل تاني) عشان مانزعجش الكابتن.
  void _reportGpsIssue(String msg) {
    if (!mounted || _lastGpsIssue == msg) return;
    _lastGpsIssue = msg;
    showAppAlert(context, msg);
  }

  void _stopLocationWatch() {
    _posSub?.cancel();
    _posSub = null;
    _gpsRetryTimer?.cancel();
    _gpsFailures = 0;
    _lastGpsIssue = null;
  }

  /// نسخ قديمة كانت بتكتب الموقع في users/{id}.location (مقروء لأي مستخدم).
  /// بنمسحه مرة عند الفتح؛ الموقع دلوقتي في driver_locations بقواعد قراءة مقيّدة.
  void _scrubLegacyLocation() {
    db
        .collection('users')
        .doc(user.id)
        .update({'location': FieldValue.delete()}).catchError((_) {});
  }

  // ── مين يشوف موقعي ──

  void _listenMyOffers() {
    _subMyOffers?.cancel();
    _subMyOffers = db
        .collection('offers')
        .where('driverId', isEqualTo: user.id)
        .snapshots()
        .listen((snap) {
      _offersLoaded = true;
      _myOfferOrderIds = {
        for (final d in snap.docs)
          if ((d.data()['orderId'] as String?)?.isNotEmpty ?? false)
            d.data()['orderId'] as String,
      };
      _syncViewers();
    }, onError: (e) =>
            handleFirestoreError(e, OperationType.list, 'offers (mine)'));
  }

  Set<String> _desiredViewers() {
    final s = <String>{};
    for (final o in _availableOrders) {
      if (_myOfferOrderIds.contains(o.id) && o.customerId.isNotEmpty) {
        s.add(o.customerId);
      }
    }
    final a = _activeOrder;
    if (a != null && a.customerId.isNotEmpty) s.add(a.customerId);
    return s;
  }

  /// بيخلّي قائمة `viewers` في driver_locations مطابقة للمطلوب (وبيشيل العملاء
  /// اللي طلبهم خلص/اتاخد من كابتن تاني). مزامنة واحدة في نفس الوقت.
  Future<void> _syncViewers() async {
    if (!mounted) return;
    if (!(_offersLoaded && _pendingLoaded && _activeLoaded)) return;
    if (_viewersSyncing) {
      _viewersDirty = true;
      return;
    }
    _viewersSyncing = true;
    try {
      do {
        _viewersDirty = false;
        final want = _desiredViewers();
        final done = _publishedViewers;
        if (done != null && setEquals(done, want)) continue;
        final ok = await _publisher.setViewers(want);
        if (ok) {
          _publishedViewers = want;
        } else if (mounted) {
          _viewersRetryTimer?.cancel();
          _viewersRetryTimer = Timer(const Duration(seconds: 15), _syncViewers);
        }
      } while (_viewersDirty && mounted);
    } finally {
      _viewersSyncing = false;
    }
  }

  void _setOnlineFlag(bool v) {
    db.collection('users').doc(user.id).update({'isOnline': v}).catchError((_) {});
  }

  void _toggleOnline() {
    setState(() => _isOnline = !_isOnline);
    _setOnlineFlag(_isOnline);
    _listenOrders();
    if (_isOnline) {
      _startLocationWatch();
    } else {
      _stopLocationWatch();
    }
  }

  DateTime? _lastRouteAt;
  String? _lastRouteDest;

  /// موقع حقيقي مرة واحدة (آخر معروف ثم الحالي) — عشان الخريطة والمسار
  /// ميبدأوش من المركز الافتراضي، وعشان تشتغل حتى والكابتن أوفلاين.
  Future<void> _refreshPosition({bool route = true}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() =>
            _currentLocation = ll.LatLng(last.latitude, last.longitude));
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() =>
          _currentLocation = ll.LatLng(pos.latitude, pos.longitude));
    } catch (e) {
      debugPrint('refresh position failed: $e');
    }
    if (route && mounted) _recalcRoute(force: true);
  }

  /// وجهة المسار الحالية، أو null لو مفيش وجهة معروفة. في مرحلة الاستلام
  /// بنستخدم نقطة الاستلام *الحقيقية* بس: الصيدلية والطلب اليدوي مالهمش مكان
  /// معروف، فمفيش مسار ولا علامة (بدل ما نوجّه الكابتن لنقطة وهمية).
  ll.LatLng? _routeDestination(Order order) => order.status == OrderStatus.assigned
      ? orderPickupPoint(order)
      : orderDropoffPoint(order);

  Future<void> _recalcRoute({bool force = false}) async {
    final order = _activeOrder;
    final dest = order == null ? null : _routeDestination(order);
    if (order == null || dest == null) {
      _lastRouteDest = null;
      _routeRetryTimer?.cancel();
      _routeBackoff.reset();
      if (mounted && _routeGeometry.isNotEmpty) setState(() => _routeGeometry = []);
      return;
    }
    final destKey = '${order.id}|${order.status.value}';
    final destChanged = destKey != _lastRouteDest;
    if (destChanged) {
      // وجهة جديدة: نبدأ من الأول (التباعد القديم كان لوجهة تانية).
      _routeBackoff.reset();
      _routeRetryTimer?.cancel();
    }
    if (_routeInFlight) return; // طلب واحد في نفس الوقت
    if (_routeBackoff.blocked) return; // بعد فشل/429: الـ Timer هيعيد المحاولة
    final now = DateTime.now();
    // ما نطلبش المسار من الخادم مع كل تحديث GPS: كل 15 ثانية أو لما الوجهة تتغير.
    if (!force &&
        !destChanged &&
        _lastRouteAt != null &&
        now.difference(_lastRouteAt!) < const Duration(seconds: 15)) {
      return;
    }
    _lastRouteDest = destKey;
    _lastRouteAt = now;
    _routeInFlight = true;
    final info = utils.RouteFetchInfo();
    var stale = false;
    try {
      final geo = await utils.getRouteGeometry(_currentLocation.latitude,
          _currentLocation.longitude, dest.latitude, dest.longitude,
          info: info);
      if (!mounted) return;
      final cur = _activeOrder;
      if (cur == null || '${cur.id}|${cur.status.value}' != destKey) {
        stale = true; // الطلب/المرحلة اتغيّرت أثناء الانتظار: الرد ده قديم
      } else if (utils.isStraightFallback(geo)) {
        // السيرفرات فشلت: منستبدلش طريق حقيقي قديم بخط مستقيم، وبنعيد المحاولة
        // بتباعد تصاعدي (مش مع كل تحديث GPS).
        _onRouteFailure(rateLimited: info.rateLimited);
        if (_routeGeometry.length <= 2) {
          setState(() => _routeGeometry = geo.isNotEmpty
              ? geo.map((p) => ll.LatLng(p[0], p[1])).toList()
              : [_currentLocation, dest]);
        }
      } else {
        _routeBackoff.succeed();
        _routeRetryTimer?.cancel();
        setState(() =>
            _routeGeometry = geo.map((p) => ll.LatLng(p[0], p[1])).toList());
      }
    } catch (_) {
      if (mounted) {
        _onRouteFailure();
        if (_routeGeometry.length <= 2) {
          setState(() => _routeGeometry = [_currentLocation, dest]);
        }
      }
    } finally {
      _routeInFlight = false;
    }
    if (stale && mounted) _recalcRoute(force: true);
  }

  void _onRouteFailure({bool rateLimited = false}) {
    final wait = _routeBackoff.fail(rateLimited: rateLimited);
    _routeRetryTimer?.cancel();
    // Timer عشان المحاولة تتكرر حتى لو الكابتن واقف (مفيش تحديث GPS جديد).
    _routeRetryTimer = Timer(wait, () {
      if (mounted) _recalcRoute(force: true);
    });
  }

  void _listenOrders() {
    _subAvailable?.cancel();
    if (!_isOnline || user.status != UserStatus.approved) {
      // أوفلاين: بنوقف الطلبات الجديدة بس، والمشوار النشط يفضل متابَع.
      if (mounted) setState(() => _availableOrders = []);
      _pendingLoaded = true;
      _syncViewers();
      return;
    }
    _subActive?.cancel();

    var firstPending = true;
    _subAvailable = db
        .collection('orders')
        .where('status', isEqualTo: OrderStatus.pending.value)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (firstPending) {
        firstPending = false;
      } else {
        for (final ch in snap.docChanges) {
          if (ch.type != DocumentChangeType.added) continue;
          final m = ch.doc.data();
          if (m == null) continue;
          final o = Order.fromMap(stripFirestore(m) as Map<String, dynamic>, ch.doc.id);
          NotificationService.show(
            key: 'order_${o.id}',
            title: 'طلب جديد 🛵',
            body:
                '${o.restaurantName ?? o.pickup.villageName ?? "مشوار"} ← ${o.dropoff.villageName ?? ""} • ${o.price.toInt()} ج.م',
          );
        }
      }
      setState(() {
        _availableOrders = snap.docs
            .map((d) => Order.fromMap(
                stripFirestore(d.data()) as Map<String, dynamic>, d.id))
            .toList();
      });
      _pendingLoaded = true;
      _syncViewers(); // العروض على طلبات اتاخدت/اتلغت: نشيل عملاءها
    }, onError: (e) =>
        handleFirestoreError(e, OperationType.list, 'orders (pending)'));

    _subActive = db
        .collection('orders')
        .where('driverId', isEqualTo: user.id)
        .snapshots()
        .listen((snap) {
      final all = snap.docs
          .map((d) => Order.fromMap(
              stripFirestore(d.data()) as Map<String, dynamic>, d.id))
          .toList();
      Order? active;
      for (final o in all) {
        if (o.status != OrderStatus.delivered &&
            o.status != OrderStatus.cancelled) {
          active = o;
          break;
        }
      }
      final changed = active?.id != _activeOrder?.id ||
          active?.status != _activeOrder?.status;
      if (!mounted) return;
      setState(() => _activeOrder = active);
      _activeLoaded = true;
      _syncViewers();
      if (changed) {
        _listenCustomerLocation();
        // بنجيب الموقع الحقيقي الأول، وبعدها المسار منه.
        _refreshPosition();
      }
    }, onError: (e) =>
        handleFirestoreError(e, OperationType.list, 'orders (active_driver)'));
  }

  void _listenCustomerLocation() {
    _subCustomer?.cancel();
    final order = _activeOrder;
    if (order == null) {
      setState(() => _customerLocation = null);
      return;
    }
    _subCustomer = db
        .collection('users')
        .doc(order.customerId)
        .snapshots()
        .listen((docSnap) {
      if (!mounted || !docSnap.exists) return;
      final loc = docSnap.data()?['location'];
      if (loc is Map) {
        setState(() => _customerLocation = ll.LatLng(
            (loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()));
      }
    }, onError: (e) => handleFirestoreError(
        e, OperationType.get, 'users/${order.customerId}'));
  }

  Future<void> _handleSendOffer(String orderId) async {
    final typed = double.tryParse(_offerPriceCtrl.text);
    if (typed == null || _isSubmitting) return;
    // الحد الأدنى 25 ج.م: أي عرض أقل بيترفع تلقائياً لـ 25
    final price = finalFare(typed);
    setState(() => _isSubmitting = true);
    try {
      // رسالة ودّية لو الحساب مش مسموح له يستقبل طلبات (الحجب الفعلي في قواعد Firestore).
      final blocked = await verificationBlockMessage(user.id);
      if (blocked != null) {
        if (mounted) showAppAlert(context, blocked);
        return;
      }
      final userSnap = await db.collection('users').doc(user.id).get();
      final userData = userSnap.data();
      final rating = (userData?['rating'] as num?)?.toDouble() ?? 5.0;
      final photo = userData?['photoURL'] as String?;

      final offerRef = await db.collection('offers').add({
        'orderId': orderId,
        'driverId': user.id,
        'driverName': user.name,
        'driverPhone': user.phone,
        'driverRating': rating,
        'driverPhoto': photo,
        'vehicleType': (user.vehicleType ?? VehicleType.toktok).value,
        'price': price,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      final target = _availableOrders.where((o) => o.id == orderId).toList();
      if (target.isNotEmpty) {
        await NotificationService.notifyUser(
          userId: target.first.customerId,
          title: 'وصلك عرض سعر جديد 💰',
          body: 'الكابتن ${user.name} عرض ${price.toInt()} ج.م على طلبك',
          type: 'SUCCESS',
          key: 'offer_${offerRef.id}',
          orderId: orderId,
        );
      }
      setState(() {
        _showOfferInputFor = null;
        _offerPriceCtrl.clear();
      });
      if (mounted) showAppAlert(context, 'تم إرسال عرضك للعميل بنجاح');
    } catch (e) {
      if (mounted) showAppAlert(context, 'خطأ في إرسال العرض');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _updateOrderStatus(OrderStatus status) async {
    final order = _activeOrder;
    if (order == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await order_service.updateOrderStatus(order.id, status, user.id, user.role);
      if (status == OrderStatus.picked) {
        await NotificationService.notifyUser(
          userId: order.customerId,
          title: 'الكابتن استلم طلبك 🛵',
          body: 'أول ما يوصلك اضغط "تم الاستلام بالفعل" في التطبيق.',
          type: 'INFO',
          key: 'picked_${order.id}',
          orderId: order.id,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppAlert(context, 'فشل تحديث الحالة: ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleRejectOrder() async {
    final order = _activeOrder;
    if (order == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تأكيد الاعتذار', style: T.s(16, T.w900, C.slate900)),
          content: Text(
              'هل تريد الاعتذار عن هذا المشوار؟ سيعود الطلب متاحاً للكباتن الآخرين.',
              style: T.s(13, T.w600, C.slate600)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('تراجع', style: T.s(13, T.w700, C.slate500))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('نعم، اعتذار', style: T.s(13, T.w900, C.rose600))),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await order_service.releaseOrderFromCourier(order.id, user.id);
      await NotificationService.notifyUser(
        userId: order.customerId,
        title: 'الكابتن اعتذر عن مشوارك',
        body: 'تم إرجاع طلبك لقائمة العروض — اختار كابتن تاني.',
        type: 'ALERT',
        key: 'released_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
        orderId: order.id,
      );
      if (mounted) showAppAlert(context, 'تم الاعتذار عن المشوار بنجاح');
    } catch (e) {
      if (mounted) showAppAlert(context, 'فشل الاعتذار: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showChat && _activeOrder != null) {
      return ChatView(
        user: user,
        order: _activeOrder!,
        onBack: () => setState(() => _showChat = false),
      );
    }
    if (_activeView == _CourierView.activity) {
      return ActivityView(
          user: user, onBack: () => setState(() => _activeView = _CourierView.home));
    }
    if (_activeView == _CourierView.profile) {
      return ProfileView(
        user: user,
        onUpdate: (_) {},
        onBack: () => setState(() => _activeView = _CourierView.home),
      );
    }

    // fit: expand ضروري: من غيره الـ Stack بيتقلص لحجم أكبر ابن غير موضّع، ولما
    // تاب الخريطة يتفتح الابن ده بيبقى Offstage (حجمه صفر) فالخريطة بتتحط في
    // مساحة 0 والشاشة بتبقى فاضية.
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: C.slate50,
          child: Offstage(
            offstage: _activeView == _CourierView.map,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 672),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        VerificationBanner(user: user),
                        _onlineStatusCard(),
                        const SizedBox(height: 32),
                        if (_activeOrder != null)
                          _activeOrderCard(_activeOrder!)
                        else
                          _availableOrdersList(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_activeView == _CourierView.map) _mapView(context),
        _bottomNav(),
      ],
    );
  }

  Widget _onlineStatusCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: _isOnline
            ? const LinearGradient(colors: [C.emerald700, C.emerald600])
            : null,
        color: _isOnline ? null : C.slate950,
        borderRadius: BorderRadius.circular(48),
        boxShadow: Sh.xxl(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PressScale(
            scale: 0.9,
            onTap: _toggleOnline,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isOnline ? C.white : C.emerald500,
                borderRadius: BorderRadius.circular(32),
                boxShadow: Sh.xxl(),
              ),
              child: Icon(LucideIcons.power,
                  size: 36, color: _isOnline ? C.emerald600 : C.white),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_isOnline ? 'نشط ومستعد' : 'متوقف',
                      style: T.s(30, T.w900, C.white, letterSpacing: -0.6)),
                  const SizedBox(width: 8),
                  _isOnline
                      ? Pulse(
                          child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF6EE7B7),
                                  shape: BoxShape.circle)))
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                              color: C.slate500, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: C.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: C.white.withOpacity(0.2)),
                    ),
                    child: Text(
                        user.vehicleType == VehicleType.toktok
                            ? '🛺 كابتن توكتوك'
                            : user.vehicleType == VehicleType.car
                                ? '🚗 كابتن سيارة'
                                : '🏍️ كابتن دليفري',
                        style: T.s(11, T.w900, C.white)),
                  ),
                  const SizedBox(width: 8),
                  Text('وصلها المنوفية',
                      style: T.s(10, T.w700, C.white.withOpacity(0.75))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _availableOrdersList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
              'مشاوير بانتظارك في المنوفية (${_availableOrders.length})',
              textAlign: TextAlign.right,
              style: T.s(11, T.w900, C.slate400, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 24),
        for (final o in _availableOrders) _availableOrderCard(o),
        if (_availableOrders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 96),
            decoration: BoxDecoration(
              color: C.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(64),
              border: Border.all(
                  color: C.slate100, width: 4, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.bot, size: 64, color: C.slate200),
                const SizedBox(height: 24),
                Text('بانتظار طلبات جديدة من مراكز المنوفية...',
                    style: T.s(11, T.w900, C.slate300, letterSpacing: 1.4)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _availableOrderCard(Order o) {
    final isOfferOpen = _showOfferInputFor == o.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(56),
        border: Border.all(color: C.slate50, width: 2),
        boxShadow: Sh.xl(),
      ),
      child: isOfferOpen
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تقديم عرض سعر للمشوار',
                    textAlign: TextAlign.center,
                    style: T.s(20, T.w900, C.slate900)),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: C.slate50,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 4,
                          spreadRadius: -1,
                          offset: Offset(0, 2))
                    ],
                  ),
                  child: TextField(
                    controller: _offerPriceCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: T.s(48, T.w900, C.slate900),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: o.price.toStringAsFixed(0),
                      hintStyle: T.s(48, T.w900, C.gray400),
                      contentPadding: const EdgeInsets.all(32),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // قيمة الرحلة ← العمولة ← صافي المستحق (بنفس قاعدة الحد الأدنى 25)
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _offerPriceCtrl,
                  builder: (_, v, __) => FareBreakdownView(
                      fare: finalFare(double.tryParse(v.text) ?? o.price)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showOfferInputFor = null),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text('إلغاء',
                              textAlign: TextAlign.center,
                              style: T.s(14, T.w900, C.slate400)),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: PressScale(
                        onTap: () => _handleSendOffer(o.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.emerald600,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow:
                                Sh.xl(color: C.emerald900.withOpacity(0.2)),
                          ),
                          child: _isSubmitting
                              ? const Spinner()
                              : Text('إرسال العرض',
                                  style: T.s(14, T.w900, C.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: C.slate950,
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: Sh.xxl(),
                      ),
                      child: Text('${finalFare(o.price).toInt()}',
                          style: T.s(30, T.w900, C.emerald400)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${o.restaurantName ?? o.pickup.villageName ?? ""} ← ${o.dropoff.villageName ?? ""}',
                              textAlign: TextAlign.right,
                              style: T.s(20, T.w900, C.slate950, height: 1.2)),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: C.emerald50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(o.requestedVehicleType.value,
                                    style: T.s(10, T.w900, C.emerald600)),
                              ),
                              if (o.category == OrderCategory.food)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: C.amber50,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('طلب مطعم 🍔',
                                      style: T.s(10, T.w900, C.amber500)),
                                ),
                            ],
                          ),

                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // تفاصيل الطلب كاملة (بما فيها صورة الروشتة) قبل تقديم العرض
                OrderDetailsPanel(order: o),
                const SizedBox(height: 24),
                PressScale(
                  onTap: () => setState(() {
                    _showOfferInputFor = o.id;
                    _offerPriceCtrl.text = finalFare(o.price).toStringAsFixed(0);
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.slate950,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: Sh.xxl(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.zap,
                            size: 24, color: Color(0xFF34D399)),
                        const SizedBox(width: 16),
                        Text('تقديم عرض سريع',
                            style: T.s(20, T.w900, C.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── بطاقة الطلب النشط ──

  Widget _activeOrderCard(Order order) {
    final isAssigned = order.status == OrderStatus.assigned;
    final isPicked =
        order.status == OrderStatus.picked || order.status == OrderStatus.inDelivery;
    final destLabel = isAssigned ? 'التوجه للاستلام من' : 'التوجه للتسليم في';
    final destValue =
        isAssigned ? (order.pickup.villageName ?? '') : (order.dropoff.villageName ?? '');
    final destNotes = isAssigned ? order.pickupNotes : order.dropoffNotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: C.white,
            borderRadius: BorderRadius.circular(56),
            border: Border.all(color: C.emerald100, width: 2),
            boxShadow: Sh.xxl(color: C.emerald900.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PressScale(
                    onTap: () {
                      setState(() => _activeView = _CourierView.map);
                      _refreshPosition();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: C.emerald50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(LucideIcons.navigation,
                          size: 20, color: C.emerald600),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('مشوار جاري الآن',
                          style: T.s(10, T.w900, C.emerald600,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 2),
                      Text(order.status.labelAr,
                          style: T.s(20, T.w900, C.slate950)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FareBreakdownView(fare: finalFare(tripFareOf(order))),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: C.slate50,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isAssigned ? C.rose500 : C.emerald500,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(destLabel,
                                    style: T.s(9, T.w900, C.slate400,
                                        letterSpacing: 1.2)),
                                const SizedBox(height: 2),
                                Text(destValue,
                                    textAlign: TextAlign.right,
                                    style: T.s(16, T.w900, C.slate900)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (destNotes != null && destNotes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: C.slate200)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(destNotes,
                                    textAlign: TextAlign.right,
                                    style: T.s(11, T.w700, C.slate600)),
                              ),
                              const SizedBox(width: 8),
                              const Icon(LucideIcons.mapPin,
                                  size: 14, color: C.slate400),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (order.foodItems != null && order.foodItems!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.amber50.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: C.amber200.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('محتويات الطلب:',
                          style: T.s(10, T.w900, C.amber500,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      for (final item in order.foodItems!)
                        Text('- ${item.name} (${item.quantity}x)',
                            textAlign: TextAlign.right,
                            style: T.s(11, T.w700, C.slate700)),
                    ],
                  ),
                ),
              ],
              if (order.specialRequest != null &&
                  order.specialRequest!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.blue600.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: C.blue600.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('طلب خاص من العميل:',
                          style: T.s(10, T.w900, C.blue600,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text(order.specialRequest!,
                          textAlign: TextAlign.right,
                          style: T.s(11, T.w700, C.slate700)),
                    ],
                  ),
                ),
              ],
              if (order.prescriptionImage != null &&
                  order.prescriptionImage!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('صورة الروشتة / الدواء:',
                      style: T.s(10, T.w900, C.rose500, letterSpacing: 1.2)),
                ),
                const SizedBox(height: 6),
                PrescriptionPreview(image: order.prescriptionImage!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: PressScale(
                      onTap: () async {
                        final phone = order.customerPhone;
                        await launchUrl(Uri.parse('tel:$phone'));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.slate950,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(LucideIcons.phoneCall,
                            size: 20, color: C.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PressScale(
                      onTap: () => setState(() => _showChat = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: C.slate100, width: 2),
                        ),
                        child: const Icon(LucideIcons.messageCircle,
                            size: 20, color: C.slate900),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isAssigned)
                PressScale(
                  onTap: _isSubmitting
                      ? null
                      : () => _updateOrderStatus(OrderStatus.picked),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.emerald600,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: Sh.xl(color: C.emerald600.withOpacity(0.3)),
                    ),
                    child: _isSubmitting
                        ? const Spinner()
                        : Text('تأكيد الاستلام', style: T.s(16, T.w900, C.white)),
                  ),
                )
              else if (isPicked)
                PressScale(
                  onTap: (_isSubmitting || !order.customerReceived)
                      ? null
                      : () => _updateOrderStatus(OrderStatus.delivered),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: order.customerReceived ? C.emerald600 : C.slate200,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: order.customerReceived
                          ? Sh.xl(color: C.emerald600.withOpacity(0.3))
                          : null,
                    ),
                    child: _isSubmitting
                        ? const Spinner()
                        : Text(
                            order.customerReceived
                                ? 'تأكيد التسليم النهائي'
                                : 'بانتظار تأكيد العميل للاستلام...',
                            style: T.s(16, T.w900,
                                order.customerReceived ? C.white : C.slate500)),
                  ),
                ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _isSubmitting ? null : _handleRejectOrder,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('اعتذار عن المشوار',
                      textAlign: TextAlign.center,
                      style: T.s(11, T.w700, C.rose400)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── شاشة الخريطة ──

  Widget _mapView(BuildContext context) {
    final order = _activeOrder;
    final isAssigned = order?.status == OrderStatus.assigned;
    // نقطة الاستلام الحقيقية فقط (الصيدلية/الطلب اليدوي = null فمفيش علامة غلط).
    final pickupPt = order == null ? null : orderPickupPoint(order);
    final dropPt = order == null ? null : orderDropoffPoint(order);
    // الوجهة اللي بنركّز عليها وبنرسم لها مسار.
    final dest = order == null ? null : (isAssigned ? pickupPt : dropPt);

    return Positioned.fill(
      child: Material(
        color: C.white,
        child: Stack(
          children: [
            WasalhaMap(
              center: _currentLocation,
              zoom: 15,
              markers: [
                Marker(
                  point: _currentLocation,
                  width: 48,
                  height: 48,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.emerald600,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.white, width: 3),
                      boxShadow: Sh.xl(),
                    ),
                    child: const Icon(LucideIcons.navigation,
                        size: 20, color: C.white),
                  ),
                ),
                if (isAssigned && pickupPt != null) pickupPointMarker(pickupPt),
                // مكان العميل: وجهة المشوار بعد الاستلام، ومرجع بس قبله لو مكان
                // الاستلام مجهول (بدون مسار).
                if (dropPt != null && (!isAssigned || pickupPt == null))
                  customerHomeMarker(dropPt),
              ],
              routeGeometry: _routeGeometry,
              showControls: true,
              followCenter: true,
              fitPoints: (dest ?? dropPt) == null
                  ? null
                  : [_currentLocation, (dest ?? dropPt)!],
            ),
            Positioned(
              top: 48,
              right: 24,
              left: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PressScale(
                    onTap: () => setState(() => _activeView = _CourierView.home),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: Sh.xl(),
                      ),
                      child: const Icon(LucideIcons.arrowRight,
                          size: 24, color: C.slate900),
                    ),
                  ),
                  if (order != null && (dest != null || isAssigned))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: C.slate900,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: Sh.xl(),
                      ),
                      child: Text(
                          isAssigned
                              ? (pickupPt != null
                                  ? 'الوجهة: نقطة الاستلام'
                                  : 'نقطة الاستلام غير محددة')
                              : 'الوجهة: العميل',
                          style: T.s(11, T.w900, C.white)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── الشريط السفلي ──

  Widget _bottomNav() {
    if (_activeView == _CourierView.map) return const SizedBox.shrink();
    final tabs = [
      (_CourierView.home, LucideIcons.home, 'الرئيسية'),
      (_CourierView.map, LucideIcons.map, 'الخريطة'),
      (_CourierView.activity, LucideIcons.history, 'سجلي'),
      (_CourierView.profile, LucideIcons.user, 'حسابي'),
    ];
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        decoration: BoxDecoration(
          color: C.white.withOpacity(0.95),
          border: Border(top: BorderSide(color: C.slate100)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(56)),
          boxShadow: Sh.xxl(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final t in tabs)
              GestureDetector(
                onTap: () {
                  setState(() => _activeView = t.$1);
                  if (t.$1 == _CourierView.map) _refreshPosition();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(14),
                      constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
                      decoration: BoxDecoration(
                        color: _activeView == t.$1 ? C.emerald50 : null,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(t.$2,
                          size: 24,
                          color:
                              _activeView == t.$1 ? C.emerald600 : C.slate300),
                    ),
                    const SizedBox(height: 4),
                    Text(t.$3,
                        style: T.s(
                            11,
                            T.w900,
                            _activeView == t.$1 ? C.emerald600 : C.slate300,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
