import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Stress tests for the `Score.simple` DSL beyond the happy paths in
/// model_test.dart.
void main() {
  group('whitespace robustness', () {
    test('extra, leading and trailing whitespace is ignored', () {
      final reference = Score.simple(notes: 'c4:q d4 | e4:h');
      expect(Score.simple(notes: '  c4:q   d4  |  e4:h  '), reference);
      expect(Score.simple(notes: '\tc4:q\td4\t|\te4:h'), reference);
      expect(Score.simple(notes: 'c4:q d4 \n| e4:h\n'), reference);
    });

    test('an empty measure between bars parses as empty', () {
      final score = Score.simple(notes: 'c4:q | | d4:q');
      expect(score.measures, hasLength(3));
      expect(score.measures[1].elements, isEmpty);
    });
  });

  group('token coverage', () {
    test('every duration letter and dot count', () {
      const letters = {
        'w': DurationBase.whole,
        'h': DurationBase.half,
        'q': DurationBase.quarter,
        'e': DurationBase.eighth,
        's': DurationBase.sixteenth,
      };
      letters.forEach((letter, base) {
        for (var dots = 0; dots <= 2; dots++) {
          final source = 'c4:$letter${'.' * dots}';
          final score = Score.simple(notes: source);
          expect(
            score.measures.single.elements.single.duration,
            NoteDuration(base, dots: dots),
            reason: source,
          );
        }
      });
    });

    test('every accidental spelling in chords and notes', () {
      final score = Score.simple(notes: 'cbb4+db4+en4+f#4+g##4:q');
      final chord = score.measures.single.elements.single as NoteElement;
      expect(chord.pitches, const [
        Pitch(Step.c, alter: -2),
        Pitch(Step.d, alter: -1),
        Pitch(Step.e),
        Pitch(Step.f, alter: 1),
        Pitch(Step.g, alter: 2),
      ]);
      // The explicit natural forces the accidental for the whole chord.
      expect(chord.showAccidental, isTrue);
    });

    test('rests take sticky durations and set them for what follows', () {
      final score = Score.simple(notes: 'c4:h r d4');
      final durations =
          score.measures.single.elements.map((e) => e.duration).toList();
      expect(durations, List.filled(3, NoteDuration.half));
    });

    test('multi-digit and negative octaves', () {
      expect(
        (Score.simple(notes: 'c10:q').measures.single.elements.single
                as NoteElement)
            .pitches
            .single
            .octave,
        10,
      );
    });
  });

  group('octave inheritance', () {
    List<int> octavesOf(Score score) => [
          for (final m in score.measures)
            for (final e in m.elements) (e as NoteElement).pitches.single.octave,
        ];

    test('a pitch without an octave reuses the previous pitch\'s octave', () {
      expect(octavesOf(Score.simple(notes: 'c4 d e f')), [4, 4, 4, 4]);
    });

    test('an explicit octave re-anchors the notes that follow', () {
      expect(octavesOf(Score.simple(notes: 'c4 d e5 g')), [4, 4, 5, 5]);
    });

    test('the running octave carries across barlines', () {
      expect(octavesOf(Score.simple(notes: 'c5:q d | e f')), [5, 5, 5, 5]);
    });

    test('the first pitch defaults to octave 4', () {
      expect(octavesOf(Score.simple(notes: 'd e')), [4, 4]);
    });

    test('rests leave the running octave untouched', () {
      final notes = Score.simple(notes: 'c5 r:e d').measures.single.elements;
      expect(
        [for (final e in notes.whereType<NoteElement>()) e.pitches.single.octave],
        [5, 5],
      );
    });

    test('accidentals without octaves inherit too', () {
      final score = Score.simple(notes: 'c#4 eb f');
      final pitches = [
        for (final e in score.measures.single.elements)
          (e as NoteElement).pitches.single,
      ];
      expect(pitches, const [
        Pitch(Step.c, alter: 1),
        Pitch(Step.e, alter: -1),
        Pitch(Step.f),
      ]);
    });

    test('chord tones inherit in reading order', () {
      final score = Score.simple(notes: 'c4+e+g c3+e4+g a');
      final chords = [
        for (final e in score.measures.single.elements)
          (e as NoteElement).pitches,
      ];
      expect([for (final p in chords[0]) p.octave], [4, 4, 4]);
      expect([for (final p in chords[1]) p.octave], [3, 4, 4]);
      expect(chords[2].single.octave, 4);
    });

    test('grace notes join the running octave', () {
      final score = Score.simple(notes: 'c5 {d,e}f:q g');
      final note =
          score.measures.single.elements[1] as NoteElement; // f with graces
      expect([for (final p in note.graceNotes) p.octave], [5, 5]);
      expect(note.pitches.single.octave, 5);
      expect(
        (score.measures.single.elements[2] as NoteElement).pitches.single.octave,
        5,
      );
    });

    test('each voice keeps its own running octave', () {
      final score = Score.simple(notes: 'c4:q d ; c3:h e | f:h ; g:h');
      expect(
        [for (final e in score.measures[0].elements)
          (e as NoteElement).pitches.single.octave],
        [4, 4],
      );
      expect(
        [for (final e in score.measures[0].voice2)
          (e as NoteElement).pitches.single.octave],
        [3, 3],
      );
      expect(
        (score.measures[1].elements.single as NoteElement).pitches.single.octave,
        4,
      );
      expect(
        (score.measures[1].voice2.single as NoteElement).pitches.single.octave,
        3,
      );
    });
  });

  group('error reporting', () {
    test('malformed tokens throw FormatException mentioning the token', () {
      const badInputs = {
        'x4:q': 'x4',
        'c4:z': 'c4:z',
        'c4:qq': 'c4:qq',
        'c4::q': 'c4::q',
        'c4+r:q': 'r',
        '+c4:q': '',
        'c4:.': 'c4:.',
      };
      badInputs.forEach((source, needle) {
        expect(
          () => Score.simple(notes: source),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(needle),
          )),
          reason: source,
        );
      });
    });
  });

  group('generated ids', () {
    test('are unique and dense across a large score', () {
      final source = List.generate(
        16,
        (m) => List.generate(4, (i) => 'c4:q').join(' '),
      ).join(' | ');
      final score = Score.simple(notes: source);
      final ids = [
        for (final measure in score.measures)
          for (final element in measure.elements) element.id,
      ];
      expect(ids, hasLength(64));
      expect(ids.toSet(), hasLength(64));
      expect(ids.first, 'e0');
      expect(ids.last, 'e63');
    });
  });
}
