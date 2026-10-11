import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late LayoutSettings settings;

NoteElement note(String id, Pitch pitch,
        [NoteDuration duration = NoteDuration.quarter]) =>
    NoteElement(id: id, pitches: [pitch], duration: duration);

List<GlyphPrimitive> heads(ScoreLayout layout, String id) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((p) => p.elementId == id && p.smuflName.startsWith('notehead'))
    .toList();

List<TextPrimitive> zeros(ScoreLayout layout) => layout.primitives
    .whereType<TextPrimitive>()
    .where((p) => p.text == '0' && p.elementId == 'rest')
    .toList();

List<LinePrimitive> tabBars(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((p) => p.from.x == p.to.x && p.from.y == 0 && p.to.y == 7.5)
    .toList();

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  group('fixed StaffSystem timeline', () {
    for (final type in [
      StaffType.standard,
      StaffType.jianpu,
      StaffType.tablature
    ]) {
      for (final meter in [TimeSignature.fourFour, TimeSignature.sixEight]) {
        test('$type $meter fixes notes and bar beats without optical gaps', () {
          final count = meter == TimeSignature.sixEight ? 6 : 8;
          final score = Score(
              clef: Clef.treble,
              staffType: type,
              timeSignature: meter,
              measures: [
                for (var m = 0; m < 3; m++)
                  Measure([
                    for (var i = 0; i < count; i++)
                      note('$m-$i', const Pitch(Step.e, alter: -1, octave: 4),
                          NoteDuration.eighth),
                  ],
                      timeChange: m == 1 ? meter : null,
                      startRepeat: m == 1,
                      endRepeat: m == 1),
              ]);
          for (final beatWidth in [0.1, 4.0]) {
            final layout = layoutStaffSystem(StaffSystem([score]), settings,
                    timelineBeatWidth: beatWidth,
                    timelineLeadingWidth: 0,
                    timelineDurationBeats: 32,
                    spacingStretch: 5,
                    targetWidth: 1000,
                    gridAlign: false)
                .staves
                .single;
            for (var m = 0; m < 3; m++) {
              expect(layout.measureRegions[m].startX,
                  closeTo(m * count / 2 * beatWidth, 1e-9));
              expect(layout.measureRegions[m].endX,
                  closeTo((m + 1) * count / 2 * beatWidth, 1e-9));
              for (var i = 0; i < count; i++) {
                final id = '$m-$i';
                final x = type == StaffType.standard
                    ? heads(layout, id).single.position.x
                    : layout.primitives
                        .whereType<TextPrimitive>()
                        .firstWhere((p) =>
                            p.elementId == id &&
                            RegExp(r'^\d+$').hasMatch(p.text))
                        .position
                        .x;
                final visualOffset =
                    type == StaffType.standard && m > 0 && i == 0
                        ? 2 / 7.5
                        : 0.0;
                expect(
                    x,
                    closeTo(
                        (m * count + i) / 2 * beatWidth + visualOffset, 1e-9));
              }
            }
            expect(layout.width, closeTo(32 * beatWidth, 1e-9));
          }
        });
      }
    }

    test('mixed staves share exact pickup and changed-meter boundaries', () {
      final system = StaffSystem([
        for (final type in [
          StaffType.standard,
          StaffType.jianpu,
          StaffType.tablature
        ])
          Score(
              clef: Clef.treble,
              staffType: type,
              timeSignature: TimeSignature.fourFour,
              measures: [
                Measure([note('$type-pickup', const Pitch(Step.e, octave: 4))],
                    actualDuration: Fraction(1, 4)),
                Measure([
                  for (var i = 0; i < 6; i++)
                    note('$type-$i', const Pitch(Step.e, octave: 4),
                        NoteDuration.eighth)
                ], timeChange: TimeSignature.sixEight),
              ]),
      ]);
      final layout = layoutStaffSystem(system, settings,
          timelineBeatWidth: 4,
          timelineLeadingWidth: 12,
          timelineDurationBeats: 8);
      for (final staff in layout.staves) {
        expect(staff.measureRegions.map((r) => r.startX), [12, 16]);
        expect(staff.measureRegions.map((r) => r.endX), [16, 28]);
        expect(staff.width, 44);
      }
    });

    test(
        'standard internal barline and next note separate around timeline anchor',
        () {
      final score = Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              note('first', const Pitch(Step.d, octave: 4), NoteDuration.whole)
            ]),
            Measure([
              note('next', const Pitch(Step.e, octave: 4), NoteDuration.whole)
            ]),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      final nextHead = heads(layout, 'next').single;
      final internalBar = layout.primitives
          .whereType<LinePrimitive>()
          .singleWhere((p) =>
              p.from.x == p.to.x &&
              p.from.y == 0 &&
              p.to.y == 4 &&
              p.from.x <= layout.measureRegions[1].startX);

      expect(layout.measureRegions.map((r) => (r.startX, r.endX)),
          [(12.0, 28.0), (28.0, 44.0)]);
      expect(internalBar.from.x, closeTo(28 - 2 / 7.5, 1e-9));
      expect(nextHead.position.x, closeTo(28 + 2 / 7.5, 1e-9));
    });

    test('timeline rejects invalid widths and durations', () {
      final system = StaffSystem([
        Score(clef: Clef.treble, measures: [
          Measure([note('n', const Pitch(Step.e, octave: 4))])
        ])
      ]);
      for (final width in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
            () => layoutStaffSystem(system, settings, timelineBeatWidth: width),
            throwsArgumentError);
      }
      for (final value in [-1.0, double.nan, double.infinity]) {
        expect(
            () => layoutStaffSystem(system, settings,
                timelineBeatWidth: 4, timelineLeadingWidth: value),
            throwsArgumentError);
        expect(
            () => layoutStaffSystem(system, settings,
                timelineBeatWidth: 4, timelineDurationBeats: value),
            throwsArgumentError);
      }
    });

    test('fixed whole-bar rest anchors at its onset rather than optical center',
        () {
      final score = Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([RestElement(NoteDuration.whole, id: 'whole')]),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      final rest = layout.primitives
          .whereType<GlyphPrimitive>()
          .singleWhere((p) => p.elementId == 'whole');
      expect(rest.position.x, 12);
      expect(layout.measureRegions.single.endX, 28);
    });

    test('fixed multi-voice whole rest anchors at beat zero', () {
      final score = Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              note('note', const Pitch(Step.e, octave: 4), NoteDuration.whole)
            ], voice2: [
              RestElement(NoteDuration.whole, id: 'whole')
            ]),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      expect(
          layout.primitives
              .whereType<GlyphPrimitive>()
              .singleWhere((p) => p.elementId == 'whole')
              .position
              .x,
          12);
    });

    test('jianpu sustained digits and rest quarter points stay on the timeline',
        () {
      final score = Score(
          clef: Clef.treble,
          staffType: StaffType.jianpu,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([RestElement(NoteDuration.whole, id: 'rest')]),
            Measure([
              note('long', const Pitch(Step.e, octave: 4), NoteDuration.whole)
            ]),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      expect(zeros(layout).map((p) => p.position.x), [12, 16, 20, 24]);
      final dashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((p) => p.elementId == 'long' && p.from.y == p.to.y)
          .toList();
      expect(dashes, hasLength(3));
      expect(dashes.map((p) => (p.from.x + p.to.x) / 2), [32, 36, 40]);
    });

    test('jianpu internal barline stays left of the next fixed-timeline digit',
        () {
      final score = Score(
          clef: Clef.treble,
          staffType: StaffType.jianpu,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              note('first', const Pitch(Step.d, octave: 4), NoteDuration.whole)
            ]),
            Measure([
              note('next', const Pitch(Step.e, octave: 4), NoteDuration.whole)
            ]),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      final digit = layout.primitives
          .whereType<TextPrimitive>()
          .singleWhere((p) => p.elementId == 'next' && p.text == '3');
      final internalBar = layout.primitives
          .whereType<LinePrimitive>()
          .where((p) =>
              p.from.x == p.to.x &&
              p.from.y == JianpuLayoutEngine.barlineTop &&
              p.to.y == JianpuLayoutEngine.barlineBottom)
          .reduce((a, b) => (a.from.x - digit.position.x).abs() <
                  (b.from.x - digit.position.x).abs()
              ? a
              : b);

      expect(digit.position.x, closeTo(28, 1e-9));
      expect(internalBar.to.x, lessThan(digit.position.x));
    });

    test('jianpu start repeat stays left of the fixed-timeline first digit',
        () {
      final score = Score(
          clef: Clef.treble,
          staffType: StaffType.jianpu,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              note('first', const Pitch(Step.c, octave: 4), NoteDuration.whole)
            ]),
            Measure([
              note('repeated', const Pitch(Step.e, octave: 4),
                  NoteDuration.whole)
            ], startRepeat: true),
          ]);
      final layout = layoutStaffSystem(StaffSystem([score]), settings,
              timelineBeatWidth: 4, timelineLeadingWidth: 12)
          .staves
          .single;
      final digit = layout.primitives
          .whereType<TextPrimitive>()
          .singleWhere((p) => p.elementId == 'repeated' && p.text == '3');
      final rightmostRepeatDot = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((p) => p.smuflName == SmuflGlyph.repeatDot)
          .map((p) => p.position.x)
          .reduce((a, b) => a > b ? a : b);

      expect(digit.position.x, closeTo(28, 1e-9));
      expect(rightmostRepeatDot, lessThan(digit.position.x));
    });
  });

  group('shared timeline consumers', () {
    for (final hasLocalEnd in [true, false]) {
      test('short multivoice rest stays at onset, local end $hasLocalEnd', () {
        final score = Score(clef: Clef.treble, measures: [
          Measure([
            note('note', const Pitch(Step.c, octave: 5), NoteDuration.half),
          ], voice2: [
            RestElement(NoteDuration.half, id: 'rest'),
          ]),
        ]);
        final layout = const LayoutEngine()
            .layout(score, settings, leadingWidth: 12, forcedColumns: [
          {
            Fraction.zero: 3,
            if (hasLocalEnd) Fraction(1, 2): 15,
            Fraction(1, 1): 30,
          },
        ]);
        final rest = layout.primitives.whereType<GlyphPrimitive>().singleWhere(
            (p) => p.elementId == 'rest' && p.smuflName.startsWith('rest'));
        expect(rest.position.x, closeTo(15, 1e-9));
        expect(layout.measureRegions.single.endX, closeTo(42, 1e-9));
      });
    }

    for (final alteration in [-1, 1]) {
      for (final joint in [false, true]) {
        test('multivoice accidental $alteration keeps onset, joint $joint', () {
          final score = Score(clef: Clef.treble, measures: [
            Measure([
              note('upper', Pitch(Step.c, alter: alteration, octave: 5)),
            ], voice2: [
              if (joint)
                note('lower', Pitch(Step.e, alter: alteration, octave: 4))
              else
                RestElement(NoteDuration.eighth, id: 'rest'),
            ]),
          ]);
          final layout = const LayoutEngine()
              .layout(score, settings, leadingWidth: 12, forcedColumns: [
            {Fraction.zero: 4, Fraction(1, 1): 30},
          ]);
          expect(heads(layout, 'upper').single.position.x, closeTo(16, 1e-9));
          if (joint) {
            expect(heads(layout, 'lower').single.position.x, closeTo(16, 1e-9));
          }
          final accidentals = layout.primitives
              .whereType<GlyphPrimitive>()
              .where((p) => p.smuflName.startsWith('accidental'));
          expect(accidentals, hasLength(joint ? 2 : 1));
          expect(accidentals.every((p) => p.position.x < 16), isTrue);
        });
      }
    }

    test('TAB explicit final pair uses the shared endpoint as its thin line',
        () {
      final score = Score(clef: Clef.treble, measures: [
        Measure([note('tab', const Pitch(Step.e, octave: 4))],
            barline: BarlineStyle.finalBar),
      ]);
      final layout = const TabLayoutEngine().layout(
          score, Tuning.standardGuitar, settings,
          leadingWidth: 12,
          forcedColumns: [
            {Fraction.zero: 3, Fraction(1, 1): 30},
          ]);
      final bars = tabBars(layout);
      expect(bars, hasLength(2));
      expect(bars.first.from.x, closeTo(42, 1e-9));
      expect(bars.first.thickness, settings.thinBarlineThickness);
      expect(bars.last.thickness, settings.thickBarlineThickness);
      expect(
          bars.last.from.x,
          closeTo(
              42 +
                  settings.thinBarlineThickness / 2 +
                  settings.barlineSeparation +
                  settings.thickBarlineThickness / 2,
              1e-9));
      expect(layout.measureRegions.single.endX, closeTo(42, 1e-9));
      expect(layout.width,
          greaterThanOrEqualTo(bars.last.from.x + bars.last.thickness / 2));
    });

    test('standalone TAB keeps normal final measure as a single line', () {
      final score = Score(clef: Clef.treble, measures: [
        Measure([note('tab', const Pitch(Step.e, octave: 4))]),
      ]);
      final layout = const TabLayoutEngine()
          .layout(score, Tuning.standardGuitar, settings);
      final bars = tabBars(layout);
      expect(bars, hasLength(1));
      expect(bars.single.thickness, settings.thinBarlineThickness);
      expect(bars.single.from.x, layout.measureRegions.single.endX);
    });

    for (final finalBarline in [true, false]) {
      test('mixed TAB normal endpoint follows finalBarline $finalBarline', () {
        final system = StaffSystem([
          for (final type in StaffType.values)
            Score(
              clef: Clef.treble,
              staffType: type,
              measures: [
                Measure([note('$type-first', const Pitch(Step.e, octave: 4))]),
                Measure([note('$type-last', const Pitch(Step.e, octave: 4))]),
              ],
            ),
        ]);
        final layout =
            layoutStaffSystem(system, settings, finalBarline: finalBarline);
        final tab = layout.staves[system.staves
            .indexWhere((score) => score.staffType == StaffType.tablature)];
        final bars = tabBars(tab);
        expect(bars, hasLength(finalBarline ? 3 : 2));
        expect(bars[0].from.x, tab.measureRegions.first.endX);
        expect(bars[0].thickness, settings.thinBarlineThickness);
        final endX = tab.measureRegions.last.endX;
        expect(bars[1].from.x, endX);
        expect(bars[1].thickness, settings.thinBarlineThickness);
        for (final staff in layout.staves) {
          expect(staff.measureRegions.last.endX, closeTo(endX, 1e-9));
        }
        if (finalBarline) {
          expect(bars.last.thickness, settings.thickBarlineThickness);
          expect(
              bars.last.from.x,
              closeTo(
                  endX +
                      settings.thinBarlineThickness / 2 +
                      settings.barlineSeparation +
                      settings.thickBarlineThickness / 2,
                  1e-9));
          expect(tab.width,
              greaterThanOrEqualTo(bars.last.from.x + bars.last.thickness / 2));
        }
      });
    }

    test('wrapped mixed TAB keeps continuation single and final normal double',
        () {
      final system = StaffSystem([
        for (final type in StaffType.values)
          Score(
            clef: Clef.treble,
            staffType: type,
            measures: [
              for (var i = 0; i < 4; i++)
                Measure([note('$type-$i', const Pitch(Step.e, octave: 4))]),
            ],
          ),
      ]);
      final result = layoutStaffSystemSystems(system, settings, maxWidth: 20);
      expect(result.systems.length, greaterThan(1));
      final tabIndex = system.staves
          .indexWhere((score) => score.staffType == StaffType.tablature);
      for (var i = 0; i < result.systems.length; i++) {
        final tab = result.systems[i].layout.staves[tabIndex];
        final isFinal = i == result.systems.length - 1;
        final bars = tabBars(tab);
        expect(bars, hasLength(tab.measureRegions.length + (isFinal ? 1 : 0)));
        expect(bars.take(tab.measureRegions.length).map((bar) => bar.thickness),
            everyElement(settings.thinBarlineThickness));
        expect(bars[tab.measureRegions.length - 1].from.x,
            tab.measureRegions.last.endX);
        if (isFinal) {
          expect(bars.last.thickness, settings.thickBarlineThickness);
        }
      }
    });

    for (final exact in [true, false]) {
      test('jianpu long-rest zeros use shared time, exact $exact', () {
        final score = Score(clef: Clef.treble, measures: [
          Measure([
            note('before', const Pitch(Step.c, octave: 4)),
            RestElement(NoteDuration.half, id: 'rest'),
            note('after', const Pitch(Step.d, octave: 4)),
          ]),
        ]);
        final layout = const JianpuLayoutEngine()
            .layout(score, settings, leadingWidth: 12, forcedColumns: [
          {
            Fraction.zero: 2,
            Fraction(1, 4): 8,
            if (exact) Fraction(1, 2): 21,
            Fraction(3, 4): 30,
            Fraction(1, 1): 40,
          },
        ]);
        final rests = zeros(layout);
        expect(rests, hasLength(2));
        expect(rests.first.position.x, closeTo(20, 1e-9));
        expect(rests.last.position.x, closeTo(exact ? 33 : 31, 1e-9));
        expect(layout.measureRegions.single.endX, closeTo(52, 1e-9));
      });
    }
  });
}
