// test/jianpu_mixed_staff_test.dart
//
// Multi-staff mixed-notation layouts (docs/JIANPU.md §5):
//   1. one standard staff + one jianpu staff — the same melody rendered two
//      ways (e.g. a sight-reading aid above the numbered row).
//   2. two standard staves (piano grand staff) + one jianpu staff — the
//      piano-vocal (弹唱谱) standard layout.
//
// Jianpu does **not** join cross-staff systemic barlines (its barlines sit on
// its own y = 1..4 row, with no staff lines to bridge), but it **does** share
// the per-measure onset→x column grid, because a jianpu note and a staff
// notehead are the same logical column (one note = one column).

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score stdScore(String notes) => Score.simple(notes: notes);
Score jianpuScore(String notes) =>
    Score.simple(notes: notes, staffType: StaffType.jianpu);

/// Digit centre x positions in a jianpu layout, in column order.
List<double> jianpuDigitXs(ScoreLayout layout) {
  final xs = layout.primitives
      .whereType<TextPrimitive>()
      .where((t) =>
          t.position.y == JianpuLayoutEngine.digitBaseline &&
          // degree digits / rest 0 — exclude the key label "1=X" and time
          // signature numerator/denominator (those sit at other y values).
          t.text.length == 1 &&
          '01234567'.contains(t.text))
      .map((t) => t.position.x)
      .toList()
    ..sort();
  return xs;
}

/// Notehead x positions in a standard-staff layout, in column order.
List<double> noteheadXs(ScoreLayout layout) {
  final xs = layout.primitives
      .whereType<GlyphPrimitive>()
      .where((g) => g.smuflName.startsWith('notehead'))
      .map((g) => g.position.x)
      .toList()
    ..sort();
  return xs;
}

