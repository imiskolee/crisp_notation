import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:crisp_notation_core/src/layout/beam_grouping.dart';
import 'package:test/test.dart';

/// Contract tests for the shared beam/underline grouping (staff beams and
/// jianpu 减时线 both consume `computeBeamRuns`).
void main() {
  Fraction f(int n, int d) => Fraction(n, d);

  /// Onsets of `count` eighth notes starting at zero.
  List<Fraction> eighthOnsets(int count) =>
      [for (var i = 0; i < count; i++) f(i, 8)];

  List<List<int>> runs(
    List<Fraction> onsets, {
    TimeSignature? time,
    BeamItemRole Function(int)? roleAt,
    int Function(int)? spanAt,
  }) =>
      computeBeamRuns(
        count: onsets.length,
        onsetAt: (i) => onsets[i],
        roleAt: roleAt ?? (_) => BeamItemRole.beamable,
        spanAt: spanAt,
        time: time,
      );

  group('beamGroupBoundaries', () {
    test('simple meters are one window per beat', () {
      expect(beamGroupBoundaries(TimeSignature.fourFour),
          [f(0, 1), f(1, 4), f(1, 2), f(3, 4)]);
      expect(beamGroupBoundaries(TimeSignature.twoFour), [f(0, 1), f(1, 4)]);
    });

    test('compound meters group in threes', () {
      expect(beamGroupBoundaries(TimeSignature.sixEight), [f(0, 1), f(3, 8)]);
    });

    test('additive meters use their components', () {
      expect(beamGroupBoundaries(TimeSignature.additive([3, 2], 8)),
          [f(0, 1), f(3, 8)]);
    });

    test('3/8 and 3/16 are a single whole-measure window', () {
      expect(beamGroupBoundaries(const TimeSignature(3, 8)), [f(0, 1)]);
      expect(beamGroupBoundaries(const TimeSignature(3, 16)), [f(0, 1)]);
    });
  });

  group('computeBeamRuns', () {
    test('4/4: eight eighths group per beat — no half-measure merge', () {
      expect(
        runs(eighthOnsets(8), time: TimeSignature.fourFour),
        [
          [0, 1],
          [2, 3],
          [4, 5],
          [6, 7]
        ],
      );
    });

    test('2/4: four eighths group per beat', () {
      expect(
          runs(eighthOnsets(4), time: TimeSignature.twoFour), [
        [0, 1],
        [2, 3]
      ]);
    });

    test('3/8: three eighths form one whole-measure run', () {
      expect(
          runs(eighthOnsets(3), time: const TimeSignature(3, 8)), [
        [0, 1, 2]
      ]);
    });

    test('6/8: six eighths group in threes', () {
      expect(
          runs(eighthOnsets(6), time: TimeSignature.sixEight), [
        [0, 1, 2],
        [3, 4, 5]
      ]);
    });

    test('unmetered: quarter-note windows', () {
      expect(runs(eighthOnsets(4)), [
        [0, 1],
        [2, 3]
      ]);
    });

    test('a breaker ends the run', () {
      expect(
        runs(eighthOnsets(4),
            roleAt: (i) =>
                i == 1 ? BeamItemRole.breaker : BeamItemRole.beamable),
        [
          [0],
          [2, 3]
        ],
      );
    });

    test('a transparent item is skipped without breaking the run', () {
      // Staff rest: the beam passes over it within the same window. Four
      // sixteenths sit in one quarter window; the rest at index 1 keeps the
      // remaining three in a single run.
      final sixteenths = [for (var i = 0; i < 4; i++) f(i, 16)];
      expect(
        runs(sixteenths,
            time: TimeSignature.fourFour,
            roleAt: (i) =>
                i == 1 ? BeamItemRole.transparent : BeamItemRole.beamable),
        [
          [0, 2, 3]
        ],
      );
    });

    test('runs never cross a span boundary in either direction', () {
      // Four sixteenths in one beat (window 0), split 2+2 by tuplet spans.
      final sixteenths = [for (var i = 0; i < 4; i++) f(i, 16)];
      expect(
        runs(sixteenths,
            time: TimeSignature.fourFour, spanAt: (i) => i < 2 ? 0 : 1),
        [
          [0, 1],
          [2, 3]
        ],
      );
    });

    test('singleton runs are returned (the caller filters)', () {
      expect(
        runs(eighthOnsets(3), time: TimeSignature.fourFour),
        [
          [0, 1],
          [2]
        ],
      );
    });
  });
}
