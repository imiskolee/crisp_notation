/// Jianpu (numbered musical notation, 简谱) layout: renders a [Score]'s
/// pitches as movable-do digits on a single text row, producing the same
/// [ScoreLayout] primitives as the staff and tab engines, so the Flutter
/// renderer and the interaction layer work unchanged.
///
/// Coordinates (docs/JIANPU.md §4.1), in staff spaces: the digit baseline
/// sits at [digitBaseline] (y = 3.0); barlines span slightly beyond the
/// digit ink box — from the +1 octave-dot centre ([barlineTop]) down to
/// the first 减时线 underline ([barlineBottom]), whether or not those
/// marks are actually present. No staff lines and no line-start barline
/// are drawn: barlines close measures only. Ties, slurs, tuplet brackets,
/// dynamics and annotations go above the digits; octave dots hug the
/// digit; 减时线 (duration underlines) and lyrics sit below.
library;

import 'dart:math';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../smufl/smufl_metadata.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';
import 'beam_grouping.dart';
import 'layout_settings.dart';
import 'score_layout.dart';

/// Estimated half-width of [text] at em [size], in staff spaces. The layout
/// has no text-font metrics. CJK characters are full-width (≈1 em), so we use
/// a per-character estimate of 0.5 em half-width — generous enough to keep
/// Chinese lyrics from colliding on closely-spaced jianpu notes.
double _estTextHalfWidth(String text, double size) =>
    0.5 * size * max(1, text.length);

/// Nudges box [centers] rightward so consecutive boxes keep at least [gap]
/// between them. Lists must be parallel and in left-to-right order.
void _spreadRight(List<double> centers, List<double> halfWidths, double gap) {
  for (var i = 1; i < centers.length; i++) {
    final minCenter = centers[i - 1] + halfWidths[i - 1] + gap + halfWidths[i];
    if (centers[i] < minCenter) centers[i] = minCenter;
  }
}

/// One placed rhythmic column: its digit centre x, written duration and
/// measure onset.
class _Col {
  final double x;
  final NoteDuration duration;
  final Fraction onset;
  final bool isRest;

  /// Ink the underline must cover past the digit's right edge: the
  /// augmentation dots (each dot's ink reaches _dotHalf past its origin,
  /// origins stepping 2·_dotHalf + _symbolGap from the digit's right ink).
  final double dotExt;

  /// Bottom of the column's note ink: the digit baseline for single notes
  /// and rests, the chord stack's bottom baseline for chords. 减时线从本
  /// 列墨迹底（而不是固定的数字基线）向下排，避免穿过和弦栈。
  final double bottom;
  _Col(this.x, this.duration, this.onset,
      {this.isRest = false, this.dotExt = 0, this.bottom = 3.0});
}

/// Lays a [Score] out as jianpu (numbered notation), major keys only (v1).
///
/// The signature mirrors [TabLayoutEngine.layout]: [leadingWidth] and
/// [barlineXs] pin the leading and each measure's barline to absolute x
/// positions so a jianpu staff can align barline-for-barline with a paired
/// staff of another notation (honoured when passed; the system-level mixed
/// routing is v2). [tonicOctave] fixes which octave of the tonic is the
/// undotted reference (default 4 — the middle register).
class JianpuLayoutEngine {
  /// Creates a jianpu layout engine.
  const JianpuLayoutEngine();

  /// Baseline y of the digit row, in staff spaces.
  static const double digitBaseline = 3.0;

  /// Em size of a degree digit, in staff spaces.
  static const double digitSize = 2.0;

  // ---- 盒模型度量 -------------------------------------------------------
  // 所有记号的位置都由"数字墨盒 + 统一间隙"推出，不再各自硬编码坐标：
  // 数字 baseline 在 3.0，墨盒顶在 [digitTop]（cap height 按 0.68 em
  // 估计，核心库不测量文字），墨迹半宽 [_digitInkHalf]。记号与数字、
  // 记号与记号之间统一保持 [_symbolGap] 净距；层叠类记号（八度点、
  // 音符记号）共用同一条向上/向下游标，依次堆叠。
  /// Ink top of a degree digit (cap height ≈ 0.68 em above the baseline).
  static const double digitTop = 1.64;

  /// Half the typical ink width of a degree digit.
  static const double _digitInkHalf = 0.45;

  /// Vertical centre of the digit ink box — the 增时线 height.
  static const double _digitMid = 2.32; // (digitTop + digitBaseline) / 2

  /// Universal gap between the digit ink box and any accessory symbol
  /// (octave dots, underlines, augmentation dots, articulations).
  static const double _symbolGap = 0.15;

  /// Unified dot metric: SMuFL augmentationDot and repeatDot share the
  /// same ±0.2 bBox (the dot ink is centred on the glyph origin).
  static const double _dotHalf = 0.20;

  /// Stacked-octave-dot pitch: 2·_dotHalf + 0.05 层叠净距.
  static const double _dotStep = 0.45;

  /// Half the underline thickness (0.16 ÷ 2).
  static const double _lineHalf = 0.08;

  /// First 减时线 underline: digitBaseline + _symbolGap + _lineHalf = 3.23.
  static const double _underlineY = 3.23;
  static const double _underlineStep = 0.35;
  static const double _underlinePad = 0.45;

  // 小节线比数字墨盒略高：上抵 +1 高八度点的点心（digitTop − _symbolGap
  // − _dotHalf = 1.29），下抵第一条减时线（_underlineY = 3.23）——无论
  // 相邻音符是否真带高八度点/减时线，都按这两个名义位置对齐。
  /// Top of a jianpu barline: the +1 octave dot's centre (y = 1.29).
  static const double barlineTop = digitTop - _symbolGap - _dotHalf;

  /// Bottom of a jianpu barline: the first 减时线 underline (y = 3.23).
  static const double barlineBottom = _underlineY;

  /// 连音符括线的高度：在延音线弧顶（0.75）之上、曲中力度/表情记号
  /// （baseline 0.5）之下，避开两者的墨迹带。
  static const double _tupletY = 0.62;

  /// 连音符括线端钩向数字方向的下折长度。
  static const double _tupletHook = 0.45;

  /// 连音符比例数字的字号（em，staff spaces）——小于主体数字（2.0）。
  static const double _tupletDigitSize = 1.15;

  /// 增时线长度 ≈ 一个数字的墨迹宽度；每条增时线占一个四分音符格位。
  static const double _dashLength = 1.1;

  /// Scale for SMuFL articulation marks: SMuFL's design em is 4 staff
  /// spaces while the digit em is 2, so 0.5 keeps the mark-to-digit
  /// proportion identical to the mark-to-notehead proportion on a staff.
  static const double _articScale = 0.5;

  /// Scale for SMuFL accidental prefixes — same proportion as
  /// [_articScale]; at 0.5 the ♯/♮ ink is ≈1.4 ss tall, level with the
  /// digit cap height (1.36).
  static const double _accidentalScale = 0.5;

  /// 反复圆点的两个中心：分列数字墨盒的上、下四分之一处，整对与数字同高。
  static const double _repeatDotHigh = 1.95;
  static const double _repeatDotLow = 2.65;

  /// 附点中心高度：附点与数字底对齐——点墨迹底边落在数字基线上
  /// (digitBaseline − _dotHalf = 3.0 − 0.20)。
  static const double _augDotY = 2.80;

  /// 和弦数字的字号系数：和弦各音级数字纵向叠放，字号略小于主体数字。
  static const double _chordDigitFactor = 0.8;

  /// 和弦叠放数字之间的纵向净距。
  static const double _chordGap = 0.12;

