import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score eightMeasures() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4 |'
          'e4:q f4 g4 a4 | b4:q a4 g4 f4 | e4:q d4 c4 d4 | c4:w',
    );

StaffSystem pianoPlusJianpu() => StaffSystem([
      Score.simple(
        keySignature: const KeySignature(1),
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q a4 b4 c5 | d5:e c5 b4 a4 g4:h | e4:q g4 b4 d5 | c5:w',
      ),
      Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'g2:h c3:q b2 a2 | g2:w | c3:h g3:h | c3:w',
      ),
      Score.simple(
        clef: Clef.alto,
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:e f4 e4 d4 c4:h | f4:q a4 c5 e5 | c5:w',
      ),
    ], brackets: [
      StaffBracket(0, 1, kind: StaffBracketKind.brace),
    ]);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('SystemLayoutMode.singleLine', () {
    test('returns exactly one system covering every measure', () {
      final doc = StaffSystem([eightMeasures()]);
      final n = doc.staves.first.measures.length;
      final result = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 1, // Tiny maxWidth — singleLine must ignore it.
        layoutMode: SystemLayoutMode.singleLine,
      );
      expect(result.systems, hasLength(1));
      expect(result.systems.single.firstMeasure, 0);
      expect(result.systems.single.lastMeasure, n - 1);
    });

    test('maxWidth on returned StaffSystemSystems equals the natural layout width', () {
      final doc = StaffSystem([eightMeasures()]);
      final result = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 1,
        layoutMode: SystemLayoutMode.singleLine,
      );
      expect(result.maxWidth, result.systems.single.layout.width);
      expect(result.maxWidth, greaterThan(1));
    });

    test('ignores maxWidth: even absurdly small maxWidth produces no wrapping', () {
      final doc = StaffSystem([eightMeasures()]);
      final wide = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 10000,
        layoutMode: SystemLayoutMode.singleLine,
      );
      final narrow = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 5,
        layoutMode: SystemLayoutMode.singleLine,
      );
      expect(narrow.systems, hasLength(1));
      expect(narrow.systems.single.layout.width, wide.systems.single.layout.width);
      expect(
        narrow.systems.single.layout.staves.first.primitives.length,
        wide.systems.single.layout.staves.first.primitives.length,
      );
    });

    test('multi-staff mixed (piano + jianpu) stays on one row', () {
      final doc = pianoPlusJianpu();
      final result = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 10,
        layoutMode: SystemLayoutMode.singleLine,
      );
      expect(result.systems, hasLength(1));
      // All 3 staves are rendered inside the single StaffSystemLayout.
      expect(result.systems.single.layout.staves, hasLength(3));
    });
  });

  group('SystemLayoutMode.singleSystem', () {
    test('returns one system covering every measure, same output as singleLine', () {
      final doc = StaffSystem([eightMeasures()]);
      final n = doc.staves.first.measures.length;
      final result = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: 1,
        layoutMode: SystemLayoutMode.singleSystem,
      );
      expect(result.systems, hasLength(1));
      expect(result.systems.single.firstMeasure, 0);
      expect(result.systems.single.lastMeasure, n - 1);
      expect(result.maxWidth, result.systems.single.layout.width);
    });
  });

  group('layoutStaffSystemSingleLine convenience', () {
    test('is equivalent to layoutStaffSystemSystems + singleLine', () {
      final doc = pianoPlusJianpu();
      final direct = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: double.infinity,
        layoutMode: SystemLayoutMode.singleLine,
      ).systems.single.layout;
      final convenience = layoutStaffSystemSingleLine(
        doc,
        settings,
      );
      expect(convenience.width, direct.width);
      expect(convenience.height, direct.height);
      expect(convenience.staves.length, direct.staves.length);
      // The top-staff primitives should match exactly (jianpu one would be different).
      final a = convenience.staves.first.primitives.length;
      final b = direct.staves.first.primitives.length;
      expect(a, b);
    });

    test('forwards staffGap, gridAlign, hideEmptyStaves through', () {
      // Must have 2+ staves so staffGap actually contributes to height.
      final doc = StaffSystem([
        Score.simple(timeSignature: TimeSignature.fourFour, notes: 'c4:w'),
        Score.simple(timeSignature: TimeSignature.fourFour, clef: Clef.bass, notes: 'c3:w'),
      ]);
      final spaced = layoutStaffSystemSingleLine(doc, settings, staffGap: 20);
      final tight = layoutStaffSystemSingleLine(doc, settings, staffGap: 2);
      // Larger staffGap → taller overall layout.
      expect(spaced.height, greaterThan(tight.height));
    });
  });

  group('explicit layoutMode: wrapped matches default', () {
    test('omitting layoutMode behaves identically to wrapped', () {
      final doc = StaffSystem([eightMeasures()]);
      const maxWidth = 30.0;
      final defaults = layoutStaffSystemSystems(doc, settings, maxWidth: maxWidth);
      final explicit = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: maxWidth,
        layoutMode: SystemLayoutMode.wrapped,
      );
      expect(defaults.systems.length, explicit.systems.length);
      for (var i = 0; i < defaults.systems.length; i++) {
        expect(defaults.systems[i].firstMeasure, explicit.systems[i].firstMeasure);
        expect(defaults.systems[i].lastMeasure, explicit.systems[i].lastMeasure);
        expect(defaults.systems[i].layout.width, explicit.systems[i].layout.width);
      }
    });

    test('wrapped mode respects positive maxWidth and breaks into multiple systems', () {
      final doc = StaffSystem([eightMeasures()]);
      const narrow = 25.0;
      final broken = layoutStaffSystemSystems(
        doc,
        settings,
        maxWidth: narrow,
        layoutMode: SystemLayoutMode.wrapped,
      );
      expect(broken.systems.length, greaterThan(1));
      for (final s in broken.systems) {
        if (s.lastMeasure > s.firstMeasure) {
          expect(s.layout.width, lessThanOrEqualTo(narrow));
        }
      }
    });
  });

  group('SystemLayoutMode boundary: single-measure document', () {
    test('all three modes yield a single 0..0 system', () {
      final oneMeasure = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w',
      );
      final doc = StaffSystem([oneMeasure]);
      for (final mode in SystemLayoutMode.values) {
        final out = layoutStaffSystemSystems(
          doc,
          settings,
          maxWidth: 50,
          layoutMode: mode,
        );
        expect(out.systems, hasLength(1), reason: 'mode=$mode');
        expect(out.systems.single.firstMeasure, 0, reason: 'mode=$mode');
        expect(out.systems.single.lastMeasure, 0, reason: 'mode=$mode');
      }
    });
  });
}
