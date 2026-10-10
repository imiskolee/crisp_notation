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
