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

ScoreLayout jianpuOf(
  Score score, {
  bool drawKeyLabelText = false,
  bool drawTimeSignature = false,
}) =>
    const JianpuLayoutEngine().layout(
      score,
      settings,
      drawKeyLabelText: drawKeyLabelText,
      drawTimeSignature: drawTimeSignature,
    );

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
      final layout = jianpuOf(
        Score.simple(
          notes: 'g4:q a4 b4',
          keySignature: const KeySignature(1),
        ),
        drawKeyLabelText: true,
      );
      expect(digitsOf(layout).map((d) => d.text), ['1', '2', '3']);
      // 标签拆为 "1=" 与字母两段文本（G 大调主音无升降号字形）。
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('1='));
      expect(texts, contains('G'));
    });

    test('F major: written B natural is a raised 4, B flat a plain 4', () {
      // Bare `b4` inherits the key's B♭ (plain 4); a written B natural
      // needs the explicit `n` and becomes a raised 4 (♯ prefix).
      final layout = jianpuOf(Score.simple(
        notes: 'bn4:q b4:q',
        keySignature: const KeySignature(-1),
      ));
      final glyphs =
          layout.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName);
      expect(glyphs,
          contains(SmuflGlyph.accidentalSharp)); // prefix before the first 4
      expect(digitsOf(layout).map((d) => d.text), ['4', '4']);
    });

    test('an accidental deviating from the key gets a prefix', () {
      final layout = jianpuOf(Score.simple(notes: 'f#4:q'));
      final glyphs =
          layout.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName);
      expect(glyphs, contains(SmuflGlyph.accidentalSharp));
      expect(digitsOf(layout).single.text, '4');
    });

    test('a rest renders as 0', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q r:q d4'));
      expect(digitsOf(layout).map((d) => d.text), ['1', '0', '2']);
    });

    // GB/T 46845-2025 §6.3.7.2 / §6.3.8.6:
    // 二分/全休止符不用增时线，用增加四分休止符个数的办法构成。
    test('half rest expands to two quarter rests (0 0, no dash)', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q r:h d4:q'));
      // A half rest should be two "0" digits, each at quarter-note width.
      final zeros = digitsOf(layout).where((d) => d.text == '0').toList();
      expect(zeros, hasLength(2));
      // No augmentation dash lines for rests — only underlines (beams)
      // and other horizontal lines are allowed.
      final dashLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.y == l.to.y &&
              l.from.y > 2.3 &&
              l.from.y < 2.6) // dash y ≈ 2.45
          .toList();
      expect(dashLines, isEmpty,
          reason: 'Rests must not have augmentation dashes');
    });

    test('whole rest expands to four quarter rests (0 0 0 0)', () {
      final layout = jianpuOf(Score.simple(
        notes: 'r:w',
        timeSignature: const TimeSignature(4, 4),
      ));
      final zeros = digitsOf(layout).where((d) => d.text == '0').toList();
      expect(zeros, hasLength(4));
    });

    test('dotted half rest expands to three quarter rests (6.3.8.6d)', () {
      final layout = jianpuOf(Score.simple(
        notes: 'r:h.',
        timeSignature: const TimeSignature(3, 4),
      ));
      final zeros = digitsOf(layout).where((d) => d.text == '0').toList();
      expect(zeros, hasLength(3));
    });

    test('dotted whole rest expands to six quarter rests (6.3.8.6e)', () {
      final layout = jianpuOf(Score.simple(
        notes: 'r:w.',
        timeSignature: const TimeSignature(6, 4),
      ));
      final zeros = digitsOf(layout).where((d) => d.text == '0').toList();
      expect(zeros, hasLength(6));
    });

    test('eighth rest still uses a single 0 with underline', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q r:e d4:q'));
      final zeros = digitsOf(layout).where((d) => d.text == '0').toList();
      expect(zeros, hasLength(1));
      final underlines = underlinesOf(layout);
      expect(underlines, isNotEmpty,
          reason: 'An eighth rest should have one underline');
    });

    test('a chord stacks its degree digits vertically, high to low', () {
      final layout = jianpuOf(Score.simple(notes: 'c4+e4+g4:q'));
      // 和弦数字不在基线上（栈以数字行中线为中心），按元素 id 收集。
      final id = layout.regions.single.elementId;
      final digits = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.elementId == id && t.text.length == 1)
          .toList()
        ..sort((a, b) => a.position.y.compareTo(b.position.y));
      expect(digits.map((d) => d.text), ['5', '3', '1'],
          reason: '高音在上，自上而下读作 531');
      // 同一格位：各数字共享同一中心 x。
      for (final d in digits) {
        expect(d.position.x, closeTo(digits.first.position.x, 1e-9));
      }
      // 字号略小于主体数字。
      for (final d in digits) {
        expect(d.size, lessThan(2.0));
      }
      // 栈以数字行中线为中心。
      final topInk = digits.first.position.y - 0.68 * digits.first.size;
      final bottomInk = digits.last.position.y;
      expect((topInk + bottomInk) / 2, closeTo(2.32, 0.01));
      // 整行墨高随之上长。
      expect(layout.height, greaterThan(4.0));
    });

    test('a chord underline drops below the stack, not through it', () {
      final layout = jianpuOf(Score.simple(notes: 'c4+e4+g4:e'));
      final id = layout.regions.single.elementId;
      final digits = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.elementId == id && t.text.length == 1)
          .toList();
      final stackBottom =
          digits.map((d) => d.position.y).reduce((a, b) => a > b ? a : b);
      final underline = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.y > 3.0)
          .toList();
      expect(underline, hasLength(1));
      expect(underline.single.from.y, greaterThan(stackBottom),
          reason: '减时线在栈底之下，不穿过和弦');
    });

    test('a chord with octave dots dots the outer members only', () {
      final layout = jianpuOf(Score.simple(notes: 'c3+e4+g5:h'));
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'augmentationDot')
          .toList();
      // c3 → 低八度点一个（栈底之下）；g5 → 高八度点一个（栈顶之上）；
      // 内层 e4 无点。
      expect(dots, hasLength(2));
      final ys = dots.map((d) => d.position.y).toList()
        ..sort();
      expect(ys.first, lessThan(1.0), reason: '高八度点在栈顶之上');
      expect(ys.last, greaterThan(4.0), reason: '低八度点在栈底之下');
    });

    test('a chord accidental prefix aligns with its own member digit', () {
      // C 大调 c4+eb4+g4：只有 ♭3 偏离调号，前缀居中于中间那个数字。
      final layout = jianpuOf(Score.simple(notes: 'c4+eb4+g4:q'));
      final id = layout.regions.single.elementId;
      final digits = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.elementId == id && t.text.length == 1)
          .toList()
        ..sort((a, b) => a.position.y.compareTo(b.position.y));
      expect(digits.map((d) => d.text), ['5', '3', '1']);
      final flats = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.accidentalFlat)
          .toList();
      expect(flats, hasLength(1), reason: '只有 ♭3 一个前缀');
      // 前缀墨迹垂直中心（_glyphInkRightCenterAt：origin.y 减回半高）。
      final box = metadata.bBoxOf(SmuflGlyph.accidentalFlat);
      final inkCenterY =
          flats.single.position.y - (box.swY + box.neY) / 2 * 0.5;
      final midDigitCenterY =
          digits[1].position.y - 0.68 * digits[1].size / 2;
      expect(inkCenterY, closeTo(midDigitCenterY, 1e-9),
          reason: '前缀与 ♭3 数字同高，而不是整栈居中');
      // 前缀在数字左侧。
      final inkRightX = flats.single.position.x + box.neX * 0.5;
      expect(inkRightX, lessThan(digits[1].position.x));
    });

    test('an ornament above a chord clears the stack top', () {
      final layout = jianpuOf(Score.simple(notes: 'c4+e4+g4:q%'));
      final id = layout.regions.single.elementId;
      final digits = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.elementId == id && t.text.length == 1)
          .toList()
        ..sort((a, b) => a.position.y.compareTo(b.position.y));
      final stackTopInk = digits.first.position.y - 0.68 * digits.first.size;
      final ornaments = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'ornamentTrill')
          .toList();
      expect(ornaments, hasLength(1));
      // 墨迹底边 = origin.y − swY×0.5（装饰音以 _articScale=0.5 缩放）。
      final box = metadata.bBoxOf('ornamentTrill');
      final inkBottom = ornaments.single.position.y - box.swY * 0.5;
      expect(inkBottom, lessThan(stackTopInk),
          reason: '颤音在栈顶之上，不压最高音数字');
    });

    test('technique mark suffixes parse onto the note (滑揉拨花厉换吐)', () {
      NoteElement noteOf(String token) => Score.simple(notes: token)
          .measures
          .single
          .voices
          .single
          .single as NoteElement;
      expect(noteOf('c4:q/').techniques, {TechniqueMark.slideUp});
      expect(noteOf(r'c4:q\').techniques, {TechniqueMark.slideDown});
      expect(noteOf('c4:qH').techniques, {TechniqueMark.slideReturn});
      expect(noteOf('c4:qR').techniques, {TechniqueMark.vibrato});
      expect(noteOf('c4:qP').techniques, {TechniqueMark.pizzicato});
      expect(noteOf('c4:q*').techniques, {TechniqueMark.flutterTongue});
      expect(noteOf('c4:qL').techniques, {TechniqueMark.sharpTongue});
      expect(noteOf('c4:qV').techniques, {TechniqueMark.breath});
      expect(noteOf('c4:qT').techniques, {TechniqueMark.tonguing});
      // 可组合、顺序无关。
      expect(noteOf('c4:q/T').techniques,
          {TechniqueMark.slideUp, TechniqueMark.tonguing});
      expect(noteOf('c4:qT/').techniques,
          {TechniqueMark.slideUp, TechniqueMark.tonguing});
      expect(() => Score.simple(notes: 'r:qT'), throwsFormatException,
          reason: '休止符不能带技法记号');
    });

    test('technique marks render above the digit', () {
      for (final (suffix, want) in [
        ('/', 'glyph:brassScoop'),
        (r'\', 'glyph:brassFallLipShort'),
        ('R', 'glyph:wiggleVibratoWide'),
        ('P', 'text:拨'),
        ('*', 'text:※'),
        ('L', 'text:⊥'),
        ('V', 'text:∨'),
        ('T', 'text:T'),
      ]) {
        final layout = jianpuOf(Score.simple(notes: 'c4:q$suffix d4'));
        final digit = digitsOf(layout).first;
        final (kind, name) = (want.split(':')[0], want.split(':')[1]);
        if (kind == 'glyph') {
          final glyphs = layout.primitives
              .whereType<GlyphPrimitive>()
              .where((g) => g.smuflName == name)
              .toList();
          expect(glyphs, hasLength(1), reason: '$suffix 应渲染为 $name');
          expect(glyphs.single.position.y, lessThan(1.6),
              reason: '$name 在数字上方');
        } else {
          final texts = layout.primitives
              .whereType<TextPrimitive>()
              .where((t) => t.text == name)
              .toList();
          expect(texts, hasLength(1), reason: '$suffix 应渲染为 $name');
          expect(texts.single.position.x, closeTo(digit.position.x, 1e-9),
              reason: '$name 居中于数字');
          expect(texts.single.position.y, lessThan(JianpuLayoutEngine.digitTop),
              reason: '$name 在数字墨盒顶之上');
        }
      }
    });

    test('回滑音 combines scoop and fall, centred as a pair', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:qH d4'));
      final digit = digitsOf(layout).first;
      final pair = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) =>
              g.smuflName == SmuflGlyph.brassScoop ||
              g.smuflName == SmuflGlyph.brassFallLipShort)
          .toList();
      expect(pair, hasLength(2), reason: '回滑音 = 上滑 + 下滑并排');
      // 组合墨迹区间的中心对齐数字中心。
      final scoop = pair.firstWhere((g) => g.smuflName == SmuflGlyph.brassScoop);
      final fall =
          pair.firstWhere((g) => g.smuflName == SmuflGlyph.brassFallLipShort);
      final sBox = metadata.bBoxOf(SmuflGlyph.brassScoop);
      final fBox = metadata.bBoxOf(SmuflGlyph.brassFallLipShort);
      const scale = 0.5;
      final left = scoop.position.x + sBox.swX * scale;
      final right = fall.position.x + fBox.neX * scale;
      expect((left + right) / 2, closeTo(digit.position.x, 1e-9));
    });

    test('a slide stacks below articulations, techniques above ornaments', () {
      // 层叠次序（GB 7.11.7）：装饰滑音最贴近数字，技法记号在装饰音之上。
      final layout = jianpuOf(Score.simple(notes: "c4:q/'%T"));
      double inkBottomOf(String glyph) {
        final g = layout.primitives
            .whereType<GlyphPrimitive>()
            .singleWhere((g) => g.smuflName == glyph);
        return g.position.y - metadata.bBoxOf(glyph).swY * g.scale;
      }

      final slideBottom = inkBottomOf(SmuflGlyph.brassScoop);
      final staccato = layout.primitives
          .whereType<TextPrimitive>()
          .singleWhere((t) => t.text == '▼');
      final trillBottom = inkBottomOf('ornamentTrill');
      final tonguing = layout.primitives
          .whereType<TextPrimitive>()
          .singleWhere((t) => t.text == 'T');
      // y 轴向下：越靠上的记号 y 越小。
      expect(staccato.position.y, lessThan(slideBottom),
          reason: '断音在滑音之上');
      expect(trillBottom, lessThan(staccato.position.y - 0.7),
          reason: '颤音在断音之上');
      expect(tonguing.position.y, lessThan(trillBottom),
          reason: '吐音在装饰音之上');
    });

    test('an ornament glyph sits above the digit (trill/mordent/turn)', () {
      for (final (mark, glyph) in [
        ('%', 'ornamentTrill'),
        (r'$', 'ornamentShortTrill'),
        ('&', 'ornamentMordent'),
        ('?', 'ornamentTurn'),
      ]) {
        final layout = jianpuOf(Score.simple(notes: 'c4:q$mark d4'));
        final ornaments = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == glyph)
            .toList();
        expect(ornaments, hasLength(1), reason: '$mark 应渲染为 $glyph');
        final digit = digitsOf(layout).first;
        // GlyphPrimitive 的 position 是字形原点，不是墨迹中心；按 SMuFL
        // bbox（装饰音以 _articScale=0.5 缩放）折算墨迹中心再比较。
        final box = metadata.bBoxOf(glyph);
        final inkCenterX =
            ornaments.single.position.x + (box.swX + box.width / 2) * 0.5;
        expect((inkCenterX - digit.position.x).abs(), lessThan(0.05),
            reason: '装饰音墨迹居中于数字');
        expect(ornaments.single.position.y, lessThan(1.55),
            reason: '装饰音在数字上方（字形原点，墨迹底边在数字顶之上）');
      }
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

    test('every degree in a lower octave dots, not just the tonic', () {
      // c3 is an exact multiple of the octave span; d3..b3 must dot too
      // (floor division, not truncating ~/).
      final layout = jianpuOf(Score.simple(notes: 'c3:q d3 e3 f3 g3 a3 b3'));
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.position.y > 3.0)
          .toList();
      expect(dots, hasLength(7));
    });

    test('every degree in an upper octave dots, not just the tonic', () {
      final layout = jianpuOf(Score.simple(notes: 'c5:q d5 e5 f5 g5 a5 b5'));
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.position.y < 1.6)
          .toList();
      expect(dots, hasLength(7));
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

    test('system wrapping keeps 增时线 clear of the next digit', () {
      // 换行/系统排布走 alignedColumns 强制列位：列宽必须容纳简谱自己的
      // 增时线墨迹（此前列宽按五线谱符头墨水计算，增时线会压到下一个
      // 数字的墨盒）。
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
        notes: 'c4:h d4:h | e4:w | f4:q g4 a4 b4 | c5:h. d4:q |',
      );
      final wrapped = layoutStaffSystemSystems(StaffSystem([score]), settings,
          maxWidth: 60, layoutMode: SystemLayoutMode.wrapped);
      for (final sys in wrapped.systems) {
        final layout = sys.layout.staves.single;
        // 数字墨盒：中心 ±0.45（_digitInkHalf）。
        final digitBoxes = {
          for (final t in layout.primitives.whereType<TextPrimitive>().where(
              (t) =>
                  t.elementId != null &&
                  t.text.length == 1 &&
                  t.position.y == JianpuLayoutEngine.digitBaseline))
            t.elementId!: (t.position.x - 0.45, t.position.x + 0.45)
        };
        final dashes = layout.primitives.whereType<LinePrimitive>().where(
            (l) =>
                l.from.y == l.to.y &&
                (l.from.y - 2.32).abs() < 0.01 &&
                l.elementId != null);
        for (final dash in dashes) {
          for (final entry in digitBoxes.entries) {
            if (entry.key == dash.elementId) continue;
            final (left, right) = entry.value;
            expect(
                dash.to.x <= left || dash.from.x >= right, isTrue,
                reason: '增时线 ${dash.from.x}..${dash.to.x} 压到了'
                    ' ${entry.key} 的数字墨盒 $left..$right');
          }
        }
      }
    });
  });

  group('underlines (减时线)', () {
    test('four eighths in 4/4 split into two per-beat underlines', () {
      // 简谱：每拍独立一条减时线，不做跨半小节合并
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4',
        timeSignature: TimeSignature.commonTime,
      ));
      expect(underlinesOf(layout), hasLength(2));
      final lines = underlinesOf(layout);
      final digits = digitsOf(layout);
      // 第一条覆盖前两个 digit (c4,d4)，第二条覆盖后两个 (e4,f4)
      lines.sort((a, b) => a.from.x.compareTo(b.from.x));
      expect(lines.first.from.x, lessThan(digits.first.position.x));
      expect(lines.first.to.x,
          greaterThan(digits[1].position.x)); // 到第二个digit之后
      expect(lines.last.to.x, greaterThan(digits.last.position.x));
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
      // c4:d4(拍1: 两个8分), e4:q(拍2: 四分无减时线),
      // f4(拍3: 单独8分), g4+a4(拍4: 两个8分)
      // 简谱按拍独立 → 3 条
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4:q f4:e g4 a4',
        timeSignature: TimeSignature.commonTime,
      ));
      expect(underlinesOf(layout), hasLength(3));
    });

    test('sixteenths add a second-level line under their own run', () {
      // c4:s d4:s c4:e d4:e — 拍1两个16分(2条线), 拍2一个8分, 拍3一个8分
      // 实际 3 条：拍1的一级+二级，拍2+拍3各一条一级
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4:s c4:e d4:e',
        timeSignature: TimeSignature.commonTime,
      ));
      final lines = underlinesOf(layout);
      expect(lines, hasLength(3));
      // 二级线 (y=3.58) 比一级线 (y=3.23) 更靠下
      lines.sort((a, b) => a.from.y.compareTo(b.from.y));
      expect(lines.last.from.y, greaterThan(lines.first.from.y));
      // 二级线只覆盖前两个十六分，比一级线短
      final secondLevel = lines.last;
      final firstLevel = lines.first;
      expect(secondLevel.to.x - secondLevel.from.x,
          lessThan(firstLevel.to.x - firstLevel.from.x));
    });

    test('6/8 groups in threes', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4 g4 a4',
        timeSignature: TimeSignature.sixEight,
      ));
      // 6/8：每 3 个八分合成一组（一个复合拍），共 2 组
      expect(underlinesOf(layout), hasLength(2));
    });

    // GB/T 46845-2025 §6.3.5.3: 3/8 拍等以八分音符为一拍的三拍子，
    // 三拍的减时线连写（三个八分音符合用一条减时线）。
    test('3/8 connects all three eighths with one underline (6.3.5.3)', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4',
        timeSignature: TimeSignature(3, 8),
      ));
      // 3/8：三个八分音符连写为一条减时线
      expect(underlinesOf(layout), hasLength(1));
    });

    test('underline extends past the trailing augmentation dot', () {
      // c4:s d4:e. — 一级减时线覆盖整拍，右端必须盖住附点的墨迹
      // （附点是时值的一部分）。附点墨迹右缘 = 原点 x + 0.2。
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4:e.',
        timeSignature: TimeSignature.commonTime,
      ));
      final dot = layout.primitives
          .whereType<GlyphPrimitive>()
          .singleWhere((g) => g.smuflName.contains('augmentationDot'));
      final level1 = underlinesOf(layout)
          .reduce((a, b) => a.to.x > b.to.x ? a : b); // longest = level 1
      expect(level1.to.x, greaterThanOrEqualTo(dot.position.x + 0.2 - 1e-9));
    });

    test('underline covers both dots of a trailing double-dotted eighth',
        () {
      // 复附点八分音符在拍尾：减时线必须越过第二个附点的墨迹右缘。
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4:e..',
        timeSignature: TimeSignature.commonTime,
      ));
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.contains('augmentationDot'))
          .toList();
      expect(dots, hasLength(2));
      final lastDot =
          dots.reduce((a, b) => a.position.x > b.position.x ? a : b);
      final level1 = underlinesOf(layout)
          .reduce((a, b) => a.to.x > b.to.x ? a : b);
      expect(level1.to.x,
          greaterThanOrEqualTo(lastDot.position.x + 0.2 - 1e-9));
    });
  });

  group('leading furniture', () {
    test('draws 1=C and the time signature for a metered score', () {
      final layout = jianpuOf(
        Score.simple(
          notes: 'c4:q',
          timeSignature: TimeSignature.commonTime,
        ),
        drawKeyLabelText: true,
        drawTimeSignature: true,
      );
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      // 标签拆为 "1=" 与字母两段文本（升降号是 SMuFL 字形）。
      expect(texts, contains('1='));
      expect(texts, contains('C'));
      expect(texts, contains('4'));
    });

    test('a flat key spells its accidental (1=♭B for two flats)', () {
      final layout = jianpuOf(
        Score.simple(
          notes: 'c4:q',
          keySignature: const KeySignature(-2),
        ),
        drawKeyLabelText: true,
      );
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('1='));
      expect(texts, contains('B'));
      expect(
        layout.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName),
        contains(SmuflGlyph.accidentalFlat),
      );
    });

    test('a mid-score key change re-labels the tonic', () {
      final layout = jianpuOf(
        Score.simple(notes: 'c4:q | !key=1 g4:q'),
        drawKeyLabelText: true,
      );
      expect(digitsOf(layout).map((d) => d.text), ['1', '1']);
      final texts = layout.primitives
          .whereType<TextPrimitive>()
          .map((t) => t.text)
          .toList();
      // 行首 1=C 与变调处 1=G 各一次。
      expect(texts.where((t) => t == '1='), hasLength(2));
      expect(texts.where((t) => t == 'C'), hasLength(1));
      expect(texts.where((t) => t == 'G'), hasLength(1));
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
          jianpuOf(Score.simple(notes: 'c4:q | !repeat d4:q !endrepeat'));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.repeatDot),
        hasLength(4), // two dots at each side
      );
    });

    // GB/T 46845-2025 §5.8.2.2b: 作品开端的前段落反复号省略。
    test('opening start repeat is omitted (5.8.2.2b)', () {
      final layout =
          jianpuOf(Score.simple(notes: '!repeat c4:q d4 !endrepeat'));
      // Only the end-repeat dots (2) should be present; the start-repeat
      // dots at the piece opening are omitted per the spec.
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.repeatDot)
          .toList();
      expect(dots, hasLength(2));
    });

    // GB/T 46845-2025 §5.8.2.2c: 前后紧邻的两个反复段落，其前一段落的
    // 后反复号与后一段落的前反复号，合并为一个符号，两者的粗纵线合用一条。
    test('adjacent endRepeat + startRepeat share one thick line (5.8.2.2c)',
        () {
      final layout = jianpuOf(
          Score.simple(notes: 'c4:q !endrepeat | !repeat d4:q e4:q'));
      // Combined repeat symbol should have 4 dots (2 left + 2 right) ...
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.repeatDot)
          .toList();
      expect(dots, hasLength(4));

      // ... but only ONE thick vertical line (shared), not two separate ones.
      // A separate end-repeat + start-repeat would have 2 thick lines.
      final thickLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x) // vertical
          .where((l) => l.thickness > 0.3) // thick (0.5) vs thin (0.12)
          .toList();
      // There should be 1 thick line from the combined repeat + 1 from the
      // final barline = 2 total.
      // (Before the fix, we'd have 3: end-repeat thick + start-repeat thick
      // + final-bar thick.)
      expect(thickLines, hasLength(2),
          reason: 'Combined repeat shares one thick line; final bar adds one');
    });

    test('a volta draws its number above the measure', () {
      final layout = jianpuOf(Score.simple(notes: '!volta=1 c4:q | d4:q'));
      expect(
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
        contains('1.'),
      );
    });

    // GB/T 46845-2025 §5.11.4: 跳房子记号右端有下垂竖线。
    test('volta has a downward vertical line at the right end (5.11.4)', () {
      final layout = jianpuOf(Score.simple(notes: '!volta=1 c4:q | d4:q'));
      final voltaLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness > 0.1 && l.thickness < 0.18)
          .where((l) =>
              l.from.y < 1.0 && l.to.y < 1.0) // volta is above the staff
          .toList();
      // Should have: 1 horizontal + 2 vertical (left + right) = 3 lines
      final horizontal =
          voltaLines.where((l) => l.from.y == l.to.y).toList();
      final vertical =
          voltaLines.where((l) => l.from.x == l.to.x).toList();
      expect(horizontal, hasLength(1), reason: 'one horizontal volta line');
      expect(vertical, hasLength(2),
          reason: 'two vertical volta lines (left + right)');

      // The right vertical should be at or near barX (the measure's right edge).
      final rightVertical =
          vertical.reduce((a, b) => a.from.x > b.from.x ? a : b);
      final horiz = horizontal.single;
      expect(rightVertical.from.x,
          closeTo(horiz.to.x, 0.2)); // right end of horizontal
    });

    // GB/T 46845-2025 §5.2.2: 虚小节线是垂直细虚线。
    test('a dashed barline draws short vertical segments (5.2.2)', () {
      final layout = jianpuOf(
          Score.simple(notes: 'c4:q d4 !barline=dashed e4:q f4'));
      final verticals = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x)
          .toList();
      // Group verticals by x: the dashed barline is the one x position
      // holding several short segments (the connector and normal barlines
      // hold a single full-height line each).
      final byX = <int, List<LinePrimitive>>{};
      for (final l in verticals) {
        byX.putIfAbsent((l.from.x * 100).round(), () => []).add(l);
      }
      final dashed =
          byX.entries.where((e) => e.value.length >= 3).toList();
      expect(dashed, hasLength(1),
          reason: 'one x position holds the dashed barline segments');
      final segments = dashed.single.value;
      for (final s in segments) {
        expect((s.to.y - s.from.y).abs(), lessThan(1.0),
            reason: 'each dash is a short segment, not a full line');
      }
      // Collectively the dashes span the barline range (the +1 octave-dot
      // centre down to the first 减时线 — slightly beyond the digit ink
      // box); the dash tiling starts flush at the top and lands within one
      // dash length of the bottom.
      final top = segments
          .map((s) => s.from.y)
          .reduce((a, b) => a < b ? a : b);
      final bottom =
          segments.map((s) => s.to.y).reduce((a, b) => a > b ? a : b);
      expect(top, JianpuLayoutEngine.barlineTop);
      expect(bottom,
          greaterThan(JianpuLayoutEngine.barlineBottom - 0.33));
    });

    // 简谱小节线只收小节末尾：行首（第一个小节开头）不画任何纵线。
    test('no barline opens the row at the left end', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4'));
      final leading = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x)
          .where((l) => l.from.x < settings.leadingPadding)
          .toList();
      expect(leading, isEmpty,
          reason: '行首不画连谱线/小节线');
      // The measure content is not shifted: it still starts at the leading
      // padding.
      expect(layout.measureRegions.single.startX,
          closeTo(settings.leadingPadding, 1e-9));
    });

    test('barlines span the +1 octave-dot centre to the first underline', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q d4 e4'));
      final bars = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x)
          .toList();
      expect(bars, isNotEmpty);
      for (final bar in bars) {
        expect(bar.from.y, JianpuLayoutEngine.barlineTop);
        expect(bar.to.y, JianpuLayoutEngine.barlineBottom);
      }
      // 比数字墨盒（digitTop…digitBaseline）略高。
      expect(JianpuLayoutEngine.barlineTop,
          lessThan(JianpuLayoutEngine.digitTop));
      expect(JianpuLayoutEngine.barlineBottom,
          greaterThan(JianpuLayoutEngine.digitBaseline));
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

    test('a triplet draws an open bracket with the ratio digit above', () {
      final layout =
          jianpuOf(Score.simple(notes: '3[c4:e d4 e4] f4:e c4:q'));
      // 括线：两条横线（中央断开）+ 两个端钩，共 4 条线段在 _tupletY 一带。
      final horizontals = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.y < 1.0)
          .toList();
      expect(horizontals, hasLength(2),
          reason: '连音符括线中央为数字断开');
      final hooks = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.x == l.to.x &&
              l.from.y < 1.0 &&
              l.to.y > l.from.y)
          .toList();
      expect(hooks, hasLength(2), reason: '括线两端各有一个下折短钩');
      // 比例数字 "3" 写在断口中央，位于数字行上方（排除音级数字 3：
      // 它在数字基线上）。
      final mark = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) =>
              t.text == '3' &&
              t.position.y != JianpuLayoutEngine.digitBaseline)
          .toList();
      expect(mark, hasLength(1));
      final digits = digitsOf(layout);
      final midX = (horizontals.first.from.x + horizontals.last.to.x) / 2;
      expect(mark.single.position.x, closeTo(midX, 0.2));
      expect(mark.single.position.y, lessThan(JianpuLayoutEngine.digitTop));
      // 括线覆盖三连音的三个数字，不外延到后续的八分/四分音符。
      expect(horizontals.first.from.x, lessThan(digits[0].position.x));
      expect(horizontals.last.to.x, greaterThan(digits[2].position.x));
      expect(horizontals.last.to.x, lessThan(digits[3].position.x));
    });

    test('a tuplet covering a rest still spans its full extent', () {
      final layout = jianpuOf(Score.simple(notes: '3[c4:e r e4]'));
      final horizontals = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y == l.to.y && l.from.y < 1.0)
          .toList();
      expect(horizontals, hasLength(2));
      final digits = digitsOf(layout); // 1 0 1
      expect(digits, hasLength(3));
      expect(horizontals.last.to.x, greaterThan(digits[2].position.x));
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

    // GB/T 46845-2025 §6.7.3: 力度记号的位置：器乐谱记在乐谱下方，
    // 声乐谱记在乐谱上方。
    test('instrumental score: dynamics go below the staff (6.7.3)', () {
      final score = Score.simple(notes: 'c4:q d4').copyWith(
        dynamics: const [DynamicMarking('e0', DynamicLevel.f)],
      );
      final layout = jianpuOf(score);
      final f = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'f');
      expect(f, hasLength(1));
      // Staff bottom is at ~4.0; dynamics sit below it.
      expect(f.single.position.y, greaterThan(4.0));
    });

    test('vocal score (with lyrics): dynamics go above the staff (6.7.3)',
        () {
      final score = Score.simple(
        notes: 'c4:q d4',
        lyrics: 'do re',
      ).copyWith(
        dynamics: const [DynamicMarking('e0', DynamicLevel.f)],
      );
      final layout = jianpuOf(score);
      final f = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'f');
      expect(f, hasLength(1));
      // Staff top is at ~1.0; dynamics sit above it.
      expect(f.single.position.y, lessThan(1.0));
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

    // GB/T 46845-2025 §6.5.3.1: 断音记号用实心倒三角 ▼ 记在音符上方。
    test('staccato uses solid inverted triangle ▼ above the note (6.5.3.1)',
        () {
      final layout = jianpuOf(Score.simple(notes: "c4:q'"));
      // Staccato in jianpu is a downward-pointing solid triangle (▼),
      // rendered as a TextPrimitive — not the Western dot glyph.
      final staccatoMarks = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == '▼')
          .toList();
      expect(staccatoMarks, hasLength(1));
      // The triangle sits above the digit (y < digit top at ~1.4).
      expect(staccatoMarks.single.position.y, lessThan(1.6));
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

  group('barline boundaries', () {
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

    test('underlines never touch the barline (减时线不跨小节线)', () {
      // 标准简谱：减时线只在小节内按拍分组，不延伸到小节线。
      // e4 f4 | g4 a4 这 4 个八分音符必须保持两根独立的 beam。
      final layout = jianpuOf(Score.simple(
        notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      final barX = barlineXsOf(layout).first;
      for (final line in underlinesOf(layout)) {
        expect((line.to.x - barX).abs(), greaterThan(0.3),
            reason: 'underline reaches the barline at $barX: $line');
        expect((line.from.x - barX).abs(), greaterThan(0.3),
            reason: 'underline starts at the barline at $barX: $line');
        expect(line.from.x < barX && line.to.x > barX, isFalse,
            reason: 'underline crosses the barline: $line');
      }
      // 每小节两个拍组，共 4 条一级减时线
      expect(underlinesOf(layout), hasLength(4));
    });

    test('sixteenths at a barline stay inside their own measure', () {
      final layout = jianpuOf(Score.simple(
        notes: 'c4:s d4 | e4:s f4',
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
      ));
      final barX = barlineXsOf(layout).first;
      final nearBar = underlinesOf(layout).where((l) =>
          (l.to.x - barX).abs() < 0.3 || (l.from.x - barX).abs() < 0.3);
      expect(nearBar, isEmpty,
          reason: 'no underline level may reach the barline');
    });
  });

  group('accidentals', () {
    /// Accidental prefix glyphs (SMuFL) left of the digits, in x order.
    /// 变音记号一律用 SMuFL 字形（accidental*），不再用 Unicode 文本——
    /// 文本字体不保证有 ♯♭♮ 字符，导出图片会丢。
    List<String> prefixesOf(ScoreLayout layout) {
      final prefixes = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('accidental'))
          .toList()
        ..sort((a, b) => a.position.x.compareTo(b.position.x));
      return prefixes.map((g) => g.smuflName).toList();
    }

    test('sharp drawn for raised pitch in C major', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c#4 c4'));
      expect(prefixesOf(layout), contains(SmuflGlyph.accidentalSharp));
    });

    test('natural drawn when returning to key after a sharp', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q c#4 c4'));
      expect(prefixesOf(layout), contains(SmuflGlyph.accidentalNatural));
    });

    test('flat drawn for lowered pitch', () {
      final layout = jianpuOf(Score.simple(notes: 'd4:q db4 d4'));
      expect(prefixesOf(layout), contains(SmuflGlyph.accidentalFlat));
    });

    test('natural drawn when returning to key after a flat', () {
      final layout = jianpuOf(Score.simple(notes: 'd4:q db4 d4'));
      expect(prefixesOf(layout), contains(SmuflGlyph.accidentalNatural));
    });

    test('double sharp and double flat prefixes', () {
      final layout = jianpuOf(Score.simple(
          notes: 'c4:q c##4 cn4 dbb4'));
      final prefixes = prefixesOf(layout);
      // 重升画两个独立的 ♯ 字形；重降是专用的 SMuFL 字形。
      expect(prefixes.where((g) => g == SmuflGlyph.accidentalSharp),
          hasLength(2));
      expect(prefixes, contains(SmuflGlyph.accidentalDoubleFlat));
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
    /// The 1=X label is text runs ('1=', letter) plus a SMuFL accidental
    /// glyph when the tonic is sharpened/flattened.
    void expectKeyLabel(ScoreLayout layout, String letter,
        [String? accidentalGlyph]) {
      final texts =
          layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
      expect(texts, contains('1='));
      expect(texts, contains(letter));
      final glyphs = layout.primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName);
      if (accidentalGlyph != null) {
        expect(glyphs, contains(accidentalGlyph));
      }
    }

    test('D major tonic label is 1=D', () {
      final layout = jianpuOf(
        Score.simple(
          keySignature: const KeySignature(2),
          notes: 'd4:q',
          staffType: StaffType.jianpu,
        ),
        drawKeyLabelText: true,
      );
      expectKeyLabel(layout, 'D');
    });

    test('Eb major tonic label is 1=♭E', () {
      final layout = jianpuOf(
        Score.simple(
          keySignature: const KeySignature(-3),
          notes: 'eb4:q',
          staffType: StaffType.jianpu,
        ),
        drawKeyLabelText: true,
      );
      expectKeyLabel(layout, 'E', SmuflGlyph.accidentalFlat);
    });

    test('F# major tonic label is 1=♯F', () {
      final layout = jianpuOf(
        Score.simple(
          keySignature: const KeySignature(6),
          notes: 'f#4:q',
          staffType: StaffType.jianpu,
        ),
        drawKeyLabelText: true,
      );
      expectKeyLabel(layout, 'F', SmuflGlyph.accidentalSharp);
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

  group('box model (盒模型统一度量)', () {
    test('a dash cell equals a quarter-note cell (增时线占一格)', () {
      final half = jianpuOf(Score.simple(notes: 'c4:h'));
      final pair = digitsOf(jianpuOf(Score.simple(notes: 'c4:q d4')));
      final cell = pair[1].position.x - pair[0].position.x;
      final digitX = digitsOf(half).single.position.x;
      final dash = half.primitives.whereType<LinePrimitive>().firstWhere(
          (l) => l.from.y == l.to.y && l.from.x > digitX);
      final dashCenter = (dash.from.x + dash.to.x) / 2;
      expect(dashCenter - digitX, closeTo(cell, 1e-9));
      expect(dash.to.x - dash.from.x, closeTo(1.1, 1e-9), // ≈ 数字墨宽
          reason: 'dash length should match the digit ink width');
      // 二分音符占两格：总宽超过 digitX + 2·cell
      expect(half.width, greaterThan(digitX + 2 * cell));
    });

    test('repeat dots flank the digit box at its quarter heights', () {
      final layout =
          jianpuOf(Score.simple(notes: 'c4:q | !repeat d4:q !endrepeat'));
      final ys = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.repeatDot)
          .map((g) => g.position.y)
          .toSet();
      // 圆点 bBox 以原点为中心：origin y 即墨迹中心
      expect(ys, {1.95, 2.65});
    });

    test('high and low octave dots sit at the same gap from the digit box',
        () {
      final hiY = jianpuOf(Score.simple(notes: 'c5:q'))
          .primitives
          .whereType<GlyphPrimitive>()
          .single
          .position
          .y;
      final loY = jianpuOf(Score.simple(notes: 'c3:q'))
          .primitives
          .whereType<GlyphPrimitive>()
          .single
          .position
          .y;
      final hiGap = JianpuLayoutEngine.digitTop - hiY;
      final loGap = loY - JianpuLayoutEngine.digitBaseline;
      expect(hiGap, closeTo(loGap, 1e-9));
    });

    test('accidental prefix hugs the digit at the universal gap', () {
      final layout = jianpuOf(Score.simple(notes: 'c#4:q'));
      final sharp = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == SmuflGlyph.accidentalSharp);
      // SMuFL 记号缩放 0.5（与数字 em 的比例等同五线谱）。
      expect(sharp.scale, 0.5);
      final digit = digitsOf(layout).single;
      // 记号墨迹右缘与数字墨迹左缘（半宽 0.45）保持统一净距 0.15。
      final inkRight = sharp.position.x +
          metadata.bBoxOf(SmuflGlyph.accidentalSharp).neX * sharp.scale;
      final gap = (digit.position.x - 0.45) - inkRight;
      expect(gap, closeTo(0.15, 1e-9));
    });

    test('an accidental widens its own cell instead of overlapping leftwards',
        () {
      final withAcc = jianpuOf(Score.simple(notes: 'c4:q c#4:q'));
      final without = jianpuOf(Score.simple(notes: 'c4:q c4:q'));
      final accDigits = digitsOf(withAcc);
      final plainDigits = digitsOf(without);
      // 第一个音位置不变；带记号的第二个数字整体右移一个前缀外推量。
      expect(accDigits.first.position.x, plainDigits.first.position.x);
      expect(accDigits[1].position.x - plainDigits[1].position.x,
          greaterThan(0));
      // 记号墨迹左缘不越过本元素的格位起点（即无记号时第二个数字的 x），
      // 因此不会压上前一个元素的右侧。
      final sharp = withAcc.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == SmuflGlyph.accidentalSharp);
      final inkLeft = sharp.position.x +
          metadata.bBoxOf(SmuflGlyph.accidentalSharp).swX * sharp.scale;
      expect(inkLeft,
          greaterThanOrEqualTo(plainDigits[1].position.x - 1e-9));
    });

    test('augmentation dot is bottom-aligned with the digit', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q.'));
      final dot = layout.primitives.whereType<GlyphPrimitive>().single;
      // 点墨迹以原点为中心（±0.20）：底边须落在数字基线上。
      expect(dot.position.y + 0.20,
          closeTo(JianpuLayoutEngine.digitBaseline, 1e-9));
    });

    test(
        'augmentation dots keep the universal gap from the digit and between '
        'themselves', () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q..'));
      final digit = digitsOf(layout).single;
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.augmentationDot)
          .toList()
        ..sort((a, b) => a.position.x.compareTo(b.position.x));
      expect(dots, hasLength(2));
      // swX = 0 → origin x 即墨迹左缘：距数字墨迹右缘一个 _symbolGap
      expect(dots.first.position.x - digit.position.x, closeTo(0.6, 1e-9));
      // 多附点间距 = 点宽 0.4 + 净距 0.15
      expect(dots[1].position.x - dots[0].position.x, closeTo(0.55, 1e-9));
    });

    test('articulations stack above the octave dots, never on them', () {
      final layout = jianpuOf(Score.simple(notes: "c5:q'"));
      final dot = layout.primitives.whereType<GlyphPrimitive>().single;
      final mark = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '▼');
      // 点的墨迹顶 = 中心 − 0.2；三角基线（≈墨迹底）必须在其上方
      expect(mark.position.y, lessThan(dot.position.y - 0.2));
    });

    test('tenuto keeps the universal gap above the digit box, at digit scale',
        () {
      final layout = jianpuOf(Score.simple(notes: 'c4:q_'));
      final tenuto = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == 'articTenutoAbove');
      expect(tenuto.scale, 0.5,
          reason: 'SMuFL marks scale to the digit em (2 ss of 4)');
      // articTenutoAbove 的 swY = 0 → 墨迹底 = origin y = digitTop − 0.15
      expect(tenuto.position.y,
          closeTo(JianpuLayoutEngine.digitTop - 0.15, 1e-9));
    });
  });
}
