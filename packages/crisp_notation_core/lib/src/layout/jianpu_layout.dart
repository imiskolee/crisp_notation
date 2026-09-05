/// Jianpu (numbered musical notation, 简谱) layout: renders a [Score]'s
/// pitches as movable-do digits on a single text row, producing the same
/// [ScoreLayout] primitives as the staff and tab engines, so the Flutter
/// renderer and the interaction layer work unchanged.
///
/// Coordinates (docs/JIANPU.md §4.1), in staff spaces: the digit baseline
/// sits at [JianpuLayoutEngine.digitBaseline] (y = 3.0); barlines span
/// slightly beyond the digit ink box — from the +1 octave-dot centre
/// ([JianpuLayoutEngine.barlineTop]) down to the first 减时线 underline
/// ([JianpuLayoutEngine.barlineBottom]), whether or not those marks are
/// actually present. No staff lines and no line-start barline are drawn:
/// barlines close measures only. Ties, slurs, tuplet brackets, dynamics and
/// annotations go above the digits; octave dots hug the digit; 减时线
/// (duration underlines) and lyrics sit below.
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

part 'jianpu_barlines.dart';
part 'jianpu_furniture.dart';
part 'jianpu_notes.dart';
part 'jianpu_overlays.dart';

// ---------------------------------------------------------------------------
// Top-level helpers (library-private, no instance state).
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Box-model constants (library-private; [JianpuLayoutEngine] re-exports the
// public subset).
// ---------------------------------------------------------------------------

/// Baseline y of the digit row, in staff spaces.
const double _digitBaseline = 3.0;

/// Em size of a degree digit, in staff spaces.
const double _digitSize = 2.0;

/// Ink top of a degree digit (cap height ≈ 0.68 em above the baseline).
const double _digitTop = 1.64;

/// Half the typical ink width of a degree digit.
const double _digitInkHalf = 0.45;

/// Vertical centre of the digit ink box — the 增时线 height.
const double _digitMid = 2.32; // (digitTop + digitBaseline) / 2

/// Universal gap between the digit ink box and any accessory symbol.
const double _symbolGap = 0.15;

/// Unified dot metric: SMuFL augmentationDot and repeatDot share ±0.2 bBox.
const double _dotHalf = 0.20;

/// Stacked-octave-dot pitch: 2·_dotHalf + 0.05 层叠净距.
const double _dotStep = 0.45;

/// Half the underline thickness (0.16 ÷ 2).
const double _lineHalf = 0.08;

/// First 减时线 underline: digitBaseline + _symbolGap + _lineHalf = 3.23.
const double _underlineY = 3.23;
const double _underlineStep = 0.35;
const double _underlinePad = 0.45;

/// Top of a jianpu barline: the +1 octave dot's centre (y = 1.29).
const double _barlineTop = _digitTop - _symbolGap - _dotHalf;

/// Bottom of a jianpu barline: the first 减时线 underline (y = 3.23).
const double _barlineBottom = _underlineY;

/// 连音符括线的高度.
const double _tupletY = 0.62;

/// 连音符括线端钩向数字方向的下折长度.
const double _tupletHook = 0.45;

/// 连音符比例数字的字号.
const double _tupletDigitSize = 1.15;

/// 增时线长度 ≈ 一个数字的墨迹宽度.
const double _dashLength = 1.1;

/// Scale for SMuFL articulation marks.
const double _articScale = 0.5;

/// Scale for SMuFL accidental prefixes.
const double _accidentalScale = 0.5;

/// 反复圆点的两个中心.
const double _repeatDotHigh = 1.95;
const double _repeatDotLow = 2.65;

/// 附点中心高度.
const double _augDotY = 2.80;

/// 和弦数字的字号系数.
const double _chordDigitFactor = 0.8;

/// 和弦叠放数字之间的纵向净距.
const double _chordGap = 0.12;

/// log2 of the augmentation-dot multipliers.
const _dotLog2 = [0.0, 0.5849625007211562, 0.8073549220576041];

/// The articulations jianpu draws (above the digit, v1).
const _jianpuArticulations = {
  Articulation.staccato,
  Articulation.accent,
  Articulation.marcato,
  Articulation.tenuto,
  Articulation.fermata,
};

// ---------------------------------------------------------------------------
// _Col: one placed rhythmic column.
// ---------------------------------------------------------------------------

/// One placed rhythmic column: its digit centre x, written duration and
/// measure onset.
class _Col {
  final double x;
  final NoteDuration duration;
  final Fraction onset;
  final bool isRest;

  /// Ink the underline must cover past the digit's right edge.
  final double dotExt;

  /// Bottom of the column's note ink.
  final double bottom;
  _Col(this.x, this.duration, this.onset,
      {this.isRest = false, this.dotExt = 0, this.bottom = 3.0});
}

// ---------------------------------------------------------------------------
// JianpuLayoutEngine: public entry point.
// ---------------------------------------------------------------------------

/// Lays a [Score] out as jianpu (numbered notation), major keys only (v1).
///
/// The signature mirrors [TabLayoutEngine.layout]: [leadingWidth] and
/// [barlineXs] pin the leading and each measure's barline to absolute x
/// positions so a jianpu staff can align barline-for-barline with a paired
/// staff of another notation. [tonicOctave] fixes which octave of the tonic
/// is the undotted reference (default 4 — the middle register).
class JianpuLayoutEngine {
  /// Creates a jianpu layout engine.
  const JianpuLayoutEngine();

  /// Baseline y of the digit row, in staff spaces.
  static const double digitBaseline = _digitBaseline;

  /// Em size of a degree digit, in staff spaces.
  static const double digitSize = _digitSize;

  /// Ink top of a degree digit (cap height ≈ 0.68 em above the baseline).
  static const double digitTop = _digitTop;

  /// Top of a jianpu barline.
  static const double barlineTop = _barlineTop;

  /// Bottom of a jianpu barline.
  static const double barlineBottom = _barlineBottom;

  /// Lays [score] out as jianpu.
  ///
  /// See the class-level docs for the cross-staff alignment contract and
  /// the [drawTimeSignature] / [drawKeyLabelText] flags.
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
  }) =>
      _JianpuBuilder(
        score: score,
        s: settings,
        leadingWidth: leadingWidth,
        measureWidths: measureWidths,
        forcedColumns: forcedColumns,
        barlineXs: barlineXs,
        spacingStretch: spacingStretch,
        drawTimeSignature: drawTimeSignature,
        drawKeyLabelText: drawKeyLabelText,
        finalBarline: finalBarline,
        tonicOctave: tonicOctave,
      ).build();

  // ---- static helpers (no instance state) ----

  /// 增时线/附点 split for a duration.
  static (int dashes, int augDots) _durationMarks(NoteDuration duration) {
    if (duration.base.log2Value > -2) {
      final (num, den) = duration.fraction;
      return (max(0, (num * 4 / den).round() - 1), 0);
    }
    return (0, duration.dots);
  }

  /// Number of quarter-rest "0" units for a rest.
  static int _longRestQuarterUnits(NoteDuration duration) {
    if (duration.base.log2Value <= -2) return 1;
    final (num, den) = duration.fraction;
    return (num * 4 / den).round();
  }

  /// Pitch → (digit 1..7, deviation, octave-dot count).
  static (int, int, int) _degreeOf(
      Pitch pitch, KeySignature key, int tonicOctave) {
    final tonicStep = _tonicStepIndex(key);
    final digit = (pitch.step.index - tonicStep + 7) % 7 + 1;
    final deviation = pitch.alter - key.alterFor(pitch.step);
    final dots =
        ((pitch.diatonicIndex - (tonicOctave * 7 + tonicStep)) / 7).floor();
    return (digit, deviation, dots);
  }

  /// The diatonic step index (C=0…B=6) of [key]'s major tonic.
  static int _tonicStepIndex(KeySignature key) {
    if (!key.isStandard) return 0;
    const stepOfFifth = [0, 4, 1, 5, 2, 6, 3];
    return stepOfFifth[((key.fifths % 7) + 7) % 7];
  }

  /// The tonic's label parts for the `1=X` mark.
  static (String?, String) _tonicNameParts(KeySignature key) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const fifthOfStep = [0, 2, 4, -1, 1, 3, 5];
    final step = _tonicStepIndex(key);
    final alter = key.isStandard ? (key.fifths - fifthOfStep[step]) ~/ 7 : 0;
    final glyph = switch (alter) {
      1 => SmuflGlyph.accidentalSharp,
      -1 => SmuflGlyph.accidentalFlat,
      2 => SmuflGlyph.accidentalDoubleSharp,
      -2 => SmuflGlyph.accidentalDoubleFlat,
      _ => null,
    };
    return (glyph, letters[step]);
  }
}

