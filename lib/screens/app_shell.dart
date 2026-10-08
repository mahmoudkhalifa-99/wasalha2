import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Blob;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_router.dart';
import '../constants.dart';
import '../models/models.dart';
import '../services/account_deletion.dart';
import '../services/app_status_service.dart';
import '../services/back_interceptor.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common.dart';
import 'admin/admin_ads_manager.dart';
import 'admin/admin_edit_user.dart';
import 'admin/admin_geography_manager.dart';
import 'admin/admin_restaurant_manager.dart';
import 'admin/admin_users_list.dart';
import 'app_disabled_screen.dart';
import 'onboarding_screen.dart' show OnboardingPrefs;
import 'admin/operator_dashboard.dart';
import 'admin/super_admin_dashboard.dart';
import 'courier_dashboard.dart';
import 'customer_dashboard.dart';
import 'login_screen.dart';
import 'notifications_view.dart';
import 'support_view.dart';
import 'complete_phone_screen.dart';
import 'suspended_screen.dart';
import 'verify_email_screen.dart';

/// نسخة Flutter من pages/App.tsx
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppUser? _user;
  bool _loading = true;
  bool _connectionError = false;
  // لو القواعد رفضت إنشاء وثيقة المستخدم: نحاول مرة واحدة بس ونعرض شاشة خطأ
  // بدل ما الشاشة تفضل تترعش (الكتابة المحلية بتظهر الوثيقة ثم السيرفر يرفضها ويتكرر).
  String? _provisionAttemptedUid;
  bool _accountError = false;
  // مستخدم جوجل جديد لازم يختار (عميل / كابتن) قبل إنشاء وثيقته
  ({String uid, String email, String displayName})? _pendingProfile;
  bool _showNotifications = false;
  bool _showSupport = false;
  int _unreadCount = 0;
  bool _isLogoutModalOpen = false;
  // مفتاح تشغيل التطبيق (بيتحكم فيه السوبر أدمن). الافتراضي: شغال.
  AppStatus _appStatus = AppStatus.on;
  // السوبر أدمن بيفتح شاشة الدخول حتى والتطبيق متوقف
  bool _adminLoginRequested = false;
  StreamSubscription<AppStatus>? _statusSub;

  final List<String> _stack = ['/'];
  String get _location => _stack.last;

  StreamSubscription<fb.User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<String>? _tokenSub;
  String? _pushForUserId;
  String? _notifKey;
  String _userSig = '';

  @override
  void initState() {
    super.initState();
    _listenAuth();
    _statusSub = AppStatusService.watch().listen((st) {
      if (mounted) setState(() => _appStatus = st);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PermissionService.requestOnFirstLaunch(context);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _statusSub?.cancel();
    _userSub?.cancel();
    _notifSub?.cancel();
    _tokenSub?.cancel();
    NotificationService.stop();
    super.dispose();
  }

  void _listenAuth() {
    _authSub?.cancel();
    _authSub = auth.authStateChanges().listen((fbUser) async {
      try {
        if (fbUser != null) {
          _fetchUserData(fbUser.uid);
        } else {
          _userSub?.cancel();
          _notifSub?.cancel();
          _notifKey = null;
          _userSig = '';
          _provisionAttemptedUid = null;
          _pendingProfile = null;
          NotificationService.stop();
          if (!mounted) return;
          setState(() {
            _user = null;
            _accountError = false;
            _loading = false;
          });
        }
      } catch (error) {
        debugPrint('Auth error: $error');
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<bool> _isOnline() async {
    // Browser networking is controlled by the browser; avoid dart:io here.
    if (kIsWeb) return true;
    return true;
  }

  void _fetchUserData(String uid) {
    _userSub?.cancel();
    final userRef = db.collection('users').doc(uid);
    _userSub = userRef.snapshots().listen((docSnap) async {
      if (docSnap.exists) {
        final raw = stripFirestore(docSnap.data()) as Map<String, dynamic>;
        final data = AppUser.fromMap(raw, docSnap.id);
        if (!mounted) return;
        // مستخدم داخل بالفعل = مش محتاج شاشة التعريف لو خرج ودخل بعدين
        OnboardingPrefs.markSeen();
        _provisionAttemptedUid = null;
        _pendingProfile = null;
        if (_accountError) setState(() => _accountError = false);
        // موقع الكابتن بيتكتب كل ~10 متر: ما نعيدش بناء التطبيق كله بسببه.
        final sig = (Map<String, dynamic>.of(raw)
              ..remove('location')
              ..remove('lastTokenUpdate'))
            .toString();
        if (_user == null || sig != _userSig || _loading || _connectionError) {
          _userSig = sig;
          setState(() {
            _user = data;
            _loading = false;
            _connectionError = false;
          });
        }

        final notifKey = '${data.id}|${data.role.value}';
        if (_notifKey != notifKey) {
          _notifKey = notifKey;
        _notifSub?.cancel();
        _notifSub = db
            .collection('notifications')
            .where('userId', whereIn: [data.id, 'ALL', data.role.value])
            .snapshots()
            .listen((snap) {
          final unread =
              snap.docs.where((d) => d.data()['read'] != true).length;
          if (mounted) setState(() => _unreadCount = unread);
          NotificationService.handleSnapshot(snap, data.id);
        }, onError: (err) {
          debugPrint('Notifications listener: $err');
        });
        }

        _setupPush(data.id);
        NotificationService.startFor(data.id, data.role.value);
      } else {
        // حذف الحساب شغال: وثيقة المستخدم اتمسحت قصداً، ما نعيدش إنشاءها
        if (AccountDeletion.inProgress) return;
        final currentUser = auth.currentUser;
        if (_provisionAttemptedUid == uid) {
          // المحاولة السابقة اترفضت: نوقف التكرار ونعرض الخطأ
          if (mounted) {
            setState(() {
              _user = null;
              _accountError = true;
              _loading = false;
            });
          }
          return;
        }
        if (currentUser != null && currentUser.uid == uid) {
          final emailLower = (currentUser.email ?? '').toLowerCase();
          final isAdminEmail = adminEmails.contains(emailLower);

          if (!isAdminEmail) {
            // مستخدم جوجل جديد: ما نعملوش حساب عميل تلقائي، نسيبه يختار
            // (عميل / كابتن) ونوع المركبة من نموذج إكمال البيانات.
            final isGoogle = currentUser.providerData
                .any((p) => p.providerId == 'google.com');
            if (isGoogle) {
              if (mounted) {
                setState(() {
                  _pendingProfile = (
                    uid: uid,
                    email: currentUser.email ?? '',
                    displayName: currentUser.displayName ?? ''
                  );
                  _user = null;
                  _loading = false;
                });
              }
              return;
            }
            // تسجيل جديد بالإيميل لسه شغال: شاشة التسجيل هي اللي بتكتب
            // الوثيقة بالرتبة المختارة، فما نسبقهاش.
            final created = currentUser.metadata.creationTime;
            if (created != null &&
                DateTime.now().difference(created) <
                    const Duration(minutes: 2)) {
              if (mounted) {
                setState(() {
                  _user = null;
                  _loading = false;
                });
              }
              return;
            }
          }

          _provisionAttemptedUid = uid;

          final defaultUserData = AppUser(
            id: uid,
            email: currentUser.email ?? '',
            name: isAdminEmail
                ? 'مدير المنظومة'
                : (currentUser.displayName ?? 'مستخدم'),
            phone: '', // الرقم إجباري: بتطلبه شاشة إكمال الرقم
            role: isAdminEmail ? UserRole.admin : UserRole.customer,
            status: UserStatus.approved,
            zoneId: 'أشمون',
            wallet: const Wallet(balance: 0, totalEarnings: 0, withdrawn: 0),
          );
          try {
            await userRef.set(defaultUserData.toMap());
            if (mounted) setState(() => _user = defaultUserData);
          } catch (err) {
            debugPrint('Auto user creation error: $err');
            if (mounted) {
              setState(() {
                _user = null;
                _accountError = true;
              });
            }
          }
        } else {
          if (mounted) setState(() => _user = null);
        }
        if (mounted) setState(() => _loading = false);
      }
    }, onError: (error) async {
      if (!await _isOnline() && mounted) setState(() => _connectionError = true);
      if (mounted) setState(() => _loading = false);
    });
  }

  /// تفعيل إشعارات الأندرويد لما المستخدم يدخل التطبيق
  /// (مكافئ useEffect الخاص بـ PushNotifications في App.tsx)
  Future<void> _setupPush(String userId) async {
    if (_pushForUserId == userId) return;
    _pushForUserId = userId;
    try {
      final messaging = FirebaseMessaging.instance;

      Future<void> saveToken(String token) async {
        try {
          await db.collection('users').doc(userId).update({
            'fcmToken': token,
            'notificationsEnabled': true,
            'lastTokenUpdate': DateTime.now().millisecondsSinceEpoch,
          });
        } catch (err) {
          debugPrint('Failed to save push token: $err');
        }
      }

      _tokenSub?.cancel();
      _tokenSub = messaging.onTokenRefresh.listen(saveToken);

      // لو المستخدم سمح بالإشعارات قبل كده، نجدد التسجيل تلقائياً بصمت.
      // لو أول مرة، نطلب الإذن فوراً وقت الدخول.
      var settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await messaging.requestPermission(
            alert: true, badge: true, sound: true);
      }
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        if (token != null) await saveToken(token);
      }
    } catch (err) {
      debugPrint('Push notifications setup failed: $err');
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isLogoutModalOpen = false);
    await auth.signOut();
    _userSub?.cancel();
    _notifSub?.cancel();
    _notifKey = null;
    _userSig = '';
    _pushForUserId = null;
    if (!mounted) return;
    setState(() {
      _adminLoginRequested = false;
      _user = null;
      _loading = false;
      _unreadCount = 0;
      _showNotifications = false;
      _showSupport = false;
      _stack
        ..clear()
        ..add('/');
    });
  }

  void _reload() {
    setState(() {
      _loading = true;
      _connectionError = false;
    });
    _listenAuth();
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingScreen(context);
    if (_connectionError) return _connectionErrorScreen();
    if (_accountError) return _accountErrorScreen();
    // التطبيق متوقف من السوبر أدمن: الكل يشوف شاشة الإيقاف ما عدا الأدمن
    if (!_appStatus.enabled &&
        _user?.role != UserRole.admin &&
        !(_user == null && _adminLoginRequested)) {
      return AppDisabledScreen(
        message: _appStatus.message,
        signedIn: _user != null,
        onLogout: _handleLogout,
        onAdminLogin: () => setState(() => _adminLoginRequested = true),
      );
    }
    if (_user == null) {
      return LoginScreen(
        onLogin: (u) => setState(() => _user = u),
        completeProfileFor: _pendingProfile,
      );
    }
    // لازم يأكد البريد الأول (حسابات الإيميل/الباسورد فقط، الأدمن وجوجل مستثنين)
    if (needsEmailVerification(auth.currentUser)) {
      return VerifyEmailScreen(
        onVerified: () {
          if (mounted) setState(() {});
        },
        onLogout: _handleLogout,
      );
    }
    // حساب معطّل: مفيش استخدام لحد ما السوبر أدمن يفعّله
    if (_user!.status == UserStatus.suspended) {
      return SuspendedScreen(name: _user!.name, onLogout: _handleLogout);
    }
    // رقم الهاتف إجباري لكل الحسابات (جوجل وغيره) ما عدا المستثنين
    if (!isExemptEmail(_user!.email) && !isValidPhone(_user!.phone)) {
      return CompletePhoneScreen(
          userId: _user!.id, name: _user!.name, onLogout: _handleLogout);
    }

    final md = isMd(context);
    final headerHeight = md ? 84.0 : 68.0;
    final top = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: AppRouter(
      location: _location,
      go: (path) => setState(() {
        if (path == '/') {
          _stack
            ..clear()
            ..add('/');
        } else {
          _stack.add(path);
        }
      }),
      back: () => setState(() {
        if (_stack.length > 1) _stack.removeLast();
      }),
      child: Scaffold(
        backgroundColor: C.bgLight,
        body: Stack(
          children: [
            AppBackground(
              child: Column(
                children: [
                  _header(context, md, headerHeight, top),
                  Expanded(child: _content()),
                ],
              ),
            ),
            if (_isLogoutModalOpen) _logoutModal(),
          ],
        ),
      ),
    ));
  }

  DateTime? _lastBack;

  void _handleBack() {
    if (_isLogoutModalOpen) {
      setState(() => _isLogoutModalOpen = false);
      return;
    }
    if (_showNotifications || _showSupport) {
      setState(() {
        _showNotifications = false;
        _showSupport = false;
      });
      return;
    }
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
      return;
    }
    if (BackInterceptor.handle()) return;
    // الصفحة الرئيسية: ضغطتين رجوع للخروج
    final now = DateTime.now();
    if (_lastBack == null || now.difference(_lastBack!) > const Duration(seconds: 2)) {
      _lastBack = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Text('اضغط رجوع مرة تانية للخروج',
              textAlign: TextAlign.center,
              style: T.s(13, T.w700, C.white)),
        ));
      return;
    }
    SystemNavigator.pop();
  }

  Widget _content() {
    final loc = _location;
    final isAdmin = _user?.role == UserRole.admin;

    if (isAdmin) {
      if (loc == '/admin/users') {
        return AdminUsersList(user: _user!);
      }
      if (loc.startsWith('/admin/edit-user/')) {
        final userId = loc.substring('/admin/edit-user/'.length);
        return AdminEditUser(userId: userId);
      }
      if (loc == '/admin/restaurants') {
        return AdminRestaurantManager(user: _user!);
      }
      if (loc == '/admin/ads') {
        return AdminAdsManager(user: _user!);
      }
      if (loc == '/admin/geography') {
        return AdminGeographyManager(user: _user!);
      }
    }
    return _dashboard();
  }

  Widget _dashboard() {
    final user = _user!;
    if (_showNotifications) {
      return NotificationsView(
          user: user, onBack: () => setState(() => _showNotifications = false));
    }
    if (_showSupport) {
      return SupportView(
          user: user, onBack: () => setState(() => _showSupport = false));
    }
    switch (user.role) {
      case UserRole.admin:
        return SuperAdminDashboard(user: user);
      case UserRole.operator:
        return OperatorDashboard(user: user);
      case UserRole.driver:
        return CourierDashboard(user: user);
      case UserRole.customer:
        return CustomerDashboard(user: user);
      case UserRole.unknown:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(80),
            child: Text('الحساب معلق',
                textAlign: TextAlign.center, style: T.s(16, T.w900, C.slate900)),
          ),
        );
    }
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
    required Color bg,
    required Color borderColor,
    required Color iconColor,
    bool flip = false,
    Widget? badge,
  }) {
    return PressScale(
      scale: 0.9,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Transform.rotate(
                angle: flip ? 3.141592653589793 : 0,
                child: Icon(icon, size: 20, color: iconColor),
              ),
            ),
          ),
          if (badge != null) badge,
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool md, double height, double top) {
    final btn = md ? 44.0 : 40.0; // p-3 / p-2.5 + icon 20
    return GlassBox(
      sigma: 24,
      color: C.white.withOpacity(0.9),
      borderRadius: BorderRadius.zero,
      child: Container(
        height: height + top,
        padding: EdgeInsets.fromLTRB(md ? 32 : 16, top, md ? 32 : 16, 0),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: C.slate200.withOpacity(0.8))),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), offset: Offset(0, 4), blurRadius: 20, spreadRadius: -4),
          ],
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showNotifications = false;
                      _showSupport = false;
                      _stack
                        ..clear()
                        ..add('/');
                    });
                  },
                  child: const BrandLogo(
                      size: BrandLogoSize.sm, showSubtitle: true),
                ),

                // Middle Regional Badge (Desktop/Tablet)
                if (isSm(context))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: C.emerald50.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: C.emerald100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PingDot(size: 8, color: C.emerald500),
                        const SizedBox(width: 8),
                        Text('المنوفية • خدمة 24 ساعة مباشرة',
                            style: T.s(12, T.w900, C.emerald800)),
                      ],
                    ),
                  ),

                // Quick Action Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconButton(
                      icon: LucideIcons.messageCircle,
                      onTap: () => setState(() => _showSupport = true),
                      size: btn,
                      bg: C.slate50,
                      borderColor: C.slate200.withOpacity(0.6),
                      iconColor: C.slate500,
                    ),
                    const SizedBox(width: 8),
                    _iconButton(
                      icon: LucideIcons.bell,
                      onTap: () => setState(() => _showNotifications = true),
                      size: btn,
                      bg: C.slate50,
                      borderColor: C.slate200.withOpacity(0.6),
                      iconColor: C.slate500,
                      badge: _unreadCount > 0
                          ? Positioned(
                              top: -4,
                              right: -4,
                              child: Pulse(
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: C.rose500,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: C.white, width: 2),
                                  ),
                                  child: Text('$_unreadCount',
                                      style: T.s(9, T.w900, C.white,
                                          height: 1.0)),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _iconButton(
                      icon: LucideIcons.logOut,
                      onTap: () => setState(() => _isLogoutModalOpen = true),
                      size: btn,
                      bg: C.rose50.withOpacity(0.8),
                      borderColor: C.rose100.withOpacity(0.8),
                      iconColor: C.rose600,
                      flip: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutModal() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: GlassBox(
          sigma: 12,
          color: C.slate950.withOpacity(0.6),
          borderRadius: BorderRadius.zero,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: C.white,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: C.slate100),
                      boxShadow: Sh.xxl(),
                    ),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: C.rose50,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Center(
                            child: Transform.rotate(
                              angle: 3.141592653589793,
                              child: const Icon(LucideIcons.logOut,
                                  size: 36, color: C.rose500),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('تسجيل الخروج؟',
                            textAlign: TextAlign.center,
                            style: T.s(24, T.w900, C.slate900,
                                letterSpacing: -0.6)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'هل ترغب بالفعل في مغادرة التطبيق الآن؟ يمكنك العودة في أي وقت.',
                            textAlign: TextAlign.center,
                            style: T.s(12, T.w700, C.slate400, height: 1.625),
                          ),
                        ),
                        const SizedBox(height: 24),
                        PressScale(
                          onTap: _handleLogout,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.rose500,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: Sh.lg(
                                  color: C.rose500.withOpacity(0.2)),
                            ),
                            child: Text('تأكيد الخروج',
                                style: T.s(16, T.w900, C.white)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        PressScale(
                          onTap: () =>
                              setState(() => _isLogoutModalOpen = false),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.slate100,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('البقاء في التطبيق',
                                style: T.s(16, T.w900, C.slate600)),
                          ),
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
    );
  }

  Widget _loadingScreen(BuildContext context) {
    final md = isMd(context);
    final size = MediaQuery.of(context).size;
    Widget pill(String text, Color color) => GlassBox(
          sigma: 12,
          color: C.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: C.white.withOpacity(0.15)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(text, style: T.s(11, T.w900, color)),
        );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.slate950, C.emerald950, C.slate900],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
                top: size.height * 0.25, right: -80,
                child: Blob(size: 384, color: C.emerald500.withOpacity(0.20))),
            Positioned(
                bottom: size.height * 0.25, left: -80,
                child: Blob(size: 384, color: C.teal500.withOpacity(0.15))),
            Positioned(
                left: size.width / 2 - 275, top: size.height / 2 - 275,
                child: Ring(size: 550, color: C.emerald500.withOpacity(0.15))),
            Positioned(
                left: size.width / 2 - 375, top: size.height / 2 - 375,
                child: Ring(size: 750, color: C.emerald500.withOpacity(0.10))),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Pulse(
                      child: Container(
                        width: md ? 128 : 112,
                        height: md ? 128 : 112,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: C.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            ...Sh.xxl(color: C.emerald950.withOpacity(0.8)),
                            Sh.ring(C.white.withOpacity(0.2)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset('assets/images/icon-512.png',
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('وصـــلــهــا المنوفية',
                        textAlign: TextAlign.center,
                        style: T.s(md ? 36 : 30, T.w900, C.white,
                            letterSpacing: md ? -0.9 : -0.75)),
                    const SizedBox(height: 8),
                    Text('مشاويرك، أكلك، وطلباتك في ثواني',
                        textAlign: TextAlign.center,
                        style: T.s(12, T.w700, C.emerald300, letterSpacing: 1.8)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        pill('🛺 توكتوك', C.amber300),
                        const SizedBox(width: 8),
                        pill('🚗 سيارة', const Color(0xFFE2E8F0)),
                        const SizedBox(width: 8),
                        pill('🏍️ دليفري', C.emerald300),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GlassBox(
                      sigma: 12,
                      color: C.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: C.white.withOpacity(0.15)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Spinner(size: 16, color: C.emerald400),
                          const SizedBox(width: 12),
                          Text('جاري الاتصال بالخدمة الذكية...',
                              style: T.s(11, T.w700,
                                  C.white.withOpacity(0.9),
                                  letterSpacing: 0.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountErrorScreen() {
    return Scaffold(
      backgroundColor: C.slate50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: C.rose50,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(LucideIcons.xCircle,
                    size: 40, color: C.rose500),
              ),
              const SizedBox(height: 24),
              Text('تعذر إنشاء ملف حسابك',
                  textAlign: TextAlign.center,
                  style: T.s(22, T.w900, C.slate800)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                    'السيرفر رفض إنشاء بيانات الحساب. سجّل الخروج وحاول تاني، ولو المشكلة مستمرة كلّم الدعم.',
                    textAlign: TextAlign.center,
                    style: T.s(12, T.w700, C.slate400)),
              ),
              const SizedBox(height: 24),
              PressScale(
                onTap: _handleLogout,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: C.emerald600,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text('تسجيل الخروج',
                      style: T.s(16, T.w900, C.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionErrorScreen() {
    return Scaffold(
      backgroundColor: C.slate50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: C.rose50,
                  borderRadius: BorderRadius.circular(24),
                ),
                child:
                    const Icon(LucideIcons.wifiOff, size: 40, color: C.rose500),
              ),
              const SizedBox(height: 24),
              Text('تعذر الاتصال بالشبكة',
                  textAlign: TextAlign.center,
                  style: T.s(24, T.w900, C.slate800)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text('يرجى التأكد من اتصال هاتفك بالإنترنت ثم إعادة المحاولة',
                    textAlign: TextAlign.center,
                    style: T.s(12, T.w700, C.slate400)),
              ),
              const SizedBox(height: 24),
              PressScale(
                onTap: _reload,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: C.emerald600,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Sh.lg(color: C.emerald600.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.refreshCcw,
                          size: 16, color: C.white),
                      const SizedBox(width: 12),
                      Text('إعادة المحاولة',
                          style: T.s(16, T.w900, C.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
