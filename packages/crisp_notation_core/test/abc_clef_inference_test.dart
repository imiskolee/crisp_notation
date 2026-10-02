/// Clef inference: a voice with no explicit clef gets the treble/bass clef
/// whose ledger-line count is lowest for its pitch layout.
library;

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('clef inference', () {
    test('a low part with no clef infers bass', () {
      // C3–G3 range: far below the treble staff (heavy ledger lines), sits
      // comfortably in bass.
      final abc = '''
X:1
M:4/4
L:1/4
K:C
C, D, E, F, | G, A, B, C |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.bass);
    });

    test('a mid/high part with no clef stays treble', () {
      final abc = '''
X:1
M:4/4
L:1/4
K:C
c d e f | g a b c' |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.treble);
    });

    test('an explicit V: clef is never second-guessed', () {
      // Low notes but an explicit treble clef (e.g. guitar notation written
      // at pitch) — keep it.
      final abc = '''
X:1
M:4/4
L:1/4
K:C
V:1 clef=treble
C, D, E, F, |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.treble);
    });

    test('an explicit K: header clef is never second-guessed', () {
      final abc = '''
X:1
M:4/4
L:1/4
K:C clef=treble
C, D, E, F, |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.treble);
    });

    test('a mid-tune clef change suppresses inference', () {
      final abc = '''
X:1
M:4/4
L:1/4
K:C
C D E F | [K:C clef=bass] G A B c |
''';
      final score = scoreFromAbc(abc);
      // The mid-tune change is honored; inference does not override the
      // starting clef.
      expect(score.clef, Clef.treble);
    });

    test('rest-only voice keeps the default clef', () {
      final abc = '''
X:1
M:4/4
L:1/4
K:C
z4 | z4 |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.treble);
    });

    test('multi-voice: each voice infers independently', () {
      final abc = '''
X:1
M:4/4
L:1/4
K:C
V:1
c d e f |
V:2
C, D, E, F, |
''';
      final system = staffSystemFromAbc(abc);
      expect(system.staves[0].clef, Clef.treble);
      expect(system.staves[1].clef, Clef.bass);
    });

    test('boundary: middle-C region prefers treble on a tie', () {
      // Around middle C both clefs need similar ledger lines; the tie-break
      // keeps treble (the conventional default).
      final abc = '''
X:1
M:4/4
L:1/4
K:C
C D E F |
''';
      final score = scoreFromAbc(abc);
      expect(score.clef, Clef.treble);
    });
  });
}