  /// log2 of the augmentation-dot multipliers (1.5, 1.75) as a lookup
  /// table — no transcendental calls at runtime (rule 14).
  static const _dotLog2 = [0.0, 0.5849625007211562, 0.8073549220576041];

  /// Lays [score] out as jianpu.
  ///
  /// [leadingWidth], [measureWidths] and [forcedColumns] are the same
  /// cross-staff alignment contract as [LayoutEngine.layout]: the grand-
  /// staff / system layout uses them to share leading width, per-measure
  /// widths and per-onset column x positions so a jianpu staff aligns
  /// barline-for-barline and column-for-column with a paired staff of
  /// another notation. [forcedColumns] is the precise form — the digit
  /// centre is placed at the column x (mirroring the staff engine's
  /// notehead-anchor convention), so a jianpu digit lands on the same x
  /// as a staff notehead at the same onset.
  ///
  /// [drawTimeSignature] / [drawKeyLabelText] control the leading furniture
  /// (the "1=C 4/4" header at the score start); both default to false —
  /// jianpu strips normally go straight into the digits. Mid-score key /
  /// time CHANGES are essential content and always draw their new label /
  /// signature regardless of these flags. [finalBarline] false
  /// closes the last measure with a plain thin barline instead of the
  /// thin+thick pair (continuing systems). [spacingStretch] multiplies
  /// the duration-proportional ideal advance (≥ 1.0), matching the staff
  /// engine's stretch so a mixed system widens uniformly.
  ScoreLayout layout(
    Score score,
    LayoutSettings settings, {
    double? leadingWidth,
    List<double>? measureWidths,
    List<Map<Fraction, double>>? forcedColumns,
    List<double>? barlineXs,
    double spacingStretch = 1.0,
    bool drawTimeSignature = false,
    bool drawKeyLabelText = false,
    bool finalBarline = true,
    int tonicOctave = 4,
  }) {
    final s = settings;
    final meta = s.metadata;
    final primitives = <LayoutPrimitive>[];
    final regions = <ElementRegion>[];
    final measureRegions = <MeasureRegion>[];
    // note id -> digit centre x / shown pitch (ties, slurs, lyrics, …).
    final anchorX = <String, double>{};
    final anchorPitch = <String, Pitch>{};
    // note id -> 该元素数字墨迹的顶边（和弦为栈顶）：延音线/圆滑线的
    // 端点从它上方起弧，避免穿过和弦栈。
    final topOf = <String, double>{};
    final lyricOf = {for (final l in score.lyrics) l.elementId: l};
    var deepestUnderline = 0.0;
    // 数字行下方的最深墨迹（和弦栈底及其低八度点）：歌词行要避开它。
    var lowestInk = digitBaseline;

    var key = score.keySignature;
    var time = score.timeSignature;

    void vline(double x, double thickness) {
      primitives.add(LinePrimitive(
          Point(x, barlineTop), Point(x, barlineBottom),
          thickness: thickness));
    }

    /// Estimated advance of a text run (core cannot measure text).
    double textWidth(String text, double size) => text.length * 0.52 * size;

    var x = s.leadingPadding;

    // 简谱行首不画任何纵线：小节线只收小节末尾（反复号等内容记号除外），
    // 每行第一个小节的开头因此是开放的，直接进入调号标签/数字。

    void drawKeyLabel(KeySignature k) {
      const size = 1.7;
      const labelBaseline = digitBaseline - 0.15;
      var cx = x;
      void putText(String t) {
        final w = textWidth(t, size);
        // Just above the digit baseline so the label is never mistaken for
        // a degree digit.
        primitives
            .add(TextPrimitive(t, Point(cx + w / 2, labelBaseline), size: size));
        cx += w;
      }

      putText('1=');
      final (glyph, letter) = _tonicNameParts(k);
      if (glyph != null) {
        // 调号里的 ♯/♭ 同样用 SMuFL 字形（文本字体不保证有这两个字符，
        // 导出图片会丢）；随标签字号等比缩小，墨迹中心对齐大写字母的
        // 帽高中心。
        const scale = _accidentalScale * (size / digitSize);
        final w = meta.bBoxOf(glyph).width * scale;
        _glyphCenteredAt(primitives, glyph, cx + w / 2 + 0.05,
            labelBaseline - 0.34 * size, meta, scale);
        cx += w + 0.15;
      }
      putText(letter);
      x = cx + 0.7;
    }

    void drawTimeSig(TimeSignature t) {
      final numerator = t.components?.join('+') ?? '${t.beats}';
      final cx = x + 0.55;
      primitives.add(TextPrimitive(numerator, Point(cx, 2.0), size: 1.7));
      primitives
          .add(TextPrimitive('${t.beatUnit}', Point(cx, 3.65), size: 1.7));
      x += 1.6;
    }

    double thickAfterThin(double thinX) =>
        thinX +
        s.thinBarlineThickness / 2 +
        s.barlineSeparation +
        s.thickBarlineThickness / 2;

    /// The x past the barline (before barlineGap) matching the staff engine's
    /// `_addBarline` advance. `closingBarline`/`endRepeat` return the right INK
    /// edge; the staff engine advances `_x` by the full line thickness past
    /// the line centre for single-line and double-thin styles — `thickness/2`
    /// beyond the right edge. Multi-line styles ending in a thick line
    /// (finalBar, endRepeat) advance exactly to the right edge.
    double barlineAdvance(BarlineStyle style, double rightEdge) {
      switch (style) {
        case BarlineStyle.none:
        case BarlineStyle.finalBar:
          return rightEdge;
        case BarlineStyle.heavy:
        case BarlineStyle.reverseFinal:
          return rightEdge + s.thickBarlineThickness / 2;
        default: // normal, doubleBar, dashed, dotted, tick, short
          return rightEdge + s.thinBarlineThickness / 2;
      }
    }

    /// 反复圆点对：中心分列数字墨盒的上、下四分之一处，整对与数字同高。
    void repeatDots(double cx) {
      _glyphCenteredAt(
          primitives, SmuflGlyph.repeatDot, cx, _repeatDotHigh, meta, 1.0);
      _glyphCenteredAt(
          primitives, SmuflGlyph.repeatDot, cx, _repeatDotLow, meta, 1.0);
    }

    double startRepeat(double at) {
      final thickX = at + s.thickBarlineThickness / 2;
      vline(thickX, s.thickBarlineThickness);
      final thinX = thickX +
          s.thickBarlineThickness / 2 +
          s.barlineSeparation +
          s.thinBarlineThickness / 2;
      vline(thinX, s.thinBarlineThickness);
      final dotX = thinX + s.thinBarlineThickness / 2 + _symbolGap + _dotHalf;
      repeatDots(dotX);
      return dotX + _dotHalf + 0.4;
    }

    double endRepeat(double at) {
      final dotX = at + 0.4 + _dotHalf;
      repeatDots(dotX);
      final thinX = dotX + _dotHalf + _symbolGap + s.thinBarlineThickness / 2;
      vline(thinX, s.thinBarlineThickness);
      final thickX = thickAfterThin(thinX);
      vline(thickX, s.thickBarlineThickness);
      return thickX + s.thickBarlineThickness / 2;
    }

    /// GB/T 46845-2025 §5.8.2.2c: 前后紧邻的两个反复段落，前一段落的后反复号
    /// 与后一段落的前反复号合并为一个符号，两者的粗纵线合用一条。
    /// Left-to-right: left dots + left thin + shared thick + right thin + right dots.
    double combinedRepeat(double at) {
      // Left dots (end-repeat side)
      final leftDotX = at + 0.4 + _dotHalf;
      repeatDots(leftDotX);
      // Left thin line
      final leftThinX =
          leftDotX + _dotHalf + _symbolGap + s.thinBarlineThickness / 2;
      vline(leftThinX, s.thinBarlineThickness);
      // Shared thick line
      final thickX = thickAfterThin(leftThinX);
      vline(thickX, s.thickBarlineThickness);
      // Right thin line
      final rightThinX = thickX +
          s.thickBarlineThickness / 2 +
          s.barlineSeparation +
          s.thinBarlineThickness / 2;
      vline(rightThinX, s.thinBarlineThickness);
      // Right dots (start-repeat side)
      final rightDotX =
          rightThinX + s.thinBarlineThickness / 2 + _symbolGap + _dotHalf;
      repeatDots(rightDotX);
      return rightDotX + _dotHalf + 0.4;
    }

    /// Draws a measure's closing barline in [style]; returns the right ink
    /// edge. A plain last measure closes with a final (thin+thick) barline.
    double closingBarline(double barX, BarlineStyle style) {
      switch (style) {
        case BarlineStyle.none:
          return barX;
        case BarlineStyle.finalBar:
          vline(barX, s.thinBarlineThickness);
          final thickX = thickAfterThin(barX);
          vline(thickX, s.thickBarlineThickness);
          return thickX + s.thickBarlineThickness / 2;
        case BarlineStyle.reverseFinal:
          vline(barX, s.thickBarlineThickness);
          final thinX = barX +
              s.thickBarlineThickness / 2 +
              s.barlineSeparation +
              s.thinBarlineThickness / 2;
          vline(thinX, s.thinBarlineThickness);
          return thinX + s.thinBarlineThickness / 2;
        case BarlineStyle.doubleBar:
          vline(barX, s.thinBarlineThickness);
          final second =
              barX + s.thinBarlineThickness + s.barlineSeparation;
          vline(second, s.thinBarlineThickness);
          return second + s.thinBarlineThickness / 2;
        case BarlineStyle.heavy:
          vline(barX, s.thickBarlineThickness);
          return barX + s.thickBarlineThickness / 2;
        case BarlineStyle.dashed:
          // GB/T 46845-2025 §5.2.2: 虚小节线是垂直细虚线。在小节线纵程内
          // 均匀排短划（划长 0.32，步进 0.52）。
          const dashLen = 0.32, dashStep = 0.52;
          var segY = barlineTop;
          while (segY <= barlineBottom + 1e-9) {
            primitives.add(LinePrimitive(
                Point(barX, segY),
                Point(barX, min(segY + dashLen, barlineBottom)),
                thickness: s.thinBarlineThickness));
            segY += dashStep;
          }
          return barX + s.thinBarlineThickness / 2;
        // Dotted/tick/short degrade to a plain line in v1.
        default:
          vline(barX, s.thinBarlineThickness);
          return barX + s.thinBarlineThickness / 2;
      }
    }

    /// 连音符（三连音等）：数字上方的开口括线，两端下折短钩，中央断开处
    /// 写比例数字（"3"）。横线默认在 [_tupletY]（延音线弧顶之上）；跨段
    /// 内有和弦栈顶更高时整条括线上抬避让。数字竖向居中于横线的断口。
    void drawTuplet(double firstDigitX, double lastDigitX, int actual,
        double spanTop) {
      final x1 = firstDigitX - _digitInkHalf - 0.2;
      final x2 = lastDigitX + _digitInkHalf + 0.2;
      final bracketY = min(_tupletY, spanTop - _symbolGap - _tupletHook);
      final label = '$actual';
      final halfLabel = textWidth(label, _tupletDigitSize) / 2 + 0.18;
      final midX = (x1 + x2) / 2;
      const th = 0.14;
      // 中央断口两侧的横线段（括线太短时为负长，钳到端点）。
      primitives.add(LinePrimitive(Point(x1, bracketY),
          Point(max(x1, midX - halfLabel), bracketY),
          thickness: th));
      primitives.add(LinePrimitive(Point(min(x2, midX + halfLabel), bracketY),
          Point(x2, bracketY),
          thickness: th));
      primitives.add(LinePrimitive(Point(x1, bracketY),
          Point(x1, bracketY + _tupletHook),
          thickness: th));
      primitives.add(LinePrimitive(Point(x2, bracketY),
          Point(x2, bracketY + _tupletHook),
          thickness: th));
      // 数字竖向居中于横线：baseline = 线 y + 半帽高（0.68 em 估计）。
      primitives.add(TextPrimitive(
          label, Point(midX, bracketY + 0.34 * _tupletDigitSize),
          size: _tupletDigitSize));
    }

    // --- leading furniture: the "1=X" key label, then the time signature.
    if (drawKeyLabelText) drawKeyLabel(key);
    if (time != null && drawTimeSignature) drawTimeSig(time);
    if (leadingWidth != null) x = max(x, leadingWidth);

    // 增时线格位 = 一个四分音符的前进量（含 stretch）："5 -" 与 "5 5"
    // 占用同样的水平宽度，与长休止符展开的多个 "0" 共用同一网格。
    final quarterCell = _advance(NoteDuration.quarter, s,
        dashes: 0, lyricReserve: 0, spacingStretch: spacingStretch);

    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];
      // 变调/变拍是内容而非装饰：无论 leading furniture 是否绘制，
      // 曲中的新调号、新拍号都必须标出。
      if (measure.keyChange != null) {
        key = measure.keyChange!;
        drawKeyLabel(key);
      }
      if (measure.timeChange != null) {
        time = measure.timeChange;
        drawTimeSig(time!);
      }
      // GB/T 46845-2025 §5.8.2.2b: 作品开端的前段落反复号省略。
      // §5.8.2.2c: 与前一小节 endRepeat 合并为组合符号时，startRepeat 也省略。
      final prevHadEndRepeat =
          m > 0 && score.measures[m - 1].endRepeat;
      final nextHasStartRepeat =
          m < score.measures.length - 1 &&
          score.measures[m + 1].startRepeat;
      final combinedRepeatWithNext =
          measure.endRepeat && nextHasStartRepeat;
      if (measure.startRepeat && m > 0 && !prevHadEndRepeat) {
        x = startRepeat(x);
      }
      final startX = x;