void main() {
  setUpAll(() {
    final source =
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('layoutGrandStaff: standard + jianpu (one melody, two notations)', () {
    test('both staves share the same total width', () {
      final upper = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final lower = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower),
        settings,
      );
      expect(layout.upper.width, closeTo(layout.lower.width, 0.01));
    });

    test('barlines align: every barline x is shared', () {
      final upper = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final lower = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower),
        settings,
      );
      // Closing barline of measure 0: same x on both staves (jianpu's barline
      // sits at y = 1..4 in its own frame; we only compare x).
      final upperBarXs = layout.upper.measureRegions.map((r) => r.endX);
      final lowerBarXs = layout.lower.measureRegions.map((r) => r.endX);
      expect(lowerBarXs.length, upperBarXs.length);
      for (var i = 0; i < upperBarXs.length; i++) {
        expect(lowerBarXs.elementAt(i),
            closeTo(upperBarXs.elementAt(i), 0.01),
            reason: 'barline $i x mismatch');
      }
    });

    test('column alignment: digit x == notehead x at the same onset', () {
      // Same rhythm on both staves: each onset has exactly one column, so the
      // digit centres and notehead centres must line up.
      final upper = stdScore('c4:q d4 e4 f4');
      final lower = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower),
        settings,
      );
      final heads = noteheadXs(layout.upper);
      final digits = jianpuDigitXs(layout.lower);
      expect(digits.length, heads.length,
          reason: 'expected one digit per notehead');
      for (var i = 0; i < heads.length; i++) {
        expect(digits[i], closeTo(heads[i], 0.05),
            reason: 'column $i digit x (${digits[i]}) != notehead x '
                '(${heads[i]})');
      }
    });

    test('jianpu staff is shorter than a 5-line staff', () {
      // Jianpu has no staff lines and its ink box is the digit row plus
      // octave/underline marks — well under the standard staff's ~4 spaces
      // of body plus ledger/stem ink. The grand-staff height picks up the
      // gap, but each layout's own height should reflect this.
      final upper = stdScore('c4:q d4 e4 f4');
      final lower = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower),
        settings,
      );
      expect(layout.lower.height, lessThan(layout.upper.height));
    });
  });

  group('layoutStaffSystem: 2× standard + 1× jianpu (piano + jianpu)', () {
    test('all three staves share the same total width', () {
      final treble = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final bass = stdScore('c3:q d3 e3 f3 | g3:q a3 b3 c4');
      final jianpu = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(
        StaffSystem([treble, bass, jianpu]),
        settings,
      );
      final w = layout.staves.first.width;
      for (final s in layout.staves) {
        expect(s.width, closeTo(w, 0.01));
      }
    });

    test('barlines align across all three staves', () {
      final treble = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final bass = stdScore('c3:q d3 e3 f3 | g3:q a3 b3 c4');
      final jianpu = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(
        StaffSystem([treble, bass, jianpu]),
        settings,
      );
      final refBars = layout.staves[0].measureRegions.map((r) => r.endX);
      for (var s = 1; s < layout.staves.length; s++) {
        final bars = layout.staves[s].measureRegions.map((r) => r.endX);
        expect(bars.length, refBars.length);
        for (var i = 0; i < refBars.length; i++) {
          expect(bars.elementAt(i), closeTo(refBars.elementAt(i), 0.01),
              reason: 'staff $s barline $i mismatch');
        }
      }
    });

    test('jianpu digits align with treble noteheads at the same onset', () {
      final treble = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final bass = stdScore('c3:q d3 e3 f3 | g3:q a3 b3 c4');
      final jianpu = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(
        StaffSystem([treble, bass, jianpu]),
        settings,
      );
      final heads = noteheadXs(layout.staves[0]);
      final digits = jianpuDigitXs(layout.staves[2]);
      expect(digits.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(digits[i], closeTo(heads[i], 0.05),
            reason: 'column $i digit x (${digits[i]}) != treble notehead x '
                '(${heads[i]})');
      }
    });

    test('jianpu staff is its own barline group (no cross-staff connector)',
        () {
      // The user's constraint: 简谱不需要跨 barline 一起渲染 — jianpu's
      // barlines never bridge into the standard staves. With explicit
      // barlineGroups that put jianpu in its own single-staff group, every
      // BarlineSpan of the jianpu staff covers only its own y = 0..4 — never
      // reaching the standard staves above.
      final treble = stdScore('c4:q d4 e4 f4');
      final bass = stdScore('c3:q d3 e3 f3');
      final jianpu = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutStaffSystem(
        StaffSystem(
          [treble, bass, jianpu],
          // treble+bass connected (piano), jianpu on its own.
          barlineGroups: const [
            BarlineGroup(0, 1),
            BarlineGroup(2, 2),
          ],
        ),
        settings,
      );
      final spans = layout.barlineSpans;
      // The jianpu staff's span: top = staffTop(2), bottom = staffTop(2) + 4
      // — exactly its own body, never touching the piano staves above.
      final jianpuSpan = spans.last;
      expect(jianpuSpan.top, closeTo(layout.staffTop(2), 0.001));
      expect(jianpuSpan.bottom, closeTo(layout.staffTop(2) + 4, 0.001));
      // And the piano span ends before the jianpu span starts (a gap, not a
      // connection).
      final pianoSpan = spans.first;
      expect(pianoSpan.bottom, lessThanOrEqualTo(jianpuSpan.top));
    });

    test('default connectBarlines leaves jianpu isolated', () {
      // With no explicit groups and connectBarlines = true (the default), the
      // system would normally draw one barline through all three staves. For
      // a mixed system that includes jianpu, the engine must auto-break the
      // barline at the jianpu boundary (jianpu is never joined across staves).
      final treble = stdScore('c4:q d4 e4 f4');
      final bass = stdScore('c3:q d3 e3 f3');
      final jianpu = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutStaffSystem(
        StaffSystem([treble, bass, jianpu]),
        settings,
      );
      final spans = layout.barlineSpans;
      // The jianpu staff (index 2) is its own group; the two standard staves
      // are joined together (one span over 0..1).
      expect(spans.length, 2);
      expect(spans.last.top, closeTo(layout.staffTop(2), 0.001));
      expect(spans.first.bottom, lessThanOrEqualTo(spans.last.top));
    });
  });

  group('engine routing', () {
    test('layoutGrandStaff picks JianpuLayoutEngine for a jianpu staff', () {
      // A jianpu staff laid out through the grand-staff path must carry
      // jianpu primitives: digit TextPrimitives at the digit baseline. If
      // the router used LayoutEngine instead, the lower layout would have
      // noteheads, not digits.
      final upper = stdScore('c4:q d4 e4 f4');
      final lower = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower),
        settings,
      );
      final digits = jianpuDigitXs(layout.lower);
      expect(digits.length, 4, reason: 'jianpu staff should have 4 digits');
      expect(noteheadXs(layout.lower), isEmpty,
          reason: 'jianpu staff should have no noteheads');
    });

    test('layoutStaffSystem picks the right engine per staff', () {
      final treble = stdScore('c4:q d4 e4 f4');
      final jianpu = jianpuScore('c4:q d4 e4 f4');
      final layout = layoutStaffSystem(
        StaffSystem([treble, jianpu]),
        settings,
      );
      expect(noteheadXs(layout.staves[0]).length, 4);
      expect(jianpuDigitXs(layout.staves[1]).length, 4);
      expect(noteheadXs(layout.staves[1]), isEmpty);
    });
  });
}
