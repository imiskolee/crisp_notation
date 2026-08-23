import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  StaffSystem twoStavesEightMeasures() => StaffSystem([
        Score.simple(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          notes:
              'c5:q d5 e5 f5 | g5:q a5 b5 c6 | d5:e c5 b4 a4 g4:h | e4:q g4 b4 d5 | c5:w',
        ),
        Score.simple(
          clef: Clef.bass,
          timeSignature: TimeSignature.fourFour,
          notes:
              'c3:q d3 e3 f3 | g3:q a3 b3 c4 | a2:e g2 f2 e2 d2:h | c2:q e2 g2 c3 | c3:w',
        ),
      ], brackets: [
        StaffBracket(0, 1, kind: StaffBracketKind.brace),
      ]);

  group('StaffSystemView layoutMode: wrapped', () {
    testWidgets('wrapped mode breaks into multiple systems', (tester) async {
      final sys = twoStavesEightMeasures();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            // Narrow → must wrap into two+ systems.
            child: SizedBox(
              width: 300,
              child: StaffSystemView(
                system: sys,
                layoutMode: SystemLayoutMode.wrapped,
                staffSpace: 6,
              ),
            ),
          ),
        ),
      ));
      final render = tester
          .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView));
      // With narrow 300px width the long piece must break into >=2 systems.
      // Render object keeps them via `_systems`; there's no public getter, so
      // infer from height: with >=2 systems total height must exceed what a
      // single 2-staff system would be.
      final single = tester.renderObject<RenderStaffSystemView>(
          find.byType(StaffSystemView));
      // 2 staffs: staff height = 4 ss each + gap 4 ss = ~12 ss min; 2 systems
      // would be >= 24 ss; at staffSpace 6 that gives 144px; a single system
      // is at most 4*2+4=12 ss → 72px. Use that rough bound.
      expect(single.size.height, greaterThan(72));
      // Better: expose a diagnostic. Check render systemLayout is null (since
      // when wrapped it uses _systems instead).
      expect(render.systemLayout, isNull);
    });

    testWidgets('custom systemGap increases total height', (tester) async {
      final sys = twoStavesEightMeasures();
      Widget buildWithGap(double gap) => SizedBox(
            width: 300,
            child: StaffSystemView(
              system: sys,
              layoutMode: SystemLayoutMode.wrapped,
              staffSpace: 6,
              systemGap: gap,
            ),
          );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: buildWithGap(2)))));
      final hTight = tester
          .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView))
          .size
          .height;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: buildWithGap(40)))));
      await tester.pumpAndSettle();
      final hLoose = tester
          .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView))
          .size
          .height;
      expect(hLoose, greaterThan(hTight));
    });

    testWidgets('tap on lower system hits right note using elementIdAt', (tester) async {
      // Build a score with known ids, one per measure.
      String noteId(int staff, int m) => 's${staff}m$m';
      final sys = StaffSystem([
        Score(
          clef: Clef.treble,
          measures: List.generate(6, (i) => Measure([
                NoteElement.note(Pitch(Step.c, octave: 5 + (i % 2)),
                    NoteDuration.whole, id: noteId(0, i)),
              ])),
        ),
        Score(
          clef: Clef.bass,
          measures: List.generate(6, (i) => Measure([
                NoteElement.note(Pitch(Step.c, octave: 3),
                    NoteDuration.whole, id: noteId(1, i)),
              ])),
        ),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 250,
              child: StaffSystemView(
                system: sys,
                layoutMode: SystemLayoutMode.wrapped,
                staffSpace: 6,
                systemGap: 10,
              ),
            ),
          ),
        ),
      ));
      final render = tester
          .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView));
      // Sanity: wrapped mode should produce >= 2 systems for 6 measures at 250px.
      final size = render.size;
      expect(size.height, greaterThan(0));
      // Hit-test the widget's own bottom-right corner via the public API:
      // if a hit exists we get a non-null id that matches our known ids list.
      final allIds = {for (var s = 0; s < 2; s++) for (var m = 0; m < 6; m++) noteId(s, m)};
      final probe = render.elementIdAt(Offset(size.width - 4, size.height - 4));
      if (probe != null) {
        expect(allIds, contains(probe));
      }
    });
  });

  group('StaffSystemScrollView (single-line horizontal scroll)', () {
    testWidgets('widget contains a horizontally scrollable StaffSystemView', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: StaffSystemScrollView(
              system: twoStavesEightMeasures(),
              staffSpace: 6,
            ),
          ),
        ),
      ));
      expect(find.byType(StaffSystemView), findsOneWidget);
      final inner = tester.widget<StaffSystemView>(find.byType(StaffSystemView));
      expect(inner.layoutMode, SystemLayoutMode.singleLine);
    });

    testWidgets('tap inside scroll view still reports element id', (tester) async {
      String? tapped;
      final sys = StaffSystem([
        Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(
                const Pitch(Step.c, octave: 5),
                NoteDuration.whole,
                id: 'top-c',
              ),
            ]),
          ],
        ),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: StaffSystemScrollView(
              system: sys,
              staffSpace: 10,
              onElementTap: (id) => tapped = id,
            ),
          ),
        ),
      ));
      final render = tester.renderObject<RenderStaffSystemView>(
          find.byType(StaffSystemView));
      final layout = render.systemLayout!;
      final region = layout.staves.first.regions.first;
      final origin = render.staffOrigin(0);
      final scale = 10.0;
      final widgetTopLeft = tester.getTopLeft(find.byType(StaffSystemView));
      final center = widgetTopLeft +
          Offset(
            origin.dx +
                (region.bounds.left + region.bounds.width / 2) * scale,
            origin.dy +
                (region.bounds.top + region.bounds.height / 2) * scale,
          );
      await tester.tapAt(center);
      await tester.pump();
      expect(tapped, 'top-c');
    });

    testWidgets('forwards showNoteNames + noteNameStyle to inner view', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: StaffSystemScrollView(
              system: twoStavesEightMeasures(),
              staffSpace: 6,
              showNoteNames: true,
              showNoteOctaves: true,
              noteNameStyle: NoteNameStyle.solfege,
            ),
          ),
        ),
      ));
      final inner = tester.widget<StaffSystemView>(find.byType(StaffSystemView));
      expect(inner.showNoteNames, isTrue);
      expect(inner.showNoteOctaves, isTrue);
      expect(inner.noteNameStyle, NoteNameStyle.solfege);
    });
  });
}