// ---------------------------------------------------------------------------
// _JianpuBuilder: holds all mutable layout state; extension methods in the
// part files provide the rendering logic.
// ---------------------------------------------------------------------------

/// Mutable accumulator that walks the score and builds the [ScoreLayout].
/// All state that was previously captured by nested closures in the old
/// monolithic `layout()` lives here as fields, so extension methods in the
/// part files can access it directly.
class _JianpuBuilder {
  // --- immutable parameters ---
  final Score score;
  final LayoutSettings s;
  final double? leadingWidth;
  final List<double>? measureWidths;
  final List<Map<Fraction, double>>? forcedColumns;
  final List<double>? barlineXs;
  final double spacingStretch;
  final bool drawTimeSignature;
  final bool drawKeyLabelText;
  final bool finalBarline;
  final int tonicOctave;

  // --- derived getters ---
  SmuflMetadata get meta => s.metadata;

  // --- mutable output accumulators ---
  final List<LayoutPrimitive> primitives = [];
  final List<ElementRegion> regions = [];
  final List<MeasureRegion> measureRegions = [];

  // --- note lookup tables (populated during the element loop) ---
  final Map<String, double> anchorX = {};
  final Map<String, Pitch> anchorPitch = {};
  final Map<String, double> topOf = {};
  late final Map<String, Lyric> lyricOf = {
    for (final l in score.lyrics) l.elementId: l
  };

