import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A `Q:` used to be VISIBLE and INAUDIBLE.
///
/// The reader rendered it as a text annotation — which is what the layout
/// draws, since nothing in it draws [Tempo] — but never set `Score.tempo`, and
/// the writer emitted no `Q:` at all. So an imported ABC tune printed its
/// metronome mark and then played at the default tempo, and an export dropped
/// the mark entirely.
void main() {
  Score read(String q) =>
      scoreFromAbc('X:1\n${q.isEmpty ? '' : '$q\n'}L:1/4\nK:C\nC D E F|\n');

  group('Q: reaches the model', () {
    test('a plain metronome mark', () {
      expect(read('Q:1/4=120').tempo, const Tempo(120));
    });

    test('a bare number is a quarter, which is what ABC says it is', () {
      expect(read('Q:120').tempo, const Tempo(120));
    });

    test('a labelled mark keeps the mark', () {
      expect(read('Q:"Allegro" 1/4=120').tempo, const Tempo(120));
    });

    test('3/8 is a DOTTED QUARTER, not three eighths', () {
      // Three eighths is not a beat unit the model can name, and rounding it
      // to an eighth would make the piece three times too fast.
      final t = read('Q:3/8=60').tempo!;
      expect(t.beatUnit, DurationBase.quarter);
      expect(t.dots, 1);
      expect(t.quarterBpm, 90);
    });

    test('no Q: sets no tempo', () {
      expect(read('').tempo, isNull);
    });
  });

  group('initial and changed tempo display', () {
    const changed = 'X:1\nM:4/4\nL:1/4\nQ:1/4=58\nK:C\n'
        'C D E F | [Q:1/4=72] G A B c |\n';

    test('header Q sets playback tempo without a visible annotation', () {
      final score = scoreFromAbc(changed);
      expect(score.tempo, const Tempo(58));
      expect(score.annotations.map((a) => a.text), isNot(contains('♩ = 58')));
    });

    test('inline Q changes the next measure and annotates its first note', () {
      final score = scoreFromAbc(changed);
      expect(score.measures[1].tempoChange, const Tempo(72));
      expect(score.annotations.map((a) => (a.elementId, a.text)),
          [('e4', '♩ = 72')]);
    });

    test('tempo map starts at the header tempo then applies the change', () {
      final map = tempoMapOf(scoreFromAbc(changed));
      expect(map.spans, hasLength(2));
      expect(map.spans[0].at, Fraction(0, 1));
      expect(map.spans[0].quarterBpm, 58);
      expect(map.spans[1].at, Fraction(1, 1));
      expect(map.spans[1].quarterBpm, 72);
    });

    test('standalone body Q has the same structured and visible semantics', () {
      final score = scoreFromAbc(
        'X:1\nM:4/4\nL:1/4\nQ:1/4=58\nK:C\n'
        'C D E F |\nQ:1/4=72\nG A B c |\n',
      );
      expect(score.measures[1].tempoChange, const Tempo(72));
      expect(score.annotations.map((a) => (a.elementId, a.text)),
          [('e4', '♩ = 72')]);
    });
  });

  group('the writer emits Q: without printing the mark twice', () {
    String qLine(String q) => scoreToAbc(read(q))
        .split('\n')
        .firstWhere((l) => l.startsWith('Q:'), orElse: () => '');

    test('a tempo becomes a Q: field', () {
      expect(qLine('Q:1/4=120'), 'Q:1/4=120');
      expect(qLine('Q:3/8=60'), 'Q:3/8=60');
    });

    test('a bare number is normalised to the explicit form', () {
      expect(qLine('Q:120'), 'Q:1/4=120');
    });

    test('a header label is not retained as a visible annotation', () {
      // `Tempo` carries playback speed but not free text; header Q: no longer
      // creates an annotation solely to preserve that label for export.
      expect(qLine('Q:"Allegro" 1/4=120'), 'Q:1/4=120');
    });

    test('the derived annotation is NOT also written into the body', () {
      // It is regenerated on the next read; writing it too would print the
      // metronome mark twice, once from Q: and once as body text.
      final abc = scoreToAbc(read('Q:1/4=120'));
      expect(abc, isNot(contains('"♩ = 120"')));
      expect(abc, isNot(contains(r'"^♩ = 120"')));
    });

    test('an ordinary annotation on the first note is NOT suppressed', () {
      final s = scoreFromAbc('X:1\nQ:1/4=120\nL:1/4\nK:C\n"^rit."C D E F|\n');
      final abc = scoreToAbc(s);
      expect(abc, contains('Q:1/4=120'));
      expect(abc, contains('rit.'));
    });

    test('a score with no tempo writes no Q:', () {
      expect(qLine(''), '');
    });
  });

  _multipleAnnotationsTest();

  test('tempo and annotations are both stable over a round trip', () {
    for (final q in [
      'Q:1/4=120',
      'Q:"Allegro" 1/4=120',
      'Q:3/8=60',
      'Q:120',
      '',
    ]) {
      final once = read(q);
      final twice = scoreFromAbc(scoreToAbc(once));
      expect(twice.tempo, once.tempo, reason: q);
      expect(twice.annotations.map((a) => a.text),
          once.annotations.map((a) => a.text),
          reason: q);
    }
  });
}

void _multipleAnnotationsTest() {
  test('a note carrying SEVERAL annotations keeps them all', () {
    // The writer's map was keyed id -> String, so a second annotation on the
    // same note overwrote the first. A note with both a tempo mark and a
    // direction on it is the ordinary case that makes it visible.
    final s = Score(
      clef: Clef.treble,
      measures: [
        Measure(<MusicElement>[
          NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter)),
        ]),
      ],
      annotations: const [
        Annotation('e0', 'rit.'),
        Annotation('e0', 'dolce'),
      ],
    );
    final back = scoreFromAbc(scoreToAbc(s));
    expect(back.annotations.map((a) => a.text), ['rit.', 'dolce']);
  });
}
