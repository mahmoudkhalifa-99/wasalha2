import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/app_shell.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // أي خطأ بيظهر نصه بدل الشاشة البيضا
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText('UI error:\n${details.exceptionAsString()}',
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
            ),
          ),
        ),
      );
  FlutterError.onError = (d) => FlutterError.presentError(d);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  ));

  // الـ UI بيبدأ فوراً، والتهيئة بتتم جواه (مع timeout وعرض الخطأ)
  runZonedGuarded(
    () => runApp(const _Bootstrap()),
    (e, st) => debugPrint('Uncaught: $e\n$st'),
  );
}

Future<void> _initServices() async {
  try {
    await initFirebase().timeout(const Duration(seconds: 20));
  } on FirebaseException catch (e) {
    // التهيئة اتعملت قبل كده (native) — عادي نكمل
    if (e.code != 'duplicate-app') rethrow;
  }
  // الويب: الـ handler بيتسجل في service worker مش من هنا (أندرويد زي ما هو)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  try {
    await NotificationService.init().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('NotificationService.init failed: $e');
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<void> _future = _initServices();

  void _retry() => setState(() => _future = _initServices());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const WasalhaApp();
        }
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.white,
            child: Center(
              child: snap.hasError
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('تعذّر تشغيل التطبيق',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          SelectableText('${snap.error}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.red)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                              onPressed: _retry,
                              child: const Text('إعادة المحاولة')),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

class WasalhaApp extends StatelessWidget {
  const WasalhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'وصلها',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.bgLight,
        colorScheme: ColorScheme.fromSeed(seedColor: C.brandPrimary),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        textTheme: GoogleFonts.cairoTextTheme(),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: C.emerald600,
          selectionColor: C.emerald500.withOpacity(0.35),
          selectionHandleColor: C.emerald600,
        ),
      ),
      home: const AppShell(),
    );
  }
}