  // --- mutable tracking variables ---
  double deepestUnderline = 0.0;
  double lowestInk = _digitBaseline;
  KeySignature key;
  TimeSignature? time;
  double x = 0;
  late double quarterCell;

  _JianpuBuilder({
    required this.score,
    required this.s,
    this.leadingWidth,
    this.measureWidths,
    this.forcedColumns,
    this.barlineXs,
    this.spacingStretch = 1.0,
    this.drawTimeSignature = false,
    this.drawKeyLabelText = false,
    this.finalBarline = true,
    this.tonicOctave = 4,
  })  : key = score.keySignature,
        time = score.timeSignature,
        x = s.leadingPadding;

  /// The advance for one column: the staff engine's logarithmic ideal,
  /// floored by the dash cells and by the lyric syllable's estimated width.
  double _advance(NoteDuration duration,
      {required int dashes,
      required int lyricReserve,
      double quarterCell = 0}) {
    final ideal = max(
        2.0,
        (s.spacingBase +
                s.spacingPerLog2 *
                    (4 + duration.base.log2Value + _dotLog2[duration.dots])) *
            spacingStretch);
    final dashFloor =
        dashes > 0 && quarterCell > 0 ? (dashes + 1) * quarterCell : 0.0;
    final lyricFloor =
        lyricReserve > 0 ? (lyricReserve + 1.0) * s.lyricSize : 0.0;
    return max(ideal, max(dashFloor, lyricFloor));
  }

