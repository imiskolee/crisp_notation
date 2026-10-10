// test/tab_alignment_test.dart
//
// Production-grade mixed-notation alignment: standard staff + jianpu + TAB
// must share the same visual column for every simultaneous onset. This
// catches any drift between the three layout engines' column anchors, which
// is what the Studio UI renders.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score stdScore(String notes) => Score.simple(notes: notes);
Score jianpuScore(String notes) =>
    Score.simple(notes: notes, staffType: StaffType.jianpu);
Score tabScore(String notes) =>
    Score.simple(notes: notes, staffType: StaffType.tablature);

/// All notehead x positions in a standard staff layout.
List<double> noteheadXs(ScoreLayout layout) {
  final xs = layout.primitives
      .whereType<GlyphPrimitive>()
      .where((g) => g.smuflName.startsWith('notehead'))
      .map((g) => g.position.x)
      .toList()
    ..sort();
  return xs;
}

/// All jianpu digit x positions (degree digits '0'..'7').
List<double> jianpuDigitXs(ScoreLayout layout) {
  final xs = layout.primitives
      .whereType<TextPrimitive>()
      .where((t) =>
          '01234567'.contains(t.text) &&
          t.text.length == 1 &&
          // jianpu digits are drawn at a specific baseline
          t.position.y >= JianpuLayoutEngine.digitBaseline - 0.5 &&
          t.position.y <= JianpuLayoutEngine.digitBaseline + 0.5)
      .map((t) => t.position.x)
      .toList()
    ..sort();
  return xs;
}

/// All TAB fret digit x positions (open string '0', fretted 'n', ghost '(n)',
/// dead 'x'). Only strings that look like fret numbers are picked — chord
/// labels ('C', 'G7'), technique marks ('T', 'S', 'P') and long labels
/// ('P.M.', 'let ring') are excluded by the regex itself.
List<double> tabFretXs(ScoreLayout layout) {
  final xs = <double>{};
  for (final primitive in layout.primitives) {
    if (primitive is! TextPrimitive) continue;
    final text = primitive.text;
    final isFret = RegExp(r'^-?\d{1,2}$').hasMatch(text) ||
        RegExp(r'^\(\d{1,2}\)$').hasMatch(text) ||
        text == 'x';
    if (isFret) xs.add(primitive.position.x);
  }
  return xs.toList()..sort();
}

/// Returns the anchor x (notehead / digit / fret) of every element, keyed by
/// `(measureIndex, localOnset)`. Rests are included with their glyph x.
Map<(int, Fraction), double> onsetAnchors(Score score, ScoreLayout layout) {
  // Element id → anchor x, first matching primitive.
  final anchorX = <String, double>{};
  final restIds = {
    for (final m in score.measures)
      for (final e in m.elements)
        if (e is RestElement && e.id != null) e.id!,
  };
  for (final p in layout.primitives) {
    final id = p.elementId;
    if (id == null) continue;
    if (p is GlyphPrimitive) {
      if (p.smuflName.startsWith('notehead') || restIds.contains(id)) {
        anchorX.putIfAbsent(id, () => p.position.x);
      }
    } else if (p is TextPrimitive) {
      final text = p.text;
      if (score.staffType == StaffType.tablature) {
        final isFret = RegExp(r'^-?\d{1,2}$').hasMatch(text) ||
            RegExp(r'^\(\d{1,2}\)$').hasMatch(text) ||
            text == 'x';
        if (isFret) anchorX.putIfAbsent(id, () => p.position.x);
      } else if (score.staffType == StaffType.jianpu &&
          text.length == 1 &&
          '01234567'.contains(text)) {
        anchorX.putIfAbsent(id, () => p.position.x);
      }
    }
  }

  final result = <(int, Fraction), double>{};
  for (var mi = 0; mi < score.measures.length; mi++) {
    var onset = Fraction.zero;
    final measure = score.measures[mi];
    for (var i = 0; i < measure.elements.length; i++) {
      final x = anchorX[measure.elements[i].id];
      if (x != null) result[(mi, onset)] = x;
      onset += measure.effectiveDurationAt(i);
    }
  }
  return result;
}

Map<(int, Fraction), double> voiceOnsetAnchors(
  Score score,
  ScoreLayout layout,
  int voice,
) {
  final anchorX = <String, double>{};
  for (final primitive in layout.primitives) {
    final id = primitive.elementId;
    if (id == null) continue;
    if (primitive is GlyphPrimitive &&
        primitive.smuflName.startsWith('notehead')) {
      anchorX.putIfAbsent(id, () => primitive.position.x);
    } else if (primitive is TextPrimitive) {
      final isAnchor = score.staffType == StaffType.tablature
          ? RegExp(r'^-?\d{1,2}$').hasMatch(primitive.text) ||
              RegExp(r'^\(\d{1,2}\)$').hasMatch(primitive.text) ||
              primitive.text == 'x'
          : score.staffType == StaffType.jianpu &&
              primitive.text.length == 1 &&
              '01234567'.contains(primitive.text);
      if (isAnchor) anchorX.putIfAbsent(id, () => primitive.position.x);
    }
  }

  final result = <(int, Fraction), double>{};
  for (var mi = 0; mi < score.measures.length; mi++) {
    final measure = score.measures[mi];
    final elements = measure.voices[voice];
    var onset = Fraction.zero;
    for (var i = 0; i < elements.length; i++) {
      final x = anchorX[elements[i].id];
      if (x != null) result[(mi, onset)] = x;
      onset += measure.effectiveDurationAt(i, voice: voice);
    }
  }
  return result;
}

