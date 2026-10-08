import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

/// بيوصّل تغيّرات مركز الخريطة للـ picker بأمان:
///
/// - **ما بينادّيش `onCenter` أبدًا بشكل متزامن** من جوه `onPositionChanged`
///   (اللي ممكن يتنادى أثناء build/layout/frame). التنفيذ دايمًا post-frame.
/// - **آخر قيمة بتكسب**: أي عدد من التحديثات قبل الـ frame = استدعاء واحد.
/// - **من غير تكرار**: نفس آخر مركز اتبعت ما بيتبعتش تاني.
/// - بعد [dispose] أي callback مؤجّل بيتجاهل (frame callbacks مفيهاش إلغاء
///   فعلي في Flutter، فالحارس هو اللي بيلغي أثرها).
///
/// الـ debounce الخاص بالـ geocoding (500ms) في `LocationPickerController`
/// ومتغيّرش.
class CenterUpdateScheduler {
  CenterUpdateScheduler({
    required this.onCenter,
    required this.isActive,
    void Function(void Function() callback)? scheduleFrame,
  }) : _scheduleFrame = scheduleFrame ?? _postFrame;

  final void Function(LatLng center) onCenter;

  /// false = وضع الاختيار مش شغال، فمفيش إرسال.
  final bool Function() isActive;
  final void Function(void Function() callback) _scheduleFrame;

  LatLng? _queued;
  LatLng? _lastSent;
  bool _scheduled = false;
  bool _disposed = false;

  static void _postFrame(void Function() cb) {
    final b = SchedulerBinding.instance;
    b.addPostFrameCallback((_) => cb());
    // addPostFrameCallback لوحده مبيطلبش frame؛ ده بيضمن إنه يتنفّذ.
    b.ensureVisualUpdate();
  }

  /// مركز جديد (بيتنادى من onPositionChanged).
  void update(LatLng center) {
    if (_disposed) return;
    // نفس آخر مركز اتبعت ومفيش حاجة مستنية = تكرار.
    if (_queued == null && center == _lastSent) return;
    _queued = center;
    if (_scheduled) return;
    _scheduled = true;
    _scheduleFrame(_flush);
  }

  void _flush() {
    _scheduled = false;
    if (_disposed) return;
    final c = _queued;
    _queued = null;
    if (c == null || c == _lastSent) return;
    if (!isActive()) return;
    _lastSent = c;
    onCenter(c);
  }

  /// عند تغيير وضع الاختيار (دخول/خروج): نمسح الحالة عشان أول مركز بعد
  /// الدخول يتبعت حتى لو هو نفسه آخر مركز قديم (الـ picker بيتعمله reset).
  void reset() {
    _queued = null;
    _lastSent = null;
  }

  void dispose() {
    _disposed = true;
    _queued = null;
  }
}