  /// 变音记号前缀从数字中心向左的外推量.
  double _prefixOverhang(int deviation) {
    final w = switch (deviation) {
      1 => meta.bBoxOf(SmuflGlyph.accidentalSharp).width * _accidentalScale,
      -1 => meta.bBoxOf(SmuflGlyph.accidentalFlat).width * _accidentalScale,
      2 =>
        2 * meta.bBoxOf(SmuflGlyph.accidentalSharp).width * _accidentalScale +
            _symbolGap,
      -2 =>
        meta.bBoxOf(SmuflGlyph.accidentalDoubleFlat).width * _accidentalScale,
      0 => meta.bBoxOf(SmuflGlyph.accidentalNatural).width * _accidentalScale,
      _ => 0.0,
    };
    return w > 0 ? _digitInkHalf + _symbolGap + w : 0.0;
  }

  /// 变音记号前缀：SMuFL 字形而非文本.
  void _drawAccidentalPrefix(int deviation, double digitX, String? elementId,
      {double cy = _digitMid, double inkHalf = _digitInkHalf}) {
    final rx = digitX - inkHalf - _symbolGap;
    switch (deviation) {
      case 1:
        _glyphInkRightCenterAt(
            SmuflGlyph.accidentalSharp, rx, cy, _accidentalScale, elementId);
      case -1:
        _glyphInkRightCenterAt(
            SmuflGlyph.accidentalFlat, rx, cy, _accidentalScale, elementId);
      case 2:
        final w =
            meta.bBoxOf(SmuflGlyph.accidentalSharp).width * _accidentalScale;
        _glyphInkRightCenterAt(
            SmuflGlyph.accidentalSharp, rx, cy, _accidentalScale, elementId);
        _glyphInkRightCenterAt(SmuflGlyph.accidentalSharp, rx - w - _symbolGap,
            cy, _accidentalScale, elementId);
      case -2:
        _glyphInkRightCenterAt(SmuflGlyph.accidentalDoubleFlat, rx, cy,
            _accidentalScale, elementId);
      case 0:
        _glyphInkRightCenterAt(
            SmuflGlyph.accidentalNatural, rx, cy, _accidentalScale, elementId);
    }
  }

