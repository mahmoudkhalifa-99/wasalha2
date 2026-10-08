// معالجة زر الرجوع في الأندرويد: كل شاشة داخلية (قائمة مطعم، محفظة، ...)
// بتسجّل نفسها هنا، وأحدث واحدة هي اللي بتتقفل أول.
class BackInterceptor {
  BackInterceptor._();
  static final List<bool Function()> _handlers = [];

  static void register(bool Function() h) => _handlers.add(h);
  static void unregister(bool Function() h) => _handlers.remove(h);

  /// بيرجع true لو فيه شاشة اتقفلت بسبب الرجوع.
  static bool handle() {
    for (final h in _handlers.reversed.toList()) {
      if (h()) return true;
    }
    return false;
  }
}
