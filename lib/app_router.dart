import 'package:flutter/widgets.dart';

/// بديل بسيط لـ HashRouter في نسخة الويب.
/// المسارات: '/', '/admin/users', '/admin/edit-user/:userId',
/// '/admin/restaurants', '/admin/ads', '/admin/geography'
class AppRouter extends InheritedWidget {
  final String location;
  final void Function(String path) go;
  final VoidCallback back;

  const AppRouter({
    super.key,
    required this.location,
    required this.go,
    required this.back,
    required super.child,
  });

  static AppRouter of(BuildContext context) {
    final r = context.dependOnInheritedWidgetOfExactType<AppRouter>();
    assert(r != null, 'AppRouter not found in widget tree');
    return r!;
  }

  @override
  bool updateShouldNotify(AppRouter old) => location != old.location;
}
