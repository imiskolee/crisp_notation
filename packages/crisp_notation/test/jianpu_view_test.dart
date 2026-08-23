// test/jianpu_view_test.dart
//
// StaffView / export engine routing by Score.staffType (docs/JIANPU.md §5):
// a jianpu score renders through JianpuLayoutEngine inside the same widget
// and export helpers; a standard score is bit-for-bit the old behaviour.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  setUpAll(setUpCrispNotationForTests);

  group('StaffView jianpu routing', () {
    testWidgets('a jianpu score lays out as numbered notation',
        (tester) async {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        staffType: StaffType.jianpu,
      );
      await tester.pumpWidget(wrap(StaffView(score: score, staffSpace: 12)));
      final render =
          tester.renderObject<RenderStaffView>(find.byType(StaffView));
      final layout = render.scoreLayout!;
      final digits = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.position.y == JianpuLayoutEngine.digitBaseline)
          .map((t) => t.text);
      expect(digits, ['1', '2', '3', '4']);
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=C'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standard score still draws staff lines (regression guard)',
        (tester) async {
      final score = Score.simple(notes: 'c4:q d4 e4 f4');
      await tester.pumpWidget(wrap(StaffView(score: score, staffSpace: 12)));
      final layout = tester
          .renderObject<RenderStaffView>(find.byType(StaffView))
          .scoreLayout!;
      // The five staff lines: full-width horizontals at y = 0..4 (the
      // c4 ledger line sits at y = 5, outside the range).
      final staffLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.y == l.to.y && l.from.y >= 0 && l.from.y <= 4)
          .map((l) => l.from.y)
          .toSet();
      expect(staffLines, {0.0, 1.0, 2.0, 3.0, 4.0});
    });

    testWidgets('jianpu: tapping a digit reports its element id',
        (tester) async {
      final tapped = <String>[];
      final score = Score.simple(
          notes: 'c4:q d4 e4 f4', staffType: StaffType.jianpu);
      await tester.pumpWidget(
        wrap(StaffView(score: score, staffSpace: 12, onElementTap: tapped.add)),
      );
      final render =
          tester.renderObject<RenderStaffView>(find.byType(StaffView));
      final region = render.scoreLayout!.regions
          .firstWhere((r) => r.elementId == 'e1');
      final center =
          (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
      final local = render.staffToLocal(center);
      final topLeft = tester.getTopLeft(find.byType(StaffView));
      await tester.tapAt(topLeft + local);
      expect(tapped, ['e1']);
    });
  });

  group('export routing', () {
    testWidgets('jianpu scores export to SVG with digits and key label',
        (tester) async {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        staffType: StaffType.jianpu,
      );
      final svg = await tester
          .runAsync(() => exportScoreToSvg(score, embedFont: false));
      expect(svg!, contains('>1=C<'));
      expect(svg, contains('>1<'));
    });

    testWidgets('jianpu scores export to PNG bytes', (tester) async {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        staffType: StaffType.jianpu,
      );
      final bytes = await tester.runAsync(() => exportScoreToPng(score));
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(200));
    });
  });
}
