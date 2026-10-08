import 'package:flutter_test/flutter_test.dart';
import 'package:wasalha/features/verification/domain/review_checklist.dart';
import 'package:wasalha/features/verification/models/captain_verification.dart';

void main() {
  group('checklistFor', () {
    test('كابتن بمركبة فيها مستندات: 4 بنود تشمل المركبة', () {
      final l = checklistFor(needsVehicleDocs: true);
      expect(l.map((e) => e.key),
          ['identity_match', 'face_match', 'vehicle_match', 'no_duplicates']);
    });

    test('من غير مستندات مركبة: بند المركبة مش موجود', () {
      final l = checklistFor(needsVehicleDocs: false);
      expect(l.map((e) => e.key), ['identity_match', 'face_match', 'no_duplicates']);
    });

    test('المفاتيح فريدة', () {
      final keys = checklistFor(needsVehicleDocs: true).map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('checklistComplete', () {
    final items = checklistFor(needsVehicleDocs: true);

    test('كل البنود متأكدة = مكتمل', () {
      expect(checklistComplete(items, items.map((e) => e.key).toSet()), isTrue);
    });

    test('بند ناقص أو لا شيء = غير مكتمل', () {
      expect(checklistComplete(items, {'identity_match', 'face_match'}), isFalse);
      expect(checklistComplete(items, <String>{}), isFalse);
    });

    test('بنود زيادة غريبة مش بتعوّض بند ناقص', () {
      expect(checklistComplete(items, {'identity_match', 'face_match', 'x', 'y'}), isFalse);
    });
  });

  group('ReviewInfo.checklist', () {
    test('بيتحفظ ويترجع في toMap/fromMap', () {
      const r = ReviewInfo(
        decision: 'APPROVE',
        reason: '',
        reviewerId: 'admin1',
        reviewedAt: 1000,
        checklist: ['identity_match', 'face_match'],
      );
      final m = r.toMap();
      expect(m['checklist'], ['identity_match', 'face_match']);
      final back = ReviewInfo.fromMap(m)!;
      expect(back.checklist, ['identity_match', 'face_match']);
    });

    test('من غير بنود: الحقل مش بيتكتب (توافق مع القرارات القديمة)', () {
      const r = ReviewInfo(decision: 'REJECT', reason: 'x', reviewerId: 'a', reviewedAt: 1);
      expect(r.toMap().containsKey('checklist'), isFalse);
      expect(ReviewInfo.fromMap({'decision': 'APPROVE', 'reviewerId': 'a'})!.checklist, isEmpty);
    });
  });
}
