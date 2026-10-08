import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/widgets/center_update_scheduler.dart';

const _a = LatLng(30.55, 31.0);
const _b = LatLng(30.56, 31.01);
const _c = LatLng(30.57, 31.02);

/// "Frame" يدوي: الـ scheduler بيحط الـ callback هنا، والاختبار هو اللي
/// بيقرر إمتى الـ frame يخلص.
class FakeFrames {
  final List<void Function()> queue = [];
  void schedule(void Function() cb) => queue.add(cb);
  void runFrame() {
    final batch = List.of(queue);
    queue.clear();
    for (final cb in batch) {
      cb();
    }
  }
}

void main() {
  late FakeFrames frames;
  late List<LatLng> sent;
  late bool active;
  late CenterUpdateScheduler s;

  setUp(() {
    frames = FakeFrames();
    sent = [];
    active = true;
    s = CenterUpdateScheduler(
      onCenter: sent.add,
      isActive: () => active,
      scheduleFrame: frames.schedule,
    );
  });

  test('مبينادّيش onCenter متزامنًا أبدًا (آمن أثناء build)', () {
    s.update(_a);
    expect(sent, isEmpty); // لسه ما فيش frame
    expect(frames.queue.length, 1);
    frames.runFrame();
    expect(sent, [_a]);
  });

  test('عدة تحديثات قبل الـ frame = استدعاء واحد بآخر قيمة (frame واحد مجدول)',
      () {
    s.update(_a);
    s.update(_b);
    s.update(_c);
    expect(frames.queue.length, 1);
    frames.runFrame();
    expect(sent, [_c]);
  });

  test('مفيش تكرار: نفس آخر مركز اتبعت ما بيتبعتش ولا بيجدول frame', () {
    s.update(_a);
    frames.runFrame();
    s.update(_a);
    expect(frames.queue, isEmpty);
    frames.runFrame();
    expect(sent, [_a]);
  });

  test('تحديث يرجّع لآخر قيمة مبعوتة قبل الـ frame = مفيش إرسال', () {
    s.update(_a);
    frames.runFrame();
    s.update(_b); // مجدول
    s.update(_a); // رجع لنفس المبعوت
    frames.runFrame();
    expect(sent, [_a]);
  });

  test('قيم مختلفة عبر frames مختلفة بتتبعت بالترتيب', () {
    s.update(_a);
    frames.runFrame();
    s.update(_b);
    frames.runFrame();
    s.update(_c);
    frames.runFrame();
    expect(sent, [_a, _b, _c]);
  });

  test('الوضع مش شغال وقت الـ frame: مفيش إرسال', () {
    s.update(_a);
    active = false;
    frames.runFrame();
    expect(sent, isEmpty);
  });

  test('dispose قبل الـ frame: الـ callback المؤجّل بيتجاهل', () {
    s.update(_a);
    s.dispose();
    frames.runFrame();
    expect(sent, isEmpty);
  });

  test('بعد dispose: update مبيجدولش حاجة', () {
    s.dispose();
    s.update(_a);
    expect(frames.queue, isEmpty);
  });

  test('reset: نفس المركز القديم بيتبعت تاني بعد دخول وضع الاختيار من جديد', () {
    s.update(_a);
    frames.runFrame();
    s.reset();
    s.update(_a);
    frames.runFrame();
    expect(sent, [_a, _a]);
  });

  test('reset بيمسح التحديث المنتظر', () {
    s.update(_a);
    s.reset();
    frames.runFrame();
    expect(sent, isEmpty);
  });

  test('تحديث جديد بعد frame اتنفّذ بيجدول frame جديد', () {
    s.update(_a);
    frames.runFrame();
    s.update(_b);
    expect(frames.queue.length, 1);
  });
}
