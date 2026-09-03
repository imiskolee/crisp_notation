import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('Score.simple DSL', () {
    test('parses pitches and durations', () {
      final score = Score.simple(notes: 'c4:q d4:q e4:h');
      expect(score.measures, hasLength(1));
      final elements = score.measures.first.elements;
      expect(elements, hasLength(3));
      expect(
        elements[0],
        const NoteElement(
          pitches: [Pitch(Step.c)],
          duration: NoteDuration.quarter,
          id: 'e0',
        ),
      );
      expect(
        (elements[2] as NoteElement).duration,
        NoteDuration.half,
      );
    });

    test('durations are sticky and default to quarter', () {
      final score = Score.simple(notes: 'c4 d4:e e4 f4:h g4');
      final durations =
          score.measures.first.elements.map((e) => e.duration).toList();
      expect(durations, [
        NoteDuration.quarter,
        NoteDuration.eighth,
        NoteDuration.eighth,
        NoteDuration.half,
        NoteDuration.half,
      ]);
    });

    test('dotted durations', () {
      final score = Score.simple(notes: 'c4:q. d4:h..');
      expect(
        score.measures.first.elements[0].duration,
        const NoteDuration(DurationBase.quarter, dots: 1),
      );
      expect(
        score.measures.first.elements[1].duration,
        const NoteDuration(DurationBase.half, dots: 2),
      );
    });

    test('rests', () {
      final score = Score.simple(notes: 'c4:q r r:h');
      final elements = score.measures.first.elements;
      expect(elements[1], const RestElement(NoteDuration.quarter, id: 'e1'));
      expect(elements[2], const RestElement(NoteDuration.half, id: 'e2'));
    });

    test('chords via +', () {
      final score = Score.simple(notes: 'c4+e4+g4:h');
      final chord = score.measures.first.elements.single as NoteElement;
      expect(chord.pitches, const [
        Pitch(Step.c),
        Pitch(Step.e),
        Pitch(Step.g),
      ]);
      expect(chord.duration, NoteDuration.half);
    });

    test('measures split on |', () {
      final score = Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c4:q d4 e4 | f4 g4 a4 | b4:h.',
      );
      expect(score.measures, hasLength(3));
      for (final measure in score.measures) {
        expect(measure.totalDuration, Fraction(3, 4), reason: '$measure');
      }
    });

    test('accidentals incl. forced naturals', () {
      final score = Score.simple(notes: 'f#4:q bb3 cn5');
      final elements = score.measures.first.elements.cast<NoteElement>();
      expect(elements[0].pitches.single, const Pitch(Step.f, alter: 1));
      expect(elements[0].showAccidental, isNull);
      expect(
        elements[1].pitches.single,
        const Pitch(Step.b, alter: -1, octave: 3),
      );
      expect(elements[2].pitches.single, const Pitch(Step.c, octave: 5));
      expect(elements[2].showAccidental, isTrue);
    });

    test('pitches without an accidental inherit the key signature', () {
      // E♭ major: B♭, E♭, A♭.
      final score = Score.simple(
        keySignature: const KeySignature(-3),
        notes: 'b4:q e5 a4 c5 bn4 bb4',
      );
      final elements = score.measures.first.elements.cast<NoteElement>();
      expect(elements[0].pitches.single, const Pitch(Step.b, alter: -1));
      expect(
        elements[1].pitches.single,
        const Pitch(Step.e, alter: -1, octave: 5),
      );
      expect(elements[2].pitches.single, const Pitch(Step.a, alter: -1));
      // C is unaltered in E♭ major.
      expect(elements[3].pitches.single, const Pitch(Step.c, octave: 5));
      // An explicit suffix always wins over the key signature.
      expect(elements[4].pitches.single, const Pitch(Step.b));
      expect(elements[4].showAccidental, isTrue);
      expect(elements[5].pitches.single, const Pitch(Step.b, alter: -1));
    });

    test('a !key= directive re-keys the notes that follow it', () {
      final score = Score.simple(notes: 'f4:q | !key=1 f4 | f4 !key=0 f4');
      NoteElement noteAt(int m, int i) =>
          score.measures[m].elements[i] as NoteElement;
      // C major: F natural.
      expect(noteAt(0, 0).pitches.single, const Pitch(Step.f));
      // G major from the directive on: F♯.
      expect(noteAt(1, 0).pitches.single, const Pitch(Step.f, alter: 1));
      expect(score.measures[1].keyChange, const KeySignature(1));
      // The directive takes effect where it stands: the first f keeps G
      // major's F♯, the second is back to C major's F natural.
      expect(noteAt(2, 0).pitches.single, const Pitch(Step.f, alter: 1));
      expect(noteAt(2, 1).pitches.single, const Pitch(Step.f));
    });

    test('grace notes inherit the key signature', () {
      final score = Score.simple(
        keySignature: const KeySignature(-1), // F major: B♭
        notes: '{b4,f#5}c5:q',
      );
      final note = score.measures.first.elements.single as NoteElement;
      expect(note.graceNotes, const [
        Pitch(Step.b, alter: -1),
        Pitch(Step.f, alter: 1, octave: 5),
      ]);
    });

    test('ids are assigned in reading order across measures', () {
      final score = Score.simple(notes: 'c4:q d4 | r e4');
      final ids = [
        for (final measure in score.measures)
          for (final element in measure.elements) element.id,
      ];
      expect(ids, ['e0', 'e1', 'e2', 'e3']);
    });

    test('carries clef and signatures', () {
      final score = Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(-2),
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:w',
      );
      expect(score.clef, Clef.bass);
      expect(score.keySignature, const KeySignature(-2));
      expect(score.timeSignature, TimeSignature.fourFour);
    });

    test('rejects malformed input', () {
      expect(() => Score.simple(notes: 'h4:q'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:z'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:q:q'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:q...'), throwsFormatException);
      expect(() => Score.simple(notes: 'c+4'), throwsFormatException);
    });
  });

  group('Measure.totalDuration', () {
    test('sums exactly', () {
      final measure = Measure([
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        const RestElement(NoteDuration.eighth),
        NoteElement.note(
          const Pitch(Step.d),
          const NoteDuration(DurationBase.eighth, dots: 1),
        ),
      ]);
      // 1/4 + 1/8 + 3/16 = 9/16.
      expect(measure.totalDuration, Fraction(9, 16));
      expect(const Measure([]).totalDuration, Fraction.zero);
    });
  });

  group('value semantics', () {
    test('elements', () {
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
      );
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        isNot(NoteElement.note(const Pitch(Step.d), NoteDuration.quarter)),
      );
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter, id: 'a'),
        isNot(NoteElement.note(const Pitch(Step.c), NoteDuration.quarter)),
      );
      expect(
        const RestElement(NoteDuration.quarter),
        const RestElement(NoteDuration.quarter),
      );
      expect(
        const RestElement(NoteDuration.quarter),
        isNot(const RestElement(NoteDuration.half)),
      );
    });

    test('scores parsed from the same string are equal', () {
      expect(
        Score.simple(notes: 'c4:q d4 | e4:h'),
        Score.simple(notes: 'c4:q d4 | e4:h'),
      );
      expect(
        Score.simple(notes: 'c4:q'),
        isNot(Score.simple(notes: 'c4:h')),
      );
      expect(
        Score.simple(notes: 'c4:q'),
        isNot(Score.simple(notes: 'c4:q', clef: Clef.bass)),
      );
    });
  });
}
