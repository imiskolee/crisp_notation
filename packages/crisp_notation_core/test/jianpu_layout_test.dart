// test/jianpu_layout_test.dart
//
// JianpuLayoutEngine — the numbered-notation (简谱) parallel engine
// (docs/JIANPU.md §4). Reads the same Score model as the staff engine and
// produces the same ScoreLayout primitives.

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout jianpuOf(Score score) =>
    const JianpuLayoutEngine().layout(score, settings);

/// Digit/rest texts at the digit baseline, in x order.
List<TextPrimitive> digitsOf(ScoreLayout layout) {
  final digits = layout.primitives
      .whereType<TextPrimitive>()
      .where((t) => t.position.y == JianpuLayoutEngine.digitBaseline)
      .toList()
    ..sort((a, b) => a.position.x.compareTo(b.position.x));
  return digits;
}

/// Horizontal lines at an underline level (below the digit row).
List<LinePrimitive> underlinesOf(ScoreLayout layout) =>
    layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y == l.to.y && l.from.y > 3.05)
        .toList();

List<String> describe(ScoreLayout layout) => [
      for (final p in layout.primitives)
        switch (p) {
          final GlyphPrimitive g => 'glyph:${g.smuflName}@${g.position}',
          final LinePrimitive l => 'line:${l.from}->${l.to}:${l.thickness}',
          final BeamPrimitive b =>
            'beam:${b.start}->${b.end}:${b.thickness}',
          final CurvePrimitive c => 'curve:${c.start},${c.control1},'
              '${c.control2},${c.end}',
          final TextPrimitive t => 'text:${t.text}@${t.position}:${t.size}',
        },
    ].toList();

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('digits and degrees', () {
    test('C major scale renders as 1 2 3 4 5 6 7', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4 f4 g4 a4 b4'));
      expect(digitsOf(layout).map((d) => d.text),
          ['1', '2', '3', '4', '5', '6', '7']);
    });

    test('digits ascend left to right', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4'));
      final xs = digitsOf(layout).map((d) => d.position.x).toList();
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
      }
    });

    test('G major: g is 1 and the key label reads 1=G', () {
      final layout = jianpuOf(Score.simple(
        notes: 'g4:q a4 b4',
        keySignature: const KeySignature(1),
      ));
      expect(digitsOf(layout).map((d) => d.text), ['1', '2', '3']);
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=G'),
      );
    });

    test('F major: written B natural is a raised 4, B flat a plain 4', () {
      final layout = jianpuOf(Score.simple(
        notes: 'b4:q bb4:q',
        keySignature: const KeySignature(-1),
      ));
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('♯')); // prefix glyph before the first 4
      expect(digitsOf(layout).map((d) => d.text), ['4', '4']);
    });

    test('an accidental deviating from the key gets a prefix', () {
      final layout = jianpuOf(Score.simple(notes: 'f#4:q'));
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('♯'));
      expect(digitsOf(layout).single.text, '4');
    });

    test('a rest renders as 0', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q r:q d4'));
      expect(digitsOf(layout).map((d) => d.text), ['1', '0', '2']);
    });

    test('a chord keeps its highest pitch (documented v1 degradation)', () {
      final layout = jianpuOf(Score.simple(notes: 'c4+e4+g4:q'));
      expect(digitsOf(layout).single.text, '5');
    });
  });

  group('octave dots', () {
    test('the tonic octave carries no dots', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q g4'));
      expect(layout.primitives.whereType<GlyphPrimitive>(), isEmpty);
    });

    test('one octave up puts a dot above the digit', () {
      final layout = jianpuOf(Score.simple(notes: 'c5:q'));
      final digit = digitsOf(layout).single;
      final dots = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => (g.position.x - digit.position.x).abs() < 0.4);
      expect(dots, hasLength(1));
      expect(dots.single.position.y, lessThan(1.6)); // above the digit top
    });

    test('one octave down puts a dot below the digit', () {
      final layout = jianpuOf(Score.simple(notes: 'c3:q'));
      final digit = digitsOf(layout).single;
      final dots = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => (g.position.x - digit.position.x).abs() < 0.4);
      expect(dots, hasLength(1));
      expect(dots.single.position.y, greaterThan(3.0));
    });

    test('two octaves stack two dots', () {
      final layout = jianpuOf(Score.simple(notes: 'c6:q'));
      expect(layout.primitives.whereType<GlyphPrimitive>(), hasLength(2));
    });

    test('the 7 above the tonic is not dotted (b4 in C major)', () {
      final layout = jianpuOf(Score.simple(notes: 'b4:q'));
      expect(digitsOf(layout).single.text, '7');
      expect(layout.primitives.whereType<GlyphPrimitive>(), isEmpty);
    });
  });

  group('duration notation', () {
    test('a half note adds one dash to the right', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:h'));
      final digit = digitsOf(layout).single;
      final dashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.x > digit.position.x);
      expect(dashes, hasLength(1));
    });

    test('a whole note adds three dashes', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:w'));
      final digit = digitsOf(layout).single;
      final dashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.x > digit.position.x);
      expect(dashes, hasLength(3));
    });

    test('a dotted quarter gets an augmentation dot, no underline', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q.'));
      final digit = digitsOf(layout).single;
      final dots = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => g.position.x > digit.position.x);
      expect(dots, hasLength(1));
      expect(underlinesOf(layout), isEmpty);
    });

    test('a dotted half is written with dashes only (jianpu convention)',
        () {
      final layout = jianpuOf(Score.simple(notes: 'c4:h.'));
      final digit = digitsOf(layout).single;
      final dashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.x > digit.position.x);
      expect(dashes, hasLength(2));
      expect(layout.primitives.whereType<GlyphPrimitive>(), isEmpty);
    });
  });

  group('underlines (减时线)', () {
    test('four eighths in 4/4 share one underline', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4',
        timeSignature: TimeSignature.commonTime,
      ));
      expect(underlinesOf(layout), hasLength(1));
      final line = underlinesOf(layout).single;
      final digits = digitsOf(layout);
      expect(line.from.x, lessThan(digits.first.position.x));
      expect(line.to.x, greaterThan(digits.last.position.x));
    });

    test('a lone eighth underlines only itself', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:q d4:e e4:q',
        timeSignature: TimeSignature.commonTime,
      ));
      expect(underlinesOf(layout), hasLength(1));
      final line = underlinesOf(layout).single;
      final d = digitsOf(layout)[1];
      expect(line.from.x, lessThan(d.position.x));
      expect(line.to.x, greaterThan(d.position.x));
      expect(line.to.x - line.from.x, lessThan(1.6));
    });

    test('a quarter note breaks a group across beats', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4:q f4:e g4 a4',
        timeSignature: TimeSignature.commonTime,
      ));
      expect(underlinesOf(layout), hasLength(2));
    });

    test('sixteenths add a second-level line under their own run', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4:s c4:e d4:e',
        timeSignature: TimeSignature.commonTime,
      ));
      final lines = underlinesOf(layout);
      expect(lines, hasLength(2));
      lines.sort((a, b) => a.from.y.compareTo(b.from.y));
      final l1 = lines.first, l2 = lines.last;
      expect(l2.from.y, greaterThan(l1.from.y));
      // The second level covers only the two sixteenths, not the eighths.
      expect(l2.to.x - l2.from.x, lessThan(l1.to.x - l1.from.x));
    });

    test('6/8 groups in threes', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4 g4 a4',
        timeSignature: TimeSignature.sixEight,
      ));
      expect(underlinesOf(layout), hasLength(2));
    });
  });

  group('leading furniture', () {
    test('draws 1=C and the time signature for a metered score', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:q',
        timeSignature: TimeSignature.commonTime,
      ));
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('1=C'));
      expect(texts, contains('4'));
    });

    test('a flat key spells its accidental (1=♭B for two flats)', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:q',
        keySignature: const KeySignature(-2),
      ));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=♭B'),
      );
    });

    test('a mid-score key change re-labels the tonic', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q | !key=1 g4:q'));
      expect(digitsOf(layout).map((d) => d.text), ['1', '1']);
      expect(
        layout.primitives
            .whereType<TextPrimitive>()
            .where((t) => t.text == '1=G'),
        hasLength(1),
      );
    });
  });

  group('barlines', () {
    test('measures are separated and terminated by a final barline', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q | d4:q'));
      expect(layout.measureRegions, hasLength(2));
      final verticals = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x)
          .toList();
      expect(verticals, isNotEmpty);
      // The last barline is thin+thick: two distinct thicknesses at the end
      // (thin/2 + barlineSeparation + thick/2 = 0.73 with the defaults).
      final maxX =
          verticals.map((l) => l.from.x).reduce((a, b) => a > b ? a : b);
      final atEnd =
          verticals.where((l) => maxX - l.from.x < 0.8).toList();
      expect(atEnd.length, greaterThanOrEqualTo(2));
      expect(atEnd.map((l) => l.thickness).toSet(), hasLength(2));
    });

    test('repeats draw heavy barlines with dots', () {
      final layout =
          jianpuOf(Score.simple(notes: '!repeat c4:q d4 !endrepeat'));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.repeatDot),
        hasLength(4), // two dots at each side
      );
    });

    test('a volta draws its number above the measure', () {
      final layout = jianpuOf(Score.simple(notes: '!volta=1 c4:q | d4:q'));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1.'),
      );
    });
  });

  group('spans and marks', () {
    test('a tie draws a curve above the digits', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q~ c4:q'));
      final curves = layout.primitives.whereType<CurvePrimitive>();
      expect(curves, hasLength(1));
      expect(curves.single.start.y, lessThan(1.6));
      expect(curves.single.end.y, lessThan(1.6));
    });

    test('a tie into a different pitch draws nothing', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q~ d4:q'));
      expect(layout.primitives.whereType<CurvePrimitive>(), isEmpty);
    });

    test('a slur spans its notes with one curve above', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q( d4 e4 f4)'));
      final curves = layout.primitives.whereType<CurvePrimitive>();
      expect(curves, hasLength(1));
      final digits = digitsOf(layout);
      expect(curves.single.start.x, lessThan(digits[1].position.x));
      expect(curves.single.end.x, greaterThan(digits[2].position.x));
    });

    test('lyrics sit below the underline level', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4',
        timeSignature: TimeSignature.commonTime,
        lyrics: 'la li',
      ));
      final lyrics = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'la' || t.text == 'li');
      expect(lyrics, hasLength(2));
      for (final lyric in lyrics) {
        expect(lyric.position.y,
            greaterThan(underlinesOf(layout).single.from.y));
      }
    });

    test('a dynamic marking draws above the digits', () {
      final score = Score.simple(notes: 'c4:q d4').copyWith(
        dynamics: const [DynamicMarking('e0', DynamicLevel.f)],
      );
      final layout = jianpuOf(score);
      final f = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'f');
      expect(f, hasLength(1));
      expect(f.single.position.y, lessThan(1.6));
    });

    test('an annotation draws above the digits', () {
      final layout = jianpuOf(
          Score.simple(notes: 'c4:q d4', annotations: 'Allegro *'));
      final a = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'Allegro');
      expect(a, hasLength(1));
      expect(a.single.position.y, lessThan(1.6));
    });

    test('a staccato note draws the articulation glyph', () {
      final layout = jianpuOf(Score.simple(notes: "c4:q'"));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .map((g) => g.smuflName),
        contains(SmuflGlyph.articStaccatoAbove),
      );
    });
  });

  group('layout contract', () {
    test('every digit carries its element id and a hit region', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4'));
      for (final digit in digitsOf(layout)) {
        expect(digit.elementId, isNotNull);
        expect(
          layout.regions.where((r) => r.elementId == digit.elementId),
          isNotEmpty,
        );
      }
    });

    test('ink bounds wrap the content (top may be negative)', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q'));
      expect(layout.width, greaterThan(0));
      expect(layout.height, greaterThan(0));
      expect(layout.top, lessThan(JianpuLayoutEngine.digitBaseline));
    });

    test('layout is deterministic', () {
      final score = Score.simple(
        notes: 'c4:e d4 e4:h. | f4:q~ g4( a4 b4)',
        timeSignature: TimeSignature.commonTime,
        lyrics: 'do re mi fa sol la',
      );
      expect(describe(jianpuOf(score)), describe(jianpuOf(score)));
    });
  });

  group('cross-measure underlines', () {
    /// Vertical barline x positions, sorted left → right.
    List<double> barlineXsOf(ScoreLayout layout) {
      final xs = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x)
          .map((l) => l.from.x)
          .toList()
        ..sort();
      return xs;
    }

    test('eighths across a barline draw connecting underline segments', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      final barX = barlineXsOf(layout).first;
      // Cross-measure segments end/start within 0.3 of the barline
      // (per-measure underlines end further away at lastCol + pad).
      final leftSide = underlinesOf(layout)
          .where((l) => l.to.x < barX && l.to.x > barX - 0.3);
      expect(leftSide, isNotEmpty,
          reason: 'no left-side cross-measure underline');
      final rightSide = underlinesOf(layout)
          .where((l) => l.from.x > barX && l.from.x < barX + 0.3);
      expect(rightSide, isNotEmpty,
          reason: 'no right-side cross-measure underline');
      expect(leftSide.first.from.y, rightSide.first.from.y);
    });

    test('sixteenths across a barline draw two cross-measure levels', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4 | e4:s f4',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      final barX = barlineXsOf(layout).first;
      final ys = underlinesOf(layout)
          .where((l) =>
              (l.to.x < barX && l.to.x > barX - 0.3) ||
              (l.from.x > barX && l.from.x < barX + 0.3))
          .map((l) => l.from.y)
          .toSet();
      expect(ys.length, greaterThanOrEqualTo(2),
          reason: 'expected two underline levels at the barline');
    });

    test('quarters at the boundary draw no cross-measure underline', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:q d4:q | e4:q f4:q',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      expect(underlinesOf(layout), isEmpty);
    });

    test('a rest at the boundary blocks the cross-measure underline', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 r:e | e4:e f4 r:e',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      final barX = barlineXsOf(layout).first;
      final nearBar = underlinesOf(layout).where((l) =>
          (l.to.x < barX && l.to.x > barX - 0.3) ||
          (l.from.x > barX && l.from.x < barX + 0.3));
      expect(nearBar, isEmpty,
          reason: 'a rest at the boundary should not connect');
    });
  });

  group('accidentals', () {
    /// Prefix texts (♯ ♭ ♮ etc.) left of a digit, in x order.
    List<String> prefixesOf(ScoreLayout layout) {
      final prefixes = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.position.y > 2.9 && t.position.y < 3.0)
          .toList()
        ..sort((a, b) => a.position.x.compareTo(b.position.x));
      return prefixes.map((t) => t.text).toList();
    }

    test('sharp drawn for raised pitch in C major', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c#4 c4'));
      expect(prefixesOf(layout), contains('♯'));
    });

    test('natural drawn when returning to key after a sharp', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c#4 c4'));
      expect(prefixesOf(layout), contains('♮'));
    });

    test('flat drawn for lowered pitch', () {
      final layout = jianpuOf(Score.simple(notes: 'd4:q db4 d4'));
      expect(prefixesOf(layout), contains('♭'));
    });

    test('natural drawn when returning to key after a flat', () {
      final layout = jianpuOf(Score.simple(notes: 'd4:q db4 d4'));
      expect(prefixesOf(layout), contains('♮'));
    });

    test('double sharp and double flat prefixes', () {
      final layout = jianpuOf(Score.simple(
          notes: 'c4:q c##4 cn4 dbb4'));
      expect(prefixesOf(layout), contains('♯♯'));
      expect(prefixesOf(layout), contains('♭♭'));
    });

    test('no prefix when pitch matches key and no prior alteration', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4'));
      expect(prefixesOf(layout), isEmpty);
    });
  });

  group('octaves', () {
    /// Octave-dot glyph y-positions for the digit at [digitIndex].
    List<double> dotYsOf(ScoreLayout layout, int digitIndex) {
      final digits = digitsOf(layout);
      if (digitIndex >= digits.length) return [];
      final x = digits[digitIndex].position.x;
      return layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) =>
              g.smuflName == SmuflGlyph.augmentationDot &&
              (g.position.x - x).abs() < 0.3)
          .map((g) => g.position.y)
          .toList()
        ..sort();
    }

    test('c2 has two dots below', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c2:q c4'));
      final dots = dotYsOf(layout, 1);
      expect(dots.length, 2);
      for (final y in dots) {
        expect(y, greaterThan(JianpuLayoutEngine.digitBaseline));
      }
    });

    test('c6 has two dots above', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c6:q c4'));
      final dots = dotYsOf(layout, 1);
      expect(dots.length, 2);
      for (final y in dots) {
        expect(y, lessThan(JianpuLayoutEngine.digitBaseline));
      }
    });

    test('c4 has no octave dots', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q'));
      expect(dotYsOf(layout, 0), isEmpty);
    });
  });

  group('keys', () {
    test('D major tonic label is 1=D', () {
      final layout = jianpuOf(Score.simple(
        keySignature: const KeySignature(2),
        notes: 'd4:q',
        staffType: StaffType.jianpu,
      ));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=D'),
      );
    });

    test('Eb major tonic label is 1=♭E', () {
      final layout = jianpuOf(Score.simple(
        keySignature: const KeySignature(-3),
        notes: 'eb4:q',
        staffType: StaffType.jianpu,
      ));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=♭E'),
      );
    });

    test('F# major tonic label is 1=♯F', () {
      final layout = jianpuOf(Score.simple(
        keySignature: const KeySignature(6),
        notes: 'f#4:q',
        staffType: StaffType.jianpu,
      ));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1=♯F'),
      );
    });

    test('D major scale renders as 1 2 3 4 5 6 7', () {
      final layout = jianpuOf(Score.simple(
        keySignature: const KeySignature(2),
        notes: 'd4:q e4 f#4 g4 a4 b4 c#5 d5',
        staffType: StaffType.jianpu,
      ));
      expect(digitsOf(layout).map((d) => d.text),
          ['1', '2', '3', '4', '5', '6', '7', '1']);
    });
  });
}