NoteElement eighthNote(int midi, String id) => NoteElement(
      pitches: [Pitch.fromMidi(midi)],
      duration: NoteDuration.eighth,
      id: id,
    );

/// Width of the single measure in a laid-out [layout].
double measureWidth(ScoreLayout layout) =>
    layout.measureRegions.single.endX - layout.measureRegions.single.startX;

double drawnBarlineX(ScoreLayout layout, StaffType type) {
  final (top, bottom) = switch (type) {
    StaffType.jianpu => (1.29, 3.23),
    StaffType.tablature => (0.0, 7.5),
    _ => (0.0, 4.0),
  };
  return layout.primitives
      .whereType<LinePrimitive>()
      .where((line) =>
          line.from.x == line.to.x &&
          ((line.from.y == top && line.to.y == bottom) ||
              (line.from.y == bottom && line.to.y == top)))
      .map((line) => line.from.x)
      .reduce(max);
}

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('layoutStaffSystem: standard + jianpu + TAB alignment', () {
    test('barlines share identical x across all three staves', () {
      final s = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final j = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final t = tabScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(StaffSystem([s, j, t]), settings);
      final ref = layout.staves[0].measureRegions.map((r) => r.endX).toList();
      for (var si = 1; si < 3; si++) {
        final bars =
            layout.staves[si].measureRegions.map((r) => r.endX).toList();
        for (var i = 0; i < ref.length; i++) {
          expect(bars[i], closeTo(ref[i], 1e-6),
              reason: 'staff $si barline $i mismatch');
        }
      }
    });

    test('single-measure wrapped systems keep every staff barline aligned', () {
      final score = staffSystemFromAbc('''
X:1
M:6/8
L:1/8
K:F# Major
V:Vocal st=jianpu
z6 | z3/2 =d/2 =d/2 z/2 =e3- |
V:acousticguitar st=tablature
=B,, ^F, =B, ^D =B,2 | ^C, ^G, =B,,4 |
V:violin
z6 | z6 |
''');

      final systems = layoutStaffSystemSystems(
        score,
        settings,
        maxWidth: 28,
      );

      expect(systems.systems.length, greaterThan(1));
      final first = systems.systems.first.layout.staves;
      final staffTypes = score.staves.map((staff) => staff.staffType).toList();
      final expected = drawnBarlineX(first.first, staffTypes.first);
      for (var i = 1; i < first.length; i++) {
        expect(
          drawnBarlineX(first[i], staffTypes[i]),
          closeTo(expected, 1e-6),
          reason: 'staff $i single-measure system barline mismatch',
        );
      }
    });

    test(
        'shared abstract measure time maps a short staff to the global barline',
        () {
      final standard = stdScore('c4:q d e f | g:q a b c');
      final jianpu = jianpuScore('c4:q d e f | g:q a b c');
      final tab = tabScore('c4:h | d:q e f g');
      final layout = layoutStaffSystem(
        StaffSystem([standard, jianpu, tab]),
        settings,
        finalBarline: false,
      );
      final expected = drawnBarlineX(layout.staves[0], StaffType.standard);
      for (var i = 1; i < layout.staves.length; i++) {
        expect(
          drawnBarlineX(layout.staves[i], layout.source.staves[i].staffType),
          closeTo(expected, 1e-6),
          reason: 'short staff $i lost the global abstract-time endpoint',
        );
      }
    });

    test('TAB fret digits align with standard noteheads (quarter notes)', () {
      final s = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final t = tabScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[1]);
      expect(frets.length, heads.length,
          reason: 'fret count != notehead count');
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05),
            reason: 'column $i: fret x=${frets[i]} vs notehead x=${heads[i]}');
      }
    });

    test('jianpu digits align with standard noteheads (regression guard)', () {
      final s = stdScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final j = jianpuScore('c4:q d4 e4 f4 | g4:q a4 b4 c5');
      final layout = layoutStaffSystem(StaffSystem([s, j]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final digits = jianpuDigitXs(layout.staves[1]);
      expect(digits.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(digits[i], closeTo(heads[i], 0.05),
            reason:
                'column $i: jianpu x=${digits[i]} vs notehead x=${heads[i]}');
      }
    });

    test('TAB + jianpu + standard all align together', () {
      final s = stdScore('c4:q d4 e4 f4');
      final j = jianpuScore('c4:q d4 e4 f4');
      final t = tabScore('c4:q d4 e4 f4');
      final layout = layoutStaffSystem(StaffSystem([s, j, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final digits = jianpuDigitXs(layout.staves[1]);
      final frets = tabFretXs(layout.staves[2]);
      expect(digits.length, heads.length);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(digits[i], closeTo(heads[i], 0.05),
            reason: 'col $i jianpu vs head');
        expect(frets[i], closeTo(heads[i], 0.05), reason: 'col $i tab vs head');
      }
    });

    test('TAB alignment with mixed durations (halves + quarters)', () {
      final s = stdScore('c4:h e4:q g4:q | c5:h e5:q g5:q');
      final t = tabScore('c4:h e4:q g4:q | c5:h e5:q g5:q');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[1]);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05),
            reason: 'column $i mixed duration');
      }
    });

    test('TAB alignment with sixteenth notes (dense spacing)', () {
      final s = stdScore('c4:s d4 e4 f4 | g4:s a4 b4 c5');
      final t = tabScore('c4:s d4 e4 f4 | g4:s a4 b4 c5');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[1]);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05),
            reason: 'column $i sixteenth');
      }
    });

    test('TAB alignment with dotted eighth (mixed spacing)', () {
      // dotted-eighth = 3/8 beat → syntax ':e.' (letter + dot), not numeric.
      final s = stdScore('c4:e. d4:e e4:e f4:e. g4:e a4:e');
      final t = tabScore('c4:e. d4:e e4:e f4:e. g4:e a4:e');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[1]);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05), reason: 'column $i dotted');
      }
    });

    test('TAB + jianpu + standard over 4 measures (cumulative drift check)',
        () {
      final s = stdScore(
          'c4:q d4 e4 f4 | g4:q a4 b4 c5 | d5:q c5 b4 a4 | g4:q f4 e4 d4');
      final j = jianpuScore(
          'c4:q d4 e4 f4 | g4:q a4 b4 c5 | d5:q c5 b4 a4 | g4:q f4 e4 d4');
      final t = tabScore(
          'c4:q d4 e4 f4 | g4:q a4 b4 c5 | d5:q c5 b4 a4 | g4:q f4 e4 d4');
      final layout = layoutStaffSystem(StaffSystem([s, j, t]), settings);

      // 4 measures, check every barline's endX across all 3 staves.
      final refBars =
          layout.staves[0].measureRegions.map((r) => r.endX).toList();
      for (var si = 1; si < 3; si++) {
        final bars =
            layout.staves[si].measureRegions.map((r) => r.endX).toList();
        for (var i = 0; i < refBars.length; i++) {
          expect(bars[i], closeTo(refBars[i], 1e-6),
              reason: 'staff $si barline $i drift');
        }
      }

      // Also check measure start X (leading width consistency).
      final refStarts =
          layout.staves[0].measureRegions.map((r) => r.startX).toList();
      for (var si = 1; si < 3; si++) {
        final starts =
            layout.staves[si].measureRegions.map((r) => r.startX).toList();
        for (var i = 0; i < refStarts.length; i++) {
          expect(starts[i], closeTo(refStarts[i], 1e-6),
              reason: 'staff $si measure $i start drift');
        }
      }

      // And fret-to-notehead alignment across all 4 measures.
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[2]);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05), reason: 'global column $i');
      }
    });

    test('TAB alignment with open strings (fret "0")', () {
      final s = stdScore('e2:q a2 d3 g3 b3 e4');
      final t = tabScore('e2:q a2 d3 g3 b3 e4');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);
      final heads = noteheadXs(layout.staves[0]);
      final frets = tabFretXs(layout.staves[1]);
      expect(frets.length, heads.length);
      for (var i = 0; i < heads.length; i++) {
        expect(frets[i], closeTo(heads[i], 0.05),
            reason: 'column $i open string');
      }
    });

    test('TAB alignment with chord onset (3-note chord per beat)', () {
      // 3 triads across one measure — each chord is one onset with 3 notes.
      // TAB stacks 3 fret digits vertically at the same x; the 3 chord
      // noteheads on the standard staff also cluster near the same x
      // (slight offset for seconds/accidentals). We compare onset columns,
      // counting unique notehead/fret x positions.
      final s = stdScore('c4+e4+g4:q d4+f4+a4:q | e4+g4+b4:q');
      final t = tabScore('c4+e4+g4:q d4+f4+a4:q | e4+g4+b4:q');
      final layout = layoutStaffSystem(StaffSystem([s, t]), settings);

      // Unique onset columns per staff — this is what we actually align.
      final uniqueHeads = noteheadXs(layout.staves[0]).toSet().toList()..sort();
      final uniqueFrets = tabFretXs(layout.staves[1]).toSet().toList()..sort();

      expect(uniqueFrets.length, uniqueHeads.length,
          reason: 'unique onset column count');
      for (var i = 0; i < uniqueHeads.length; i++) {
        expect(uniqueFrets[i], closeTo(uniqueHeads[i], 0.05),
            reason: 'onset column $i');
      }
    });

    test(
        'uniform grid: quarter+sharps / eighth+flats / sixteenths align, '
        'densities swap in m1', () {
      // m0: std quarters (#) | jianpu eighths (b) | tab sixteenths.
      // m1: std sixteenths (#) | jianpu eighths | tab quarters — densities
      // swap, so the grid must be computed PER MEASURE independently.
      final std = stdScore(
        'c#4:q d# f# a# | c#4:s d# f# g# a# c# d# f# g# a# c# d# f# g# a# c#',
      );
      final jianpu = jianpuScore(
        'cb4:e db eb gb ab bb db eb | cb:e db eb gb ab bb db eb',
      );
      final tab = tabScore(
        'c4:s d e f g a b c d e f g a b c d | c4:q d e f',
      );
      final layout =
          layoutStaffSystem(StaffSystem([std, jianpu, tab]), settings);
      final maps = [
        for (var i = 0; i < 3; i++)
          onsetAnchors(layout.source.staves[i], layout.staves[i]),
      ];

      // Union of (measure, onset) across staves.
      final allKeys = {...maps[0].keys, ...maps[1].keys, ...maps[2].keys};
      for (final key in allKeys) {
        double? ref;
        for (var si = 0; si < 3; si++) {
          final x = maps[si][key];
          if (x == null) continue;
          if (ref == null) {
            ref = x;
          } else {
            expect(x, closeTo(ref, 0.001),
                reason: 'm${key.$1} onset ${key.$2}: staff $si off');
          }
        }
      }
    });

    test('whole-measure rest is centered while other staves play dense notes',
        () {
      // Standard staff: one whole rest. TAB: 16 sixteenths. The rest must be
      // centered in the (grid-fixed) measure, not pinned to the onset-0 column.
      final std = stdScore('r:w');
      final tab = tabScore('c4:s d e f g a b c d e f g a b c d');
      final layout = layoutStaffSystem(StaffSystem([std, tab]), settings);
      final anchors = onsetAnchors(std, layout.staves[0]);
      expect(anchors.length, 1);
      final restX = anchors.values.single;
      final startX = layout.staves[0].measureRegions[0].startX;
      final endX = layout.staves[0].measureRegions[0].endX;
      expect(restX, closeTo((startX + endX) / 2, 0.05),
          reason: 'whole rest not centered: $restX vs center '
              '${(startX + endX) / 2}');
    });

    test(
        'measure width sanity: sparse whole-note measure is not blown up '
        'beyond ~1.4x its natural width', () {
      // Two sparse staves: a whole note on jianpu and a whole rest on the
      // standard staff. No dense staff forces space, so the final measure
      // must stay close to its single-staff natural width.
      final jianpu = jianpuScore('c4:w');
      final std = stdScore('r:w');

      final natural = jianpuScore('c4:w');
      final naturalLayout =
          const JianpuLayoutEngine().layout(natural, settings);
      final naturalW = naturalLayout.measureRegions.single.endX -
          naturalLayout.measureRegions.single.startX;

      final layout = layoutStaffSystem(StaffSystem([jianpu, std]), settings);
      final finalW = layout.staves[0].measureRegions.single.endX -
          layout.staves[0].measureRegions.single.startX;

      expect(finalW, lessThan(naturalW * 1.4),
          reason: 'sparse measure blown up: final=$finalW vs '
              'natural=$naturalW');
    });

    test('sparse half-note interval is not inflated by later sixteenths', () {
      final sparse = [
        stdScore('b4:h b4:h'),
        jianpuScore('b4:h b4:h'),
        tabScore('b4:h b4:h'),
      ];
      final mixed = [
        sparse[0],
        sparse[1],
        tabScore('b4:h b4:q b4:s b4:s b4:e'),
      ];
      final reference = alignedColumns(sparse, settings).single;
      final columns = alignedColumns(mixed, settings).single;
      final halfAdvance = columns[Fraction(1, 2)]! - columns[Fraction.zero]!;

      expect(
          halfAdvance,
          closeTo(
              reference[Fraction(1, 2)]! - reference[Fraction.zero]!, 1e-9));
      expect(halfAdvance,
          closeTo(settings.spacingBase + 3 * settings.spacingPerLog2, 1e-9));
      expect(
          columns.keys,
          orderedEquals([
            Fraction.zero,
            Fraction(1, 2),
            Fraction(3, 4),
            Fraction(13, 16),
            Fraction(7, 8),
            Fraction(1, 1),
          ]));
    });

    test('prefix rests use the same linear time origin as notes', () {
      final columns = alignedColumns(
        [stdScore('r:q c4:q d4:q e4:q f4:q')],
        settings,
      ).single;
      final start = columns[Fraction.zero]!;
      final quarter = columns[Fraction(1, 4)]!;
      final half = columns[Fraction(1, 2)]!;
      final end = columns[Fraction(1, 1)]!;
      final k = quarter - start;

      expect(k, greaterThan(0));
      expect(half - quarter, closeTo(k, 1e-9));
      expect(end - half, closeTo(k * 2, 1e-9));
    });

    test('measure width sanity: 4 quarter notes stay near natural width', () {
      final std = stdScore('c4:q d e f');
      final jianpu = jianpuScore('c4:q d e f');

      final naturalLayout = const LayoutEngine().layout(std, settings);
      final naturalW = naturalLayout.measureRegions.single.endX -
          naturalLayout.measureRegions.single.startX;

      final layout = layoutStaffSystem(StaffSystem([std, jianpu]), settings);
      final finalW = layout.staves[0].measureRegions.single.endX -
          layout.staves[0].measureRegions.single.startX;

      expect(finalW, lessThan(naturalW * 1.3),
          reason: 'quarter measure blown up: final=$finalW vs '
              'natural=$naturalW');
    });

    test('measure width grows only when a dense staff actually needs space',
        () {
      // TAB 16 sixteenths needs real space; the jianpu whole note must
      // accept that width (cross-staff max rule) — but no more than what
      // the TAB naturally needs.
      final jianpu = jianpuScore('c4:w');
      final tab = tabScore('c4:s d e f g a b c d e f g a b c d');

      final naturalTab =
          const TabLayoutEngine().layout(tab, Tuning.standardGuitar, settings);
      final naturalW = naturalTab.measureRegions.single.endX -
          naturalTab.measureRegions.single.startX;

      final layout = layoutStaffSystem(StaffSystem([jianpu, tab]), settings);
      final finalW = layout.staves[0].measureRegions.single.endX -
          layout.staves[0].measureRegions.single.startX;

      expect(finalW, closeTo(naturalW, naturalW * 0.2),
          reason: 'width should follow dense staff: final=$finalW vs '
              'tab natural=$naturalW');
    });

    test('sparse rest collisions widen only their adjacent interval', () {
      final jianpu = jianpuScore('c4:w');
      final standard = stdScore('r:s r:h');
      final columns = alignedColumns([jianpu, standard], settings).single;
      final rest = metadata.bBoxOf('rest16th');
      final next = metadata.bBoxOf('restHalf');
      final firstAdvance = max(settings.spacingBase,
          rest.neX + max(0.0, -next.swX) + settings.minNoteGap);
      final halfAdvance = max(
          settings.spacingBase + 3 * settings.spacingPerLog2,
          next.neX + settings.minNoteGap);
      final tailAdvance = settings.spacingBase +
          settings.spacingPerLog2 * (4 + log(7 / 16) / ln2);
      expect(columns[Fraction(1, 16)]! - columns[Fraction.zero]!,
          closeTo(firstAdvance, 1e-9));
      expect(columns[Fraction(9, 16)]! - columns[Fraction(1, 16)]!,
          closeTo(halfAdvance, 1e-9));
      expect(columns[Fraction(1, 1)]! - columns[Fraction(9, 16)]!,
          closeTo(tailAdvance, 1e-9));
      expect(columns.keys.toSet(),
          {Fraction.zero, Fraction(1, 16), Fraction(9, 16), Fraction(1, 1)});
      final compact =
          alignedColumns([jianpu, stdScore('r:h')], settings).single;
      expect(compact[Fraction(1, 1)]!, lessThan(12));
    });
    test(
        'overfilled measures (rhythm errors) are clamped to time-signature '
        'length, not stretched to the overflowing onset', () {
      // 4/4 measure: a dotted whole note/rest would sum to 3/2 — bad AI
      // rhythm. The grid must end at 1/1, not 3/2.
      final jianpu = jianpuScore('c4:w.');
      final layout = layoutStaffSystem(StaffSystem([jianpu]), settings);
      final finalW = layout.staves[0].measureRegions.single.endX -
          layout.staves[0].measureRegions.single.startX;

      // Natural *clamped* whole-note measure should be well under a 3/2 grid
      // (~30+). Allow up to 12.
      expect(finalW, lessThan(12),
          reason: 'overfilled measure not clamped: $finalW');
    });

    test('batch rhythm combinations preserve every shared onset column', () {
      final cases = [
        (
          'quarter-eighth-sixteenth',
          'c4:q d e f',
          'c4:e d e f g a b c',
          'c4:s d e f g a b c d e f g a b c d',
        ),
        (
          'dotted-eighth-quarter-sixteenth',
          'c4:e. d:s e:q f:e g:e',
          'c4:q d:q e:q f:q',
          'c4:s d e f g a b c d e f g a b c d',
        ),
        (
          'half-eighth-quarter',
          'c4:h d:h',
          'c4:e d e f g a b c',
          'c4:q d e f',
        ),
      ];

      for (final rhythm in cases) {
        final scores = [
          stdScore(rhythm.$2),
          jianpuScore(rhythm.$3),
          tabScore(rhythm.$4),
        ];
        final layout = layoutStaffSystem(StaffSystem(scores), settings);
        final maps = [
          for (var i = 0; i < scores.length; i++)
            onsetAnchors(scores[i], layout.staves[i]),
        ];
        final keys = <(int, Fraction)>{
          for (final map in maps) ...map.keys,
        };

        for (final key in keys) {
          final xs = [
            for (final map in maps)
              if (map[key] case final x?) x,
          ];
          for (var i = 1; i < xs.length; i++) {
            expect(xs[i], closeTo(xs.first, 0.001),
                reason: '${rhythm.$1} m${key.$1} onset ${key.$2}');
          }
        }
      }
    });

    test('staff order is unchanged for every notation permutation', () {
      final standard = stdScore('c4:q d e f');
      final jianpu = jianpuScore('c4:q d e f');
      final tab = tabScore('c4:q d e f');
      final permutations = [
        [standard, jianpu, tab],
        [tab, standard, jianpu],
        [jianpu, tab, standard],
      ];

      for (final scores in permutations) {
        final layout = layoutStaffSystem(StaffSystem(scores), settings);
        expect(layout.source.staves, orderedEquals(scores));
        for (var i = 0; i < scores.length; i++) {
          expect(identical(layout.source.staves[i], scores[i]), isTrue);
        }
      }
    });

    test('shared columns are invariant under staff order', () {
      final fourFour = Score.simple(
        timeSignature: const TimeSignature(4, 4),
        notes: 'c4:w',
      );
      final threeFour = Score.simple(
        timeSignature: const TimeSignature(3, 4),
        notes: 'c4:h.',
      );

      final forward = alignedColumns([fourFour, threeFour], settings);
      final reversed = alignedColumns([threeFour, fourFour], settings);

      expect(reversed.length, forward.length);
      for (var i = 0; i < forward.length; i++) {
        expect(reversed[i].keys, orderedEquals(forward[i].keys));
        for (final onset in forward[i].keys) {
          expect(reversed[i][onset], closeTo(forward[i][onset]!, 0.001));
        }
      }
    });

    test('actualDuration controls a sparse shared measure barline', () {
      final irregular = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure(
            [eighthNote(60, 'irregular-note')],
            actualDuration: Fraction(3, 4),
          ),
        ],
      );
      final reference = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(3, 4),
        measures: [
          Measure([eighthNote(60, 'reference-note')],
              actualDuration: Fraction(3, 4)),
        ],
      );

      final irregularLayout =
          layoutStaffSystem(StaffSystem([irregular]), settings);
      final referenceLayout =
          layoutStaffSystem(StaffSystem([reference]), settings);

      expect(
        measureWidth(irregularLayout.staves.single),
        closeTo(measureWidth(referenceLayout.staves.single), 0.001),
      );
    });

    test('voice 2 triplet uses effective onsets in shared columns', () {
      final upperMeasure = Measure(
        const [RestElement(NoteDuration.whole, id: 'upper-rest')],
        voice2: [
          eighthNote(60, 'upper-a'),
          eighthNote(62, 'upper-b'),
          eighthNote(64, 'upper-c'),
        ],
        tuplets: const [
          TupletSpan(0, 2, actual: 3, normal: 2, voice: 1),
        ],
      );
      final upper = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [upperMeasure],
      );
      final columns = alignedColumns([upper], settings).single;

      expect(columns, contains(Fraction.zero));
      expect(columns, contains(Fraction(1, 12)));
      expect(columns, contains(Fraction(1, 6)));
      expect(columns, isNot(contains(Fraction(1, 8))));
    });

    test('voice 3 triplet keeps its absolute voice index', () {
      final measure = Measure(
        const [RestElement(NoteDuration.whole, id: 'voice-1-rest')],
        voice3: [
          eighthNote(60, 'voice-3-a'),
          eighthNote(62, 'voice-3-b'),
          eighthNote(64, 'voice-3-c'),
        ],
        tuplets: const [
          TupletSpan(0, 2, actual: 3, normal: 2, voice: 2),
        ],
      );
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [measure],
      );
      final columns = alignedColumns([score], settings).single;

      expect(columns, contains(Fraction.zero));
      expect(columns, contains(Fraction(1, 12)));
      expect(columns, contains(Fraction(1, 6)));
      expect(columns, isNot(contains(Fraction(1, 8))));
    });
  });

  group('piecewise Fraction timeline', () {
    void expectPiecewise(Map<Fraction, double> columns, {double stretch = 1}) {
      final times = columns.keys.toList()..sort();
      expect(times.first, Fraction.zero);
      expect(columns.values.every((x) => x.isFinite), isTrue);
      expect(columns[Fraction.zero], greaterThanOrEqualTo(0));
      for (var i = 1; i < times.length; i++) {
        final delta = times[i] - times[i - 1];
        final ideal = settings.spacingBase +
            settings.spacingPerLog2 * (4 + log(delta.toDouble()) / ln2);
        final advance = columns[times[i]]! - columns[times[i - 1]]!;
        expect(advance, greaterThan(0));
        expect(
            advance,
            greaterThanOrEqualTo(
                max(ideal, settings.minNoteGap) * stretch - 1e-9),
            reason: 'interval ${times[i - 1]} to ${times[i]}');
      }
    }

    test('short voice endpoints remain exact events across measures', () {
      final scores = [
        stdScore('c4:e | d4:e.'),
        tabScore('c4:h | d4:h'),
      ];
      final columns = alignedColumns(scores, settings);
      expect(columns[0].keys.toSet(),
          {Fraction.zero, Fraction(1, 8), Fraction(1, 2)});
      expect(columns[1].keys.toSet(),
          {Fraction.zero, Fraction(3, 16), Fraction(1, 2)});
      for (final measure in columns) {
        expectPiecewise(measure);
      }
    });

    for (final notes in ['r:e. c#4:s d4:h.', 'c4:h r:s r:e r:e r:e']) {
      test('visible rest ink clears adjacent events: $notes', () {
        final score = stdScore(notes);
        final layout =
            layoutStaffSystem(StaffSystem([score]), settings).staves.single;
        final elements = score.measures.single.elements;
        for (var i = 1; i < elements.length; i++) {
          final previous = layout.primitives
              .whereType<GlyphPrimitive>()
              .where((p) => p.elementId == elements[i - 1].id);
          final next = layout.primitives
              .whereType<GlyphPrimitive>()
              .where((p) => p.elementId == elements[i].id);
          expect(previous, isNotEmpty);
          expect(next, isNotEmpty);
          final right = previous
              .map((p) =>
                  p.position.x + metadata.bBoxOf(p.smuflName).neX * p.scale)
              .reduce(max);
          final left = next
              .map((p) =>
                  p.position.x + metadata.bBoxOf(p.smuflName).swX * p.scale)
              .reduce(min);
          expect(left - right, greaterThanOrEqualTo(settings.minNoteGap - 1e-9),
              reason: 'events ${i - 1} and $i');
        }
      });
    }

    final random = Random(0x5eed300);
    final orders = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    for (var sample = 0; sample < 300; sample++) {
      final count = 2 + random.nextInt(3);
      final lengths = [
        for (var m = 0; m < count; m++) Fraction(2 + random.nextInt(3), 4),
      ];
      final scores = <Score>[];
      final expected = [
        for (final length in lengths) <Fraction>{Fraction.zero, length},
      ];
      for (final type in [
        StaffType.standard,
        StaffType.jianpu,
        StaffType.tablature,
      ]) {
        final measures = <Measure>[];
        for (var m = 0; m < count; m++) {
          final elements = <MusicElement>[];
          final tuplets = <TupletSpan>[];
          var onset = Fraction.zero;
          final limit = 2 + random.nextInt(6);
          for (var i = 0; i < limit; i++) {
            final duration = NoteDuration(
              [
                DurationBase.quarter,
                DurationBase.eighth,
                DurationBase.sixteenth
              ][random.nextInt(3)],
              dots: random.nextInt(3),
            );
            final ratio = [(1, 1), (3, 2), (5, 4)][random.nextInt(3)];
            final effective =
                duration.toFraction() * Fraction(ratio.$2, ratio.$1);
            if (onset + effective > lengths[m]) break;
            final id = 'property-$sample-${type.name}-$m-$i';
            elements.add(random.nextInt(4) == 0
                ? RestElement(duration, id: id)
                : NoteElement(
                    pitches: [Pitch.fromMidi(60 + random.nextInt(12))],
                    duration: duration,
                    id: id));
            if (ratio.$1 != 1) {
              tuplets.add(TupletSpan(i, i, actual: ratio.$1, normal: ratio.$2));
            }
            expected[m].add(onset);
            onset += effective;
            expected[m].add(onset);
          }
          measures.add(
              Measure(elements, tuplets: tuplets, actualDuration: lengths[m]));
        }
        scores.add(Score(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            staffType: type,
            measures: measures));
      }
      final order = orders[sample % orders.length];
      final ordered = [for (final i in order) scores[i]];
      test('seed 0x5eed300 sample $sample: exact piecewise shared anchors', () {
        final columns = alignedColumns(ordered, settings);
        final reversed = alignedColumns(ordered.reversed.toList(), settings);
        final layout = layoutStaffSystem(StaffSystem(ordered), settings,
            finalBarline: false);
        final anchors = [
          for (var si = 0; si < ordered.length; si++)
            onsetAnchors(ordered[si], layout.staves[si]),
        ];
        var globalStart = Fraction.zero;
        for (var m = 0; m < count; m++) {
          expectPiecewise(columns[m]);
          expect(columns[m].keys.toSet(), expected[m]);
          expect(reversed[m].keys, orderedEquals(columns[m].keys));
          for (final time in expected[m]) {
            final global = globalStart + time;
            expect(columns[m][global - globalStart],
                closeTo(reversed[m][time]!, 1e-9));
          }
          for (var si = 0; si < ordered.length; si++) {
            final region = layout.staves[si].measureRegions[m];
            expect(region.startX,
                closeTo(layout.staves.first.measureRegions[m].startX, 1e-9));
            expect(region.endX,
                closeTo(region.startX + columns[m][lengths[m]]!, 1e-9));
            final measure = ordered[si].measures[m];
            var onset = Fraction.zero;
            for (var i = 0; i < measure.elements.length; i++) {
              final element = measure.elements[i];
              if (ordered[si].staffType != StaffType.tablature ||
                  element is NoteElement) {
                final actual = anchors[si][(m, onset)];
                expect(actual, isNotNull, reason: 'missing ${element.id}');
                final centered = ordered[si].staffType == StaffType.standard &&
                    element is RestElement &&
                    element.duration.toFraction() == lengths[m];
                expect(
                    actual,
                    closeTo(
                        region.startX +
                            (centered
                                ? columns[m][lengths[m]]! / 2
                                : columns[m][onset]!),
                        1e-8),
                    reason: 'anchor ${element.id}');
              }
              onset += measure.effectiveDurationAt(i);
            }
          }
          globalStart += lengths[m];
        }
      });
    }

    test('dotted notes use optical advances without denominator cells', () {
      final score = jianpuScore('c4:q. d4:q. e4:q');
      final columns = alignedColumns([score], settings).single;
      expectPiecewise(columns);
      expect(columns.keys.toSet(),
          {Fraction.zero, Fraction(3, 8), Fraction(3, 4), Fraction(1, 1)});
      final dottedAdvance = settings.spacingBase +
          settings.spacingPerLog2 * (4 + log(3 / 8) / ln2);
      final quarterAdvance = settings.spacingBase + 2 * settings.spacingPerLog2;
      expect(columns[Fraction(3, 8)]! - columns[Fraction.zero]!,
          closeTo(dottedAdvance, 1e-9));
      expect(columns[Fraction(3, 4)]! - columns[Fraction(3, 8)]!,
          closeTo(dottedAdvance, 1e-9));
      expect(columns[Fraction(1, 1)]! - columns[Fraction(3, 4)]!,
          closeTo(quarterAdvance, 1e-9));
    });

    test('triplets and quarters share exact events without an LCM width', () {
      final triplet = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure(
            [for (var i = 0; i < 6; i++) eighthNote(71, 'triplet-$i')],
            tuplets: const [TupletSpan(0, 5, actual: 3, normal: 2)],
            actualDuration: Fraction(1, 2),
          ),
        ],
      );
      final quarter = Score.simple(
        timeSignature: const TimeSignature(2, 4),
        notes: 'b4:q b4:q',
      );
      final columns = alignedColumns([triplet, quarter], settings).single;
      expectPiecewise(columns);
      expect(
          columns.keys.toSet(), {for (var i = 0; i <= 6; i++) Fraction(i, 12)});
      final advance = settings.spacingBase +
          settings.spacingPerLog2 * (4 + log(1 / 12) / ln2);
      expect(columns[Fraction(1, 2)]! - columns[Fraction.zero]!,
          closeTo(6 * advance, 1e-9));
    });

    test('cross-voice right ink clears the next onset accidental', () {
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure(
            [
              NoteElement(
                  pitches: [Pitch.fromMidi(71)],
                  duration: NoteDuration.quarter,
                  id: 'upper-first'),
              NoteElement(
                  pitches: [Pitch.fromMidi(70)],
                  duration: NoteDuration.quarter,
                  id: 'upper-next'),
            ],
            voice2: [
              NoteElement(
                  pitches: [Pitch.fromMidi(71)],
                  duration: NoteDuration.quarter,
                  id: 'lower-first'),
              NoteElement(
                  pitches: [Pitch.fromMidi(60)],
                  duration: NoteDuration.quarter,
                  id: 'lower-next'),
            ],
          ),
        ],
      );
      final columns = alignedColumns([score], settings).single;
      expectPiecewise(columns);
      final layout =
          layoutStaffSystem(StaffSystem([score]), settings).staves.single;
      final firstRight = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((p) =>
              p.elementId == 'lower-first' &&
              p.smuflName.startsWith('notehead'))
          .map((p) => p.position.x + metadata.bBoxOf(p.smuflName).neX * p.scale)
          .reduce(max);
      final nextLeft = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((p) =>
              p.elementId == 'upper-next' &&
              p.smuflName.startsWith('accidental'))
          .map((p) => p.position.x + metadata.bBoxOf(p.smuflName).swX * p.scale)
          .reduce(min);
      expect(nextLeft - firstRight,
          greaterThanOrEqualTo(settings.minNoteGap - 1e-9));
    });

    test('stretch scales every time distance but not the left padding', () {
      final score = jianpuScore('c#4:e. d4:s e4:q f4:h');
      final natural = alignedColumns([score], settings).single;
      for (final stretch in [0.8, 1.5, 2.0]) {
        final scaled =
            alignedColumns([score], settings, spacingStretch: stretch).single;
        expectPiecewise(scaled, stretch: stretch);
        expect(scaled[Fraction.zero], closeTo(natural[Fraction.zero]!, 1e-9));
        for (final time in natural.keys) {
          expect(
              scaled[time]! - scaled[Fraction.zero]!,
              closeTo(
                  (natural[time]! - natural[Fraction.zero]!) * stretch, 1e-9));
        }
      }
    });

    test('jianpu collision floor measures actual dots instead of advance boxes',
        () {
      final score = jianpuScore('c4:e. c#4:s d4:h.');
      final columns = alignedColumns([score], settings).single;
      expectPiecewise(columns);
      final layout =
          layoutStaffSystem(StaffSystem([score]), settings).staves.single;
      final first = score.measures.single.elements[0].id;
      final second = score.measures.single.elements[1].id;
      final dot = layout.primitives.whereType<GlyphPrimitive>().firstWhere(
          (p) => p.elementId == first && p.smuflName == 'augmentationDot');
      final accidental = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((p) =>
              p.elementId == second && p.smuflName.startsWith('accidental'));
      final right =
          dot.position.x + metadata.bBoxOf(dot.smuflName).neX * dot.scale;
      final left = accidental.position.x +
          metadata.bBoxOf(accidental.smuflName).swX * accidental.scale;
      expect(left - right, greaterThanOrEqualTo(settings.minNoteGap - 1e-9));
    });
  });

  group('piecewise spacing: measure width follows shared time intervals', () {
    double densityW(String notes) {
      final score = Score.simple(notes: notes);
      final layout = layoutStaffSystem(StaffSystem([score]), settings);
      return measureWidth(layout.staves[0]);
    }

    test('whole < half < quarter < eighth < sixteenth (total width ordering)',
        () {
      final whole = densityW('c4:w');
      final half = densityW('c4:h d4');
      final quarter = densityW('c4:q d e f');
      final eighth = densityW('c4:e d e f g a b c');
      final sixteenth = densityW('c4:s d e f g a b c d e f g a b c d');

      expect(whole, lessThan(half));
      expect(half, lessThan(quarter));
      expect(quarter, lessThan(eighth));
      expect(eighth, lessThan(sixteenth));
      // The quarter measure must be MUCH smaller than the sixteenth measure.
      expect(quarter, lessThan(sixteenth * 0.6),
          reason: 'quarter=$quarter vs sixteenth=$sixteenth');
      // A whole-note measure is roughly one cell: well under half the quarter
      // measure's width.
      expect(whole, lessThan(quarter * 0.6),
          reason: 'whole=$whole vs quarter=$quarter');
    });

    test('per-cell width: the larger the time unit, the wider the cell', () {
      // quarter cell vs sixteenth cell: the user's rule — a quarter cell is a
      // little wider than a sixteenth cell.
      final quarter = densityW('c4:q d e f');
      final sixteenth = densityW('c4:s d e f g a b c d e f g a b c d');
      expect(quarter / 4, greaterThan(sixteenth / 16),
          reason: 'quarter cell=${quarter / 4} should exceed sixteenth '
              'cell=${sixteenth / 16}');
    });

    test('fine rests widen coarse density only enough to clear their ink', () {
      final score = stdScore('c4:h r:s r:e r:e r:e');
      final columns = alignedColumns([score], settings).single;
      final first = metadata.bBoxOf('rest16th');
      final second = metadata.bBoxOf('rest8th');
      final minimum = max(settings.spacingBase,
          first.neX + max(0.0, -second.swX) + settings.minNoteGap);
      expect(columns[Fraction(9, 16)]! - columns[Fraction(1, 2)]!,
          closeTo(minimum, 1e-9));
      expect(columns[Fraction(1, 2)]! - columns[Fraction.zero]!,
          closeTo(settings.spacingBase + 3 * settings.spacingPerLog2, 1e-9));
      final compact = alignedColumns([stdScore('c4:h r:h')], settings).single;
      expect(compact[Fraction(1, 1)]! - compact[Fraction.zero]!, lessThan(10));
    });
    test(
        'cross-staff density: a dense TAB staff refines the shared grid for '
        'sparse staves', () {
      // jianpu whole note + TAB 16 sixteenths → shared grid 16 cells, because
      // the TAB's NOTE density is real; width ~29.
      final jianpu = jianpuScore('c4:w');
      final tab = tabScore('c4:s d e f g a b c d e f g a b c d');
      final layout = layoutStaffSystem(StaffSystem([jianpu, tab]), settings);
      final w = measureWidth(layout.staves[0]);
      expect(w, greaterThan(24),
          reason: 'shared grid should follow dense TAB: $w');
    });

    test(
        'screen systems are not justified to maxWidth (sparse lines stay '
        'narrow)', () {
      // 4 sparse measures in a wide line: a justified non-final system is
      // stretched to maxWidth; the renderer must opt out so density width is
      // what reaches the UI.
      final score = Score.simple(notes: 'c4:w | c4:w | c4:w | c4:w');
      final natural = layoutStaffSystem(
        StaffSystem([Score.simple(notes: 'c4:w | c4:w | c4:w | c4:w')]),
        settings,
      );
      final naturalW = natural.width;

      final wrapped = layoutStaffSystemSystems(
        StaffSystem([score]),
        settings,
        maxWidth: 200,
        justify: false,
      );
      // Ragged single system keeps its natural (density) width.
      expect(wrapped.systems.single.layout.width,
          closeTo(naturalW, naturalW * 0.02));
      expect(wrapped.systems.single.layout.width, lessThan(40));
    });
  });
}