      // §2.9 cross-staff gridding: when a shared column table is supplied,
      // each element is placed at its onset's column (from the measure's
      // content start) instead of advancing sequentially, so a jianpu digit
      // lands on the same x as a staff notehead at the same onset.
      final columns = forcedColumns != null && m < forcedColumns.length
          ? forcedColumns[m]
          : null;
      final measureContentStart = x;

      // In-measure accidental memory (rule 9 analogue): the deviation from
      // the key last shown for each (step, octave).
      final memory = <(int, int), int>{};
      final cols = <_Col>[];
      var onset = Fraction.zero;

      for (var i = 0; i < measure.elements.length; i++) {
        final element = measure.elements[i];
        final effective = measure.effectiveDurationAt(i);
        final duration = element.duration;
        final columnX = columns == null ? null : columns[onset];
        var digitX = columnX == null ? x : measureContentStart + columnX;
        final id = element.id;

        final (dashes, augDots) = _durationMarks(duration);
        // 本元素墨迹底（减时线的挂靠基准）：单音/休止符为数字基线，和弦
        // 为栈底（含最低音的低八度点）。
        var columnBottom = digitBaseline;
        if (element is NoteElement) {
          // 顶侧游标：八度点/音符记号/装饰音从数字（或和弦栈）顶向上层叠。
          var topCursor = digitTop;
          if (element.pitches.length > 1) {
            // 和弦：各音级数字纵向叠放在同一格位，高音在上（自上而下读），
            // 字号缩为 _chordDigitFactor 倍，栈以数字行中线（_digitMid）
            // 为中心，整行墨高随栈高上长。八度点只画最外两侧——最高音的
            // 高八度点在栈顶之上、最低音的低八度点在栈底（减时线）之下；
            // 内层音的八度点无处安放，v1 省略。
            final sorted = [...element.pitches]
              ..sort((a, b) => b.midiNumber.compareTo(a.midiNumber));
            final degrees = [
              for (final p in sorted) _degreeOf(p, key, tonicOctave)
            ];
            const chordSize = digitSize * _chordDigitFactor;
            final cap = 0.68 * chordSize;
            final n = sorted.length;
            final stackH = n * cap + (n - 1) * _chordGap;
            final stackTop = _digitMid - stackH / 2;
            final stackBottom = _digitMid + stackH / 2; // 最低音 baseline
            // 各成员的变音记号前缀共享同一条左挂区（纵向错开，不互撞）；
            // 自由排布时数字整体右移最大外推量。
            final drawDevs = <int, int>{};
            var overhang = 0.0;
            for (var mi = 0; mi < n; mi++) {
              final dev = degrees[mi].$2;
              final memKey = (sorted[mi].step.index, sorted[mi].octave);
              if (dev == (memory[memKey] ?? 0)) continue;
              memory[memKey] = dev;
              if (element.showAccidental == false) continue;
              drawDevs[mi] = dev;
              overhang = max(overhang, _prefixOverhang(dev, meta));
            }
            if (columnX == null) digitX += overhang;
            const chordInkHalf = _digitInkHalf * _chordDigitFactor;
            for (var mi = 0; mi < n; mi++) {
              final baseline = stackBottom - (n - 1 - mi) * (cap + _chordGap);
              primitives.add(TextPrimitive('${degrees[mi].$1}',
                  Point(digitX, baseline),
                  size: chordSize, elementId: id));
              final dev = drawDevs[mi];
              if (dev != null) {
                _drawAccidentalPrefix(primitives, dev, digitX, meta, id,
                    cy: baseline - cap / 2, inkHalf: chordInkHalf);
              }
            }
            topCursor = stackTop;
            if (degrees.first.$3 > 0) {
              var cy = stackTop - _symbolGap - _dotHalf;
              for (var d = 0; d < degrees.first.$3; d++) {
                _glyphCenteredAt(primitives, SmuflGlyph.augmentationDot,
                    digitX, cy, meta, 1.0, id);
                cy -= _dotStep;
              }
              topCursor = cy + _dotStep - _dotHalf;
            }
            columnBottom = stackBottom;
            if (degrees.last.$3 < 0) {
              final flagCount = duration.base.flagCount;
              final belowCursor = flagCount > 0
                  ? stackBottom +
                      _symbolGap +
                      _lineHalf +
                      (flagCount - 1) * _underlineStep +
                      _lineHalf
                  : stackBottom;
              var cy = belowCursor + _symbolGap + _dotHalf;
              for (var d = 0; d < -degrees.last.$3; d++) {
                _glyphCenteredAt(primitives, SmuflGlyph.augmentationDot,
                    digitX, cy, meta, 1.0, id);
                cy += _dotStep;
              }
              columnBottom = max(columnBottom, cy - _dotStep + _dotHalf);
            }
            if (id != null) {
              anchorX[id] = digitX;
              anchorPitch[id] = sorted.first;
            }
            lowestInk = max(lowestInk, columnBottom);
          } else {
            final shown = element.pitches.first;
            final (digit, deviation, octaveDots) =
                _degreeOf(shown, key, tonicOctave);
            // Accidentals: a prefix is drawn when the pitch deviates from
            // the key differently than this (step, octave) did earlier in
            // the bar.
            final memKey = (shown.step.index, shown.octave);
            final remembered = memory[memKey] ?? 0;
            if (deviation != remembered) {
              memory[memKey] = deviation;
              if (element.showAccidental != false) {
                // 变音记号从数字墨盒向左外推；自由排布时把数字右移整个外推
                // 量，让前缀落在本元素自己的前进格内——否则前一个元素的
                // 右侧（数字/附点/增时线）会被前缀压上。强制列位（跨谱表
                // 对齐）下列位不可动，前缀照旧左挂。
                if (columnX == null) {
                  digitX += _prefixOverhang(deviation, meta);
                }
                _drawAccidentalPrefix(primitives, deviation, digitX, meta, id);
              }
            }
            primitives.add(TextPrimitive(
                '$digit', Point(digitX, digitBaseline),
                size: digitSize, elementId: id));
            // 八度点：高八度点从数字墨盒顶向上层叠；低八度点从最深的减时线
            // （无减时线时为数字底部）向下层叠。点与数字、点与点之间的净距
            // 都是统一的 _symbolGap / 层叠净距。
            if (octaveDots > 0) {
              var cy = digitTop - _symbolGap - _dotHalf;
              for (var d = 0; d < octaveDots; d++) {
                _glyphCenteredAt(primitives, SmuflGlyph.augmentationDot,
                    digitX, cy, meta, 1.0, id);
                cy -= _dotStep;
              }
              topCursor = cy + _dotStep - _dotHalf;
            } else if (octaveDots < 0) {
              final flagCount = duration.base.flagCount;
              final belowCursor = flagCount > 0
                  ? _underlineY + (flagCount - 1) * _underlineStep + _lineHalf
                  : digitBaseline;
              var cy = belowCursor + _symbolGap + _dotHalf;
              for (var d = 0; d < -octaveDots; d++) {
                _glyphCenteredAt(primitives, SmuflGlyph.augmentationDot,
                    digitX, cy, meta, 1.0, id);
                cy += _dotStep;
              }
            }
            if (id != null) {
              anchorX[id] = digitX;
              anchorPitch[id] = shown;
            }
          }
          if (id != null) topOf[id] = topCursor;
          // 装饰滑音（GB 7.6 主从滑音）属于装饰音，按 7.11.7 的层叠次序
          // 最靠近本音：先于音符记号上叠。上滑 ↗ 用 SMuFL brassScoop，
          // 下滑 ↘ 用 brassFallLipShort，回滑 = 两者并排居中。
          final techniques = element.techniques;
          if (techniques.contains(TechniqueMark.slideUp)) {
            topCursor = _glyphInkBottomAt(primitives, SmuflGlyph.brassScoop,
                digitX, topCursor - _symbolGap, meta, _articScale, id);
          }
          if (techniques.contains(TechniqueMark.slideDown)) {
            topCursor = _glyphInkBottomAt(
                primitives,
                SmuflGlyph.brassFallLipShort,
                digitX,
                topCursor - _symbolGap,
                meta,
                _articScale,
                id);
          }
          if (techniques.contains(TechniqueMark.slideReturn)) {
            final sW = meta.bBoxOf(SmuflGlyph.brassScoop).width * _articScale;
            final fW =
                meta.bBoxOf(SmuflGlyph.brassFallLipShort).width * _articScale;
            final inkBottom = topCursor - _symbolGap;
            // 组合墨迹区间（scoop + 净距 + fall）整体居中于数字。
            final totalW = sW + _symbolGap + fW;
            final topA = _glyphInkBottomAt(primitives, SmuflGlyph.brassScoop,
                digitX - totalW / 2 + sW / 2, inkBottom, meta, _articScale,
                id);
            final topB = _glyphInkBottomAt(
                primitives,
                SmuflGlyph.brassFallLipShort,
                digitX + totalW / 2 - fW / 2,
                inkBottom,
                meta,
                _articScale,
                id);
            topCursor = min(topA, topB);
          }
          // 音符记号（断音、重音、保持音等）与八度点共用同一条向上游标：
          // 每个记号的墨迹底边落在游标下方 _symbolGap 处，再把游标推到
          // 自身墨迹顶边 —— 不会与八度点或数字重叠。
          for (final art in element.articulations) {
            if (!_jianpuArticulations.contains(art)) continue;
            final inkBottom = topCursor - _symbolGap;
            if (art == Articulation.staccato) {
              // GB/T 46845-2025 §6.5.3.1: 断音记号用实心倒三角 ▼
              // 记在音符上方（文字基线 ≈ 墨迹底边）。
              const size = 1.0;
              primitives.add(TextPrimitive(
                  '▼', Point(digitX, inkBottom),
                  size: size, elementId: id));
              topCursor = inkBottom - 0.72 * size;
            } else {
              topCursor = _glyphInkBottomAt(
                  primitives,
                  SmuflGlyph.articulationGlyph(art, above: true),
                  digitX,
                  inkBottom,
                  meta,
                  _articScale,
                  id);
            }
          }
          // 装饰音（颤音/波音/回音等）在最外侧：位于音符记号之上。
          final ornament = element.ornament;
          if (ornament != null) {
            topCursor = _glyphInkBottomAt(
                primitives,
                SmuflGlyph.ornamentGlyph(ornament),
                digitX,
                topCursor - _symbolGap,
                meta,
                _articScale,
                id);
            // 带变音记号的颤音：小号升降/还原号居中于 tr 上方。
            final alter = ornament.trillAccidentalAlter;
            if (alter != null) {
              final accGlyph = switch (alter) {
                1 => SmuflGlyph.accidentalSharp,
                -1 => SmuflGlyph.accidentalFlat,
                _ => SmuflGlyph.accidentalNatural,
              };
              topCursor = _glyphInkBottomAt(primitives, accGlyph, digitX,
                  topCursor - _symbolGap, meta, _accidentalScale * 0.7, id);
            }
          }
          // 其余技法记号叠在装饰音之上（GB 7.11：记在生效处音符上方），
          // 按枚举序逐层外推：揉弦是 SMuFL 波状线，拨弦/花舌/厉音/换气/吐音
          // 是约定俗成的文字记号（拨/※/⊥/∨/T），文字基线 ≈ 墨迹底边。
          for (final mark in TechniqueMark.values) {
            if (!techniques.contains(mark)) continue;
            final inkBottom = topCursor - _symbolGap;
            switch (mark) {
              case TechniqueMark.slideUp:
              case TechniqueMark.slideDown:
              case TechniqueMark.slideReturn:
                break; // 装饰滑音已在音符记号之前画过。
              case TechniqueMark.vibrato:
                topCursor = _glyphInkBottomAt(
                    primitives,
                    SmuflGlyph.wiggleVibratoWide,
                    digitX,
                    inkBottom,
                    meta,
                    _articScale,
                    id);
              case TechniqueMark.pizzicato:
                primitives.add(TextPrimitive('拨', Point(digitX, inkBottom),
                    size: 1.0, elementId: id));
                topCursor = inkBottom - 0.88;
              case TechniqueMark.flutterTongue:
                primitives.add(TextPrimitive('※', Point(digitX, inkBottom),
                    size: 1.0, elementId: id));
                topCursor = inkBottom - 0.88;
              case TechniqueMark.sharpTongue:
                primitives.add(TextPrimitive('⊥', Point(digitX, inkBottom),
                    size: 1.0, elementId: id));
                topCursor = inkBottom - 0.88;
              case TechniqueMark.breath:
                primitives.add(TextPrimitive('∨', Point(digitX, inkBottom),
                    size: 1.0, elementId: id));
                topCursor = inkBottom - 0.72;
              case TechniqueMark.tonguing:
                primitives.add(TextPrimitive('T', Point(digitX, inkBottom),
                    size: 1.0, elementId: id));
                topCursor = inkBottom - 0.72;
            }
          }
        } else {
          // Rest element
          final longRestUnits = _longRestQuarterUnits(duration);
          if (longRestUnits <= 1) {
            // Quarter or shorter: single 0, plus dots/underlines as needed.
            primitives.add(TextPrimitive(
                '0', Point(digitX, digitBaseline),
                size: digitSize, elementId: id));
          } else {
            // GB/T 46845-2025 §6.3.7.2 / §6.3.8.6:
            // 二分/全休止符不用增时线，而用增加四分休止符个数的办法构成。
            // 附点二分/全休止符同理，用增加单纯休止符个数而不用附点。
            final qAdvance = _advance(NoteDuration.quarter, s,
                dashes: 0, lyricReserve: 0, spacingStretch: spacingStretch);
            for (var u = 0; u < longRestUnits; u++) {
              final ux = digitX + u * qAdvance;
              primitives.add(TextPrimitive(
                  '0', Point(ux, digitBaseline),
                  size: digitSize, elementId: id));
            }
          }
          // 休止符也记锚点：连音符括线（tuplet）可能覆盖休止符。
          if (id != null) anchorX[id] = digitX;
        }
        // 列位在记号分支之后收集：变音记号可能已把数字右移。
        cols.add(_Col(digitX, duration, onset,
            isRest: element is! NoteElement,
            bottom: columnBottom,
            dotExt: augDots > 0
                ? _digitInkHalf +
                    _symbolGap +
                    (augDots - 1) * (2 * _dotHalf + _symbolGap) +
                    2 * _dotHalf
                : 0));
        // 增时线：每条占一个四分音符格位，中心落在格点上（"5 -" 与
        // "5 5" 同宽）。附点从数字墨迹右缘起按 _symbolGap 依次排开，
        // 多附点之间保持同样的净距。长休止符两者皆无 —— 展开为多个 "0"。
        final isLongRest =
            element is! NoteElement && _longRestQuarterUnits(duration) > 1;
        if (!isLongRest) {
          for (var d = 0; d < dashes; d++) {
            final cx = digitX + quarterCell * (d + 1);
            primitives.add(LinePrimitive(
                Point(cx - _dashLength / 2, _digitMid),
                Point(cx + _dashLength / 2, _digitMid),
                thickness: 0.18, elementId: id));
          }
          for (var d = 0; d < augDots; d++) {
            primitives.add(GlyphPrimitive(SmuflGlyph.augmentationDot,
                Point(
                    digitX +
                        _digitInkHalf +
                        _symbolGap +
                        d * (2 * _dotHalf + _symbolGap),
                    _augDotY),
                elementId: id));
          }
        }

        final lyric = id == null ? null : lyricOf[id];
        final advance = isLongRest
            ? _longRestQuarterUnits(duration) *
                _advance(NoteDuration.quarter, s,
                    dashes: 0,
                    lyricReserve: lyric?.text.length ?? 0,
                    spacingStretch: spacingStretch)
            : _advance(duration, s,
                dashes: dashes,
                lyricReserve: lyric?.text.length ?? 0,
                spacingStretch: spacingStretch,
                quarterCell: quarterCell);
        if (id != null) {
          // 命中区域覆盖本元素的全部墨迹：和弦栈上下延伸，单音保持
          // 1.1…4.7 的默认盒。
          final regionTop = min(1.1, (topOf[id] ?? digitTop) - 0.2);
          final regionBottom = max(4.7, columnBottom + 0.3);
          regions.add(ElementRegion(
              id,
              Rectangle(digitX - 0.75, regionTop, max(advance - 0.4, 1.5),
                  regionBottom - regionTop)));
        }
        // 从（可能因变音记号右移过的）数字位置前进，外推量计入本元素。
        x = digitX + advance;
        onset += effective;
      }

