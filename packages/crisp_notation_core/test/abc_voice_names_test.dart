import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  test('V: nm= / name= become staff instrument names', () {
    final system = staffSystemFromAbc('''X:1
M:4/4
L:1/4
K:C
V:1 nm="Vocal"
V:2 name=Guitar clef=bass
[V:1] C D E F
[V:2] C, D, E, F,
''');
    expect(system.staves.length, 2);
    expect(system.staves[0].metadata.instrument, 'Vocal');
    expect(system.staves[1].metadata.instrument, 'Guitar');
    expect(system.staves[1].clef, Clef.bass);
  });

  test('single voice without nm= keeps null instrument', () {
    final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nC D E F\n');
    expect(score.metadata.instrument, isNull);
  });
}
