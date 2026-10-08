import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasalha/features/tracking/models/tracking_models.dart';
import 'package:wasalha/features/tracking/services/captain_locations.dart';
import 'package:wasalha/features/tracking/services/driver_location_source.dart';

class _Src implements DriverLocationSource {
  _Src(this.ctrl);
  final StreamController<GeoFix> ctrl;
  @override
  Stream<GeoFix> watch() => ctrl.stream;
}

GeoFix _fix(double lat, double lng) =>
    GeoFix(position: LatLng(lat, lng), updatedAt: DateTime.now());

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late Map<String, StreamController<GeoFix>> ctrls;
  late int created;
  late CaptainLocations locs;

  setUp(() {
    ctrls = {};
    created = 0;
    locs = CaptainLocations(sourceFor: (id) {
      created++;
      return _Src(ctrls[id] = StreamController<GeoFix>.broadcast());
    });
  });

  tearDown(() => locs.dispose());

  test('بيشترك مرة واحدة لكل كابتن ويحدّث مواقعهم', () async {
    locs.sync(['a', 'b']);
    locs.sync(['a', 'b']); // نفس القائمة: مفيش اشتراكات جديدة
    expect(created, 2);

    ctrls['a']!.add(_fix(30.1, 31.1));
    ctrls['b']!.add(_fix(30.2, 31.2));
    await _pump();
    expect(locs.locations.value.keys.toSet(), {'a', 'b'});
    expect(locs.locations.value['a']!.position, const LatLng(30.1, 31.1));
  });

  test('الكابتن اللي يختفي من القائمة بيتقفل اشتراكه وبيتشال موقعه', () async {
    locs.sync(['a', 'b']);
    ctrls['a']!.add(_fix(30.1, 31.1));
    ctrls['b']!.add(_fix(30.2, 31.2));
    await _pump();

    locs.sync(['a']);
    await _pump();
    expect(ctrls['b']!.hasListener, isFalse);
    expect(ctrls['a']!.hasListener, isTrue);
    expect(locs.locations.value.containsKey('b'), isFalse);
    expect(locs.locations.value.containsKey('a'), isTrue);
  });

  test('خطأ في موقع كابتن واحد ما بيوقفش الباقيين', () async {
    locs.sync(['a', 'b']);
    ctrls['a']!.addError(StateError('permission-denied'));
    ctrls['b']!.add(_fix(30.2, 31.2));
    await _pump();
    expect(locs.locations.value.containsKey('b'), isTrue);
  });

  test('كابتن من غير موقع ما بيظهرش في الخريطة', () async {
    locs.sync(['a']);
    await _pump();
    expect(locs.locations.value, isEmpty);
  });

  test('IDs فاضية بتتجاهل، و dispose بيقفل كل حاجة', () async {
    locs.sync(['', 'a']);
    expect(created, 1);
    locs.dispose();
    await _pump();
    expect(ctrls['a']!.hasListener, isFalse);
    locs.sync(['a']); // بعد dispose: ما بيعملش حاجة ولا بيرمي
    expect(created, 1);
  });
}