      // §2.9: advance to the SHARED measure-end column (the largest onset
      // across all voices/staves in this measure), not just this staff's own
      // content end, so a short-voice jianpu staff still draws its barline
      // at the aligned full-measure x. For a normal full measure
      // `onset == measureEnd`, so this is unchanged.
      if (columns != null && columns.isNotEmpty) {
        final measureEnd = columns.keys.reduce((a, b) => a > b ? a : b);
        final endX = columns[measureEnd];
        if (endX != null) x = max(x, measureContentStart + endX);
      }

      // 减时线: group the measure's eighth-and-shorter columns.
      deepestUnderline =
          max(deepestUnderline, _layoutUnderlines(primitives, cols, time));

      var barX = max(x, startX + 2.0);
      if (measureWidths != null && m < measureWidths.length) {
        barX = max(barX, startX + measureWidths[m]);
      }
      if (barlineXs != null && m < barlineXs.length) {
        barX = max(barX, barlineXs[m]);
      }
      if (measure.volta != null) {
        const y = -0.3;
        // Left vertical: drops down from the horizontal line.
        primitives.add(LinePrimitive(
            Point(startX, y + 0.9), Point(startX, y),
            thickness: 0.14));
        // Horizontal top line.
        primitives.add(LinePrimitive(
            Point(startX, y), Point(barX, y),
            thickness: 0.14));
        // GB/T 46845-2025 §5.11.4: 跳房子记号右端有下垂竖线。
        primitives.add(LinePrimitive(
            Point(barX, y), Point(barX, y + 0.9),
            thickness: 0.14));
        // Volta number sits above the horizontal line with a 0.25-ss gap,
        // just right of the vertical line. Size 1.1 (was 1.5 — too large).
        primitives.add(TextPrimitive(
            '${measure.volta}.', Point(startX + 0.25, y - 0.25),
            size: 1.1));
      }
      final isLast = m == score.measures.length - 1;
      final barlineStyle = isLast && measure.barline == BarlineStyle.normal
          ? (finalBarline
              ? BarlineStyle.finalBar
              : BarlineStyle.normal)
          : measure.barline;
      final end = combinedRepeatWithNext
          ? combinedRepeat(barX)
          : measure.endRepeat
              ? endRepeat(barX)
              : closingBarline(barX, barlineStyle);
      measureRegions.add(MeasureRegion(m, startX: startX, endX: barX));
      // Match the staff engine's advance: _addFinalBarline returns the right
      // ink edge of the closing barline with NO trailing barlineGap for the
      // default last measure (normal barline → final/thin barline), while
      // _addBarline/_addEndRepeat advance past the barline (with an extra
      // half-thickness for single-line styles) and add barlineGap. An
      // endRepeat's last line is thick, so its advance == right edge (like
      // finalBar).  A combined repeat (§5.8.2.2c) serves as both the closing
      // of this measure and the opening of the next, so there is no trailing
      // barlineGap — the next measure's content starts right after it.
      final isDefaultLast = isLast &&
          !measure.endRepeat &&
          measure.barline == BarlineStyle.normal;
      if (combinedRepeatWithNext) {
        x = end;
      } else {
        final effectiveStyle =
            measure.endRepeat ? BarlineStyle.finalBar : barlineStyle;
        x = isDefaultLast
            ? end
            : barlineAdvance(effectiveStyle, end) + s.barlineGap;
      }
    }

    final width = x;

    // 注意：简谱减时线不跨小节线连接（标准简谱记谱法：减时线仅
    // 在小节内按拍分组）。此前版本的 cross-measure 连接段会把小节
    // 末尾音符的减时线延伸到小节线、再接到下一小节首音符，视觉上
    // 让跨小节的 4 个八分音符合成一根 beam —— 这是错误的，已移除。

    // --- post-passes: ties, slurs, dynamics, annotations, lyrics. --------
    final notesInOrder = [
      for (final measure in score.measures)
        ...measure.elements.whereType<NoteElement>(),
    ];
    for (var i = 0; i < notesInOrder.length - 1; i++) {
      final note = notesInOrder[i];
      if (!note.tieToNext) continue;
      final next = notesInOrder[i + 1];
      final a = anchorX[note.id], b = anchorX[next.id];
      if (a == null || b == null) continue;
      // Only an identical shown pitch ties (a tie into another pitch is
      // not drawn).
      if (anchorPitch[note.id] != anchorPitch[next.id]) continue;
      // 端点从各自元素的墨迹顶之上起弧：和弦栈顶高于数字墨盒顶时，
      // 弧线整体抬升，不穿过栈。
      final yA = min(1.35, (topOf[note.id] ?? digitTop) - _symbolGap);
      final yB = min(1.35, (topOf[next.id] ?? digitTop) - _symbolGap);
      final apex = min(yA, yB) - 0.6;
      final span = b - a;
      primitives.add(CurvePrimitive(
        Point(a + 0.55, yA),
        Point(a + span * 0.25, apex),
        Point(b - span * 0.25, apex),
        Point(b - 0.55, yB),
        thickness: 0.12,
      ));
    }
    for (final slur in score.slurs) {
      final a = anchorX[slur.startId], b = anchorX[slur.endId];
      if (a == null || b == null || b <= a) continue;
      final span = b - a;
      final yA = min(1.3, (topOf[slur.startId] ?? digitTop) - _symbolGap);
      final yB = min(1.3, (topOf[slur.endId] ?? digitTop) - _symbolGap);
      final base = min(yA, yB);
      final lift = max(0.7, span * 0.15);
      primitives.add(CurvePrimitive(
        Point(a + 0.4, yA),
        Point(a + span * 0.3, base - lift),
        Point(b - span * 0.3, base - lift),
        Point(b - 0.4, yB),
        thickness: 0.14,
      ));
    }
    // 连音符：括线范围取跨段首元素到末元素的数字中心（休止符同样记了
    // 锚点）；括线高度避让跨段内的和弦栈顶。v1 只排第 1 声部（简谱单
    // 声部）。
    for (final measure in score.measures) {
      for (final tuplet in measure.tuplets) {
        if (tuplet.voice != 0) continue;
        double? firstX, lastX;
        var spanTop = digitTop;
        for (var i = tuplet.startIndex;
            i <= tuplet.endIndex && i < measure.elements.length;
            i++) {
          final eid = measure.elements[i].id;
          final at = eid == null ? null : anchorX[eid];
          if (at == null) continue;
          firstX ??= at;
          lastX = at;
          spanTop = min(spanTop, topOf[eid] ?? digitTop);
        }
        if (firstX == null || lastX == null) continue;
        drawTuplet(firstX, lastX, tuplet.actual, spanTop);
      }
    }
    // GB/T 46845-2025 §6.7.3: 力度记号的位置：器乐谱记在乐谱下方，
    // 声乐谱记在乐谱上方。
    final isVocal = score.lyrics.isNotEmpty;
    final dynamicY = isVocal ? 0.5 : 4.7;
    for (final dynamic_ in score.dynamics) {
      final at = anchorX[dynamic_.elementId];
      if (at == null) continue;
      primitives.add(TextPrimitive(
          dynamic_.level.name, Point(at, dynamicY),
          size: 1.6));
    }
    for (final annotation in score.annotations) {
      final at = anchorX[annotation.elementId];
      if (at == null) continue;
      primitives.add(TextPrimitive(
          annotation.text, Point(at, 0.5),
          size: s.annotationSize));
    }
    if (score.lyrics.isNotEmpty) {
      final size = s.lyricSize;
      final lineHeight = size * 1.7;
      // 歌词行避开数字行下方最深的墨迹：减时线、和弦栈底及其低八度点。
      final firstBaseline = max(5.5, max(deepestUnderline, lowestInk) + 2.5);

      // Group syllables into verses; each verse is its own stacked row.
      final byVerse = <int, List<Lyric>>{};
      for (final lyric in score.lyrics) {
        byVerse.putIfAbsent(lyric.verse, () => []).add(lyric);
      }
      final verses = byVerse.keys.toList()..sort();

      for (var row = 0; row < verses.length; row++) {
        final lyrics = byVerse[verses[row]]!;
        final baselineY = firstBaseline + row * lineHeight;

        // Anchor x per syllable from the note's digit centre.
        final centers = <double>[];
        final halfWidths = <double>[];
        final valid = <int>[];
        for (var i = 0; i < lyrics.length; i++) {
          final at = anchorX[lyrics[i].elementId];
          if (at == null) continue;
          centers.add(at);
          halfWidths.add(_estTextHalfWidth(lyrics[i].text, size));
          valid.add(i);
        }
        // Push each syllable right of the previous so wide lyrics on close
        // notes never overlap. The gap (0.8 * size) ensures CJK characters
        // have a clear visual separation even when forced-column alignment
        // (multi-staff systems) places notes closer than the lyricFloor.
        _spreadRight(centers, halfWidths, 0.8 * size);

        for (var j = 0; j < valid.length; j++) {
          final lyric = lyrics[valid[j]];
          primitives.add(TextPrimitive(
              lyric.text, Point(centers[j], baselineY),
              size: size));
        }
      }
    }

    // Ink bounds from the actual primitives (the tab engine's approach), so
    // above/below ink is never clipped.
    var minY = barlineTop, maxY = barlineBottom;
    void span(double a, double b) {
      minY = min(minY, min(a, b));
      maxY = max(maxY, max(a, b));
    }

    for (final p in primitives) {
      switch (p) {
        case GlyphPrimitive(:final smuflName, :final position, :final scale):
          final box = meta.bBoxOf(smuflName);
          span(position.y - box.neY * scale, position.y - box.swY * scale);
        case LinePrimitive(:final from, :final to):
          span(from.y, to.y);
        case CurvePrimitive(
            :final start,
            :final control1,
            :final control2,
            :final end
          ):
          span(min(min(start.y, control1.y), min(control2.y, end.y)),
              max(max(start.y, control1.y), max(control2.y, end.y)));
        case BeamPrimitive(:final start, :final end, :final thickness):
          span(min(start.y, end.y) - thickness / 2,
              max(start.y, end.y) + thickness / 2);
        case TextPrimitive(:final position, :final size):
          span(position.y - 0.8 * size, position.y + 0.25 * size);
      }
    }
    const pad = 0.3;

    return ScoreLayout(
      width: width,
      height: maxY - minY + 2 * pad,
      top: minY - pad,
      primitives: List.unmodifiable(primitives),
      regions: List.unmodifiable(regions),
      measureRegions: List.unmodifiable(measureRegions),
    );
  }

  /// The underline groups of one measure: consecutive eighth-and-shorter
  /// columns share one first-level line per metric window — the shared
  /// `computeBeamRuns` (beam_grouping.dart), the same grouping as staff
  /// beaming rule 7 (a quarter-note window when unmetered; GB/T 46845-2025
  /// §6.3.5.3 whole-measure grouping for 3/8-type meters). 减时线只在当前
  /// 小节内按拍分组，不跨小节线连接（标准简谱记谱法）。
  /// Deeper levels cover only the columns that need them.
  ///
  /// Returns the deepest underline y drawn (0 when none).
  double _layoutUnderlines(
      List<LayoutPrimitive> primitives, List<_Col> cols, TimeSignature? time) {
    int levelOf(_Col c) => c.duration.base.flagCount;

    final runs = computeBeamRuns(
      count: cols.length,
      onsetAt: (i) => cols[i].onset,
      // 简谱休止符同样带减时线（八分休止 = "0" + 一条减时线），与同拍的
      // 音符共用一级减时线 —— 对分组而言它是 beamable，不是透明跨过的。
      roleAt: (i) => levelOf(cols[i]) >= 1
          ? BeamItemRole.beamable
          : BeamItemRole.breaker,
      time: time,
    );

    var deepest = 0.0;
    for (final run in runs) {
      final maxLevel = run.map((i) => levelOf(cols[i])).reduce(max);
      // 本组减时线挂靠在组内最深的列墨迹底之下（和弦栈会把列底压低，
      // 整条减时线随之下移，不穿过栈）；普通列即 _underlineY。
      final runBottom = run.map((i) => cols[i].bottom).reduce(max);
      final firstY = runBottom + _symbolGap + _lineHalf;
      for (var level = 1; level <= maxLevel; level++) {
        var k = 0;
        while (k < run.length) {
          if (levelOf(cols[run[k]]) < level) {
            k++;
            continue;
          }
          var l = k;
          while (l + 1 < run.length && levelOf(cols[run[l + 1]]) >= level) {
            l++;
          }
          final y = firstY + (level - 1) * _underlineStep;
          // 右端延伸到本段最后一个数字的附点墨迹右缘 —— 附点属于该音符的
          // 时值，减时线要把它一起盖住。
          primitives.add(LinePrimitive(
            Point(cols[run[k]].x - _underlinePad, y),
            Point(cols[run[l]].x + max(_underlinePad, cols[run[l]].dotExt), y),
            thickness: 0.16,
          ));
          deepest = max(deepest, y);
          k = l + 1;
        }
      }
    }
    return deepest;
  }

  /// 增时线/附点 split for a duration: notes longer than a quarter extend
  /// with dashes (one per extra quarter — a dotted half is dash-only, the
  /// jianpu convention); a quarter or shorter carries augmentation dots.
  static (int dashes, int augDots) _durationMarks(NoteDuration duration) {
    if (duration.base.log2Value > -2) {
      final (num, den) = duration.fraction;
      return (max(0, (num * 4 / den).round() - 1), 0);
    }
    return (0, duration.dots);
  }

  /// Number of quarter-rest "0" units for a rest per GB/T 46845-2025
  /// §6.3.7.2 / §6.3.8.5.  Rests whose base value is longer than a quarter
  /// note are drawn as multiple quarter-rest "0"s instead of using
  /// augmentation dashes/dots.  Returns 1 for quarter and shorter rests
  /// (which keep the single-0 + dots/underlines form).
  static int _longRestQuarterUnits(NoteDuration duration) {
    if (duration.base.log2Value <= -2) return 1; // quarter or shorter
    final (num, den) = duration.fraction;
    return (num * 4 / den).round();
  }

  /// The advance for one column: the staff engine's logarithmic ideal,
  /// floored by the dash cells (a note with n 增时线 occupies n+1 quarter-
  /// note cells — "5 -" is exactly as wide as "5 5") and by the lyric
  /// syllable's estimated width. [spacingStretch] multiplies the ideal
  /// (≥ 1.0), matching the staff engine so a mixed system widens uniformly.
  double _advance(NoteDuration duration, LayoutSettings s,
      {required int dashes,
      required int lyricReserve,
      double spacingStretch = 1.0,
      double quarterCell = 0}) {
    final ideal = max(
        2.0,
        (s.spacingBase +
                s.spacingPerLog2 *
                    (4 + duration.base.log2Value + _dotLog2[duration.dots])) *
            spacingStretch);
    final dashFloor =
        dashes > 0 && quarterCell > 0 ? (dashes + 1) * quarterCell : 0.0;
    // CJK lyrics are full-width (1 em/char); the advance must clear the
    // syllable width plus a gap so adjacent lyrics never overlap.
    final lyricFloor = lyricReserve > 0
        ? (lyricReserve + 1.0) * s.lyricSize
        : 0.0;
    return max(ideal, max(dashFloor, lyricFloor));
  }

  /// Pitch → (digit 1..7, deviation from the key in semitones, octave-dot
  /// count) for a major key (movable do; v1). The octave dots compare the
  /// pitch's diatonic index with the tonic's at [tonicOctave].
  static (int, int, int) _degreeOf(
      Pitch pitch, KeySignature key, int tonicOctave) {
    final tonicStep = _tonicStepIndex(key);
    final digit = (pitch.step.index - tonicStep + 7) % 7 + 1;
    final deviation = pitch.alter - key.alterFor(pitch.step);
    // Floor division (not ~/): negative deltas like -6 must still map to
    // octave -1, otherwise d3..b3 lose their low dot (found via scale test).
    final dots =
        ((pitch.diatonicIndex - (tonicOctave * 7 + tonicStep)) / 7).floor();
    return (digit, deviation, dots);
  }

  /// 变音记号前缀从数字中心向左的外推量：数字墨迹半宽 + 净距 + 前缀
  /// 墨迹总宽（重升为两个 ♯ + 净距）。|deviation| > 2 不画，外推为 0。
  double _prefixOverhang(int deviation, SmuflMetadata meta) {
    final w = switch (deviation) {
      1 => meta.bBoxOf(SmuflGlyph.accidentalSharp).width * _accidentalScale,
      -1 => meta.bBoxOf(SmuflGlyph.accidentalFlat).width * _accidentalScale,
      2 => 2 *
              meta.bBoxOf(SmuflGlyph.accidentalSharp).width *
              _accidentalScale +
          _symbolGap,
      -2 => meta.bBoxOf(SmuflGlyph.accidentalDoubleFlat).width *
          _accidentalScale,
      0 => meta.bBoxOf(SmuflGlyph.accidentalNatural).width * _accidentalScale,
      _ => 0.0,
    };
    return w > 0 ? _digitInkHalf + _symbolGap + w : 0.0;
  }

  /// 变音记号前缀：SMuFL 字形而非文本（♯♭♮ 不在常规文本字体里，导出
  /// 图片时会变成豆腐块）。墨迹右缘距数字墨盒左缘 _symbolGap，垂直中心
  /// 对齐数字墨盒中心（和弦成员则对齐各自数字的中心 [cy]，墨盒半宽
  /// [inkHalf] 随和弦字号缩小）。重升按传统简谱并排画两个 ♯；重降用
  /// SMuFL 双降号（其字形本身即两个 ♭ 的连写比例）。|deviation| > 2 不画。
  void _drawAccidentalPrefix(List<LayoutPrimitive> primitives, int deviation,
      double digitX, SmuflMetadata meta, String? elementId,
      {double cy = _digitMid, double inkHalf = _digitInkHalf}) {
    final rx = digitX - inkHalf - _symbolGap;
    switch (deviation) {
      case 1:
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalSharp, rx,
            cy, meta, _accidentalScale, elementId);
      case -1:
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalFlat, rx,
            cy, meta, _accidentalScale, elementId);
      case 2:
        final w = meta.bBoxOf(SmuflGlyph.accidentalSharp).width *
            _accidentalScale;
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalSharp, rx,
            cy, meta, _accidentalScale, elementId);
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalSharp,
            rx - w - _symbolGap, cy, meta, _accidentalScale, elementId);
      case -2:
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalDoubleFlat,
            rx, cy, meta, _accidentalScale, elementId);
      case 0:
        _glyphInkRightCenterAt(primitives, SmuflGlyph.accidentalNatural, rx,
            cy, meta, _accidentalScale, elementId);
    }
  }

  /// The diatonic step index (C=0…B=6) of [key]'s major tonic — the same
  /// circle-of-fifths derivation the staff engine's shape notes use.
  /// Non-standard signatures fall back to C.
  static int _tonicStepIndex(KeySignature key) {
    if (!key.isStandard) return 0;
    const stepOfFifth = [0, 4, 1, 5, 2, 6, 3];
    return stepOfFifth[((key.fifths % 7) + 7) % 7];
  }

  /// The tonic's label parts for the `1=X` mark: the SMuFL accidental
  /// glyph name (null for a natural tonic) and the step letter —
  /// e.g. B♭ major → (`accidentalFlat`, `B`).
  static (String?, String) _tonicNameParts(KeySignature key) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    // Circle-of-fifths index of each step (F is one fifth below C).
    const fifthOfStep = [0, 2, 4, -1, 1, 3, 5];
    final step = _tonicStepIndex(key);
    final alter = key.isStandard
        ? (key.fifths - fifthOfStep[step]) ~/ 7
        : 0;
    final glyph = switch (alter) {
      1 => SmuflGlyph.accidentalSharp,
      -1 => SmuflGlyph.accidentalFlat,
      2 => SmuflGlyph.accidentalDoubleSharp,
      -2 => SmuflGlyph.accidentalDoubleFlat,
      _ => null,
    };
    return (glyph, letters[step]);
  }

  /// 盒模型放置：把 [glyph] 的墨迹中心对准 (cx, cy)。bBox 偏移随
  /// [scale] 缩放（GlyphPrimitive 的 position 始终是未缩放的锚点）。
  void _glyphCenteredAt(List<LayoutPrimitive> primitives, String glyph,
      double cx, double cy, SmuflMetadata meta, double scale,
      [String? elementId]) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph,
        Point(cx - (box.swX + box.width / 2) * scale,
            cy + (box.swY + box.neY) / 2 * scale),
        scale: scale,
        elementId: elementId));
  }

  /// 盒模型放置：[glyph] 墨迹右缘落在 rx、墨迹垂直中心落在 cy。
  void _glyphInkRightCenterAt(List<LayoutPrimitive> primitives, String glyph,
      double rx, double cy, SmuflMetadata meta, double scale,
      [String? elementId]) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph,
        Point(rx - box.neX * scale, cy + (box.swY + box.neY) / 2 * scale),
        scale: scale,
        elementId: elementId));
  }

  /// 盒模型放置：[glyph] 墨迹水平居中于 cx、墨迹底边落在 inkBottomY；
  /// 返回墨迹顶边 y，供记号继续向上层叠。
  double _glyphInkBottomAt(List<LayoutPrimitive> primitives, String glyph,
      double cx, double inkBottomY, SmuflMetadata meta, double scale,
      String? elementId) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph,
        Point(cx - (box.swX + box.width / 2) * scale,
            inkBottomY + box.swY * scale),
        scale: scale,
        elementId: elementId));
    return inkBottomY - box.height * scale;
  }

  /// The articulations jianpu draws (above the digit, v1).
  static const _jianpuArticulations = {
    Articulation.staccato,
    Articulation.accent,
    Articulation.marcato,
    Articulation.tenuto,
    Articulation.fermata,
  };
}