  /// 盒模型放置：墨迹中心对准 (cx, cy).
  void _glyphCenteredAt(String glyph, double cx, double cy, double scale,
      [String? elementId]) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph,
        Point(cx - (box.swX + box.width / 2) * scale,
            cy + (box.swY + box.neY) / 2 * scale),
        scale: scale,
        elementId: elementId));
  }

  /// 盒模型放置：墨迹右缘落在 rx、墨迹垂直中心落在 cy.
  void _glyphInkRightCenterAt(String glyph, double rx, double cy, double scale,
      [String? elementId]) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(glyph,
        Point(rx - box.neX * scale, cy + (box.swY + box.neY) / 2 * scale),
        scale: scale, elementId: elementId));
  }

  /// 盒模型放置：墨迹水平居中于 cx、墨迹底边落在 inkBottomY；返回墨迹顶边 y.
  double _glyphInkBottomAt(String glyph, double cx, double inkBottomY,
      double scale, String? elementId) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph,
        Point(cx - (box.swX + box.width / 2) * scale,
            inkBottomY + box.swY * scale),
        scale: scale,
        elementId: elementId));
    return inkBottomY - box.height * scale;
  }

  /// The main orchestration loop.  Calls extension methods in the part files
  /// for barlines, furniture, note rendering, and post-pass overlays.
  ScoreLayout build() {
    // --- leading furniture ---
    if (drawKeyLabelText) drawKeyLabel(key);
    if (time != null && drawTimeSignature) drawTimeSig(time!);
    if (leadingWidth != null) x = max(x, leadingWidth!);

    quarterCell = _advance(NoteDuration.quarter, dashes: 0, lyricReserve: 0);

    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];

      // 变调/变拍是内容而非装饰.
      if (measure.keyChange != null) {
        key = measure.keyChange!;
        drawKeyLabel(key);
      }
      if (measure.timeChange != null) {
        time = measure.timeChange;
        drawTimeSig(time!);
      }

      // GB/T 46845-2025 §5.8.2.2b/c: repeat handling.
      final prevHadEndRepeat = m > 0 && score.measures[m - 1].endRepeat;
      final nextHasStartRepeat =
          m < score.measures.length - 1 && score.measures[m + 1].startRepeat;
      final combinedRepeatWithNext = measure.endRepeat && nextHasStartRepeat;
      if (measure.startRepeat && m > 0 && !prevHadEndRepeat) {
        x = startRepeat(x);
      }
      final startX = x;

      // §2.9 cross-staff gridding.
      final columns = forcedColumns != null && m < forcedColumns!.length
          ? forcedColumns![m]
          : null;
      final measureContentStart = x;

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

        final (dashes, augDots) = JianpuLayoutEngine._durationMarks(duration);
        var columnBottom = _digitBaseline;

        if (element is NoteElement) {
          final r =
              renderNoteElement(element, duration, digitX, columnX, memory, id);
          digitX = r.digitX;
          columnBottom = r.columnBottom;
        } else {
          renderRestElement(duration, digitX, id);
        }

        cols.add(_Col(digitX, duration, onset,
            isRest: element is! NoteElement,
            bottom: columnBottom,
            dotExt: augDots > 0
                ? _digitInkHalf +
                    _symbolGap +
                    (augDots - 1) * (2 * _dotHalf + _symbolGap) +
                    2 * _dotHalf
                : 0));

        final isLongRest = element is! NoteElement &&
            JianpuLayoutEngine._longRestQuarterUnits(duration) > 1;
        if (!isLongRest) {
          renderDurationMarks(digitX, dashes, augDots, id);
        }

        final lyric = id == null ? null : lyricOf[id];
        final advance = isLongRest
            ? JianpuLayoutEngine._longRestQuarterUnits(duration) *
                _advance(NoteDuration.quarter,
                    dashes: 0, lyricReserve: lyric?.text.length ?? 0)
            : _advance(duration,
                dashes: dashes,
                lyricReserve: lyric?.text.length ?? 0,
                quarterCell: quarterCell);
        if (id != null) {
          final regionTop = min(1.1, (topOf[id] ?? _digitTop) - 0.2);
          final regionBottom = max(4.7, columnBottom + 0.3);
          regions.add(ElementRegion(
              id,
              Rectangle(digitX - 0.75, regionTop, max(advance - 0.4, 1.5),
                  regionBottom - regionTop)));
        }
        x = digitX + advance;
        onset += effective;
      }

      // §2.9: advance to the shared measure-end column.
      if (columns != null && columns.isNotEmpty) {
        final measureEnd = columns.keys.reduce((a, b) => a > b ? a : b);
        final endX = columns[measureEnd];
        if (endX != null) x = max(x, measureContentStart + endX);
      }

      // 减时线.
      deepestUnderline = max(deepestUnderline, layoutUnderlines(cols));

      // Barline position.
      var barX = max(x, startX + 2.0);
      if (measureWidths != null && m < measureWidths!.length) {
        barX = max(barX, startX + measureWidths![m]);
      }
      if (barlineXs != null && m < barlineXs!.length) {
        barX = max(barX, barlineXs![m]);
      }
      if (measure.volta != null) {
        drawVolta(startX, barX, measure.volta!);
      }

      // Closing barline.
      final isLast = m == score.measures.length - 1;
      final barlineStyle = isLast && measure.barline == BarlineStyle.normal
          ? (finalBarline ? BarlineStyle.finalBar : BarlineStyle.normal)
          : measure.barline;
      final end = combinedRepeatWithNext
          ? combinedRepeat(barX)
          : measure.endRepeat
              ? endRepeat(barX)
              : closingBarline(barX, barlineStyle);
      measureRegions.add(MeasureRegion(m, startX: startX, endX: barX));

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

    // --- post-passes ---
    layoutTies();
    layoutSlurs();
    layoutTuplets();
    layoutDynamics();
    layoutAnnotations();
    layoutLyrics();

    return finalizeInkBounds();
  }
}
