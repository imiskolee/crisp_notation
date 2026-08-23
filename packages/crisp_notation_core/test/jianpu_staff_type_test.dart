// test/jianpu_staff_type_test.dart
//
// `Score.staffType` — the notation-engine selector on the document model
// (docs/JIANPU.md §3). Additive: a score that never mentions it is
// byte-identical to one built before the field existed.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('Score.staffType', () {
    test('defaults to standard', () {
      expect(Score.simple(notes: 'c4:q').staffType, StaffType.standard);
    });

    test('copyWith sets it and equality distinguishes it', () {
      final score = Score.simple(notes: 'c4:q');
      final jianpu = score.copyWith(staffType: StaffType.jianpu);
      expect(jianpu.staffType, StaffType.jianpu);
      expect(jianpu, isNot(score));
      expect(jianpu.copyWith(staffType: StaffType.standard), score);
    });

    test('the DSL builder can set it directly', () {
      final score = Score.simple(
        notes: 'c4:q',
        staffType: StaffType.jianpu,
      );
      expect(score.staffType, StaffType.jianpu);
    });

    test('transposition preserves it', () {
      final jianpu =
          Score.simple(notes: 'c4:q').copyWith(staffType: StaffType.jianpu);
      expect(
        jianpu.transposedBy(Interval.perfectFifth).staffType,
        StaffType.jianpu,
      );
    });

    test('defines all four notation kinds', () {
      expect(
        StaffType.values,
        containsAll([
          StaffType.standard,
          StaffType.jianpu,
          StaffType.tablature,
          StaffType.percussion,
        ]),
      );
    });
  });
}
