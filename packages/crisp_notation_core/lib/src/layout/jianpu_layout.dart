/// Jianpu (numbered musical notation, 简谱) layout: renders a [Score]'s
/// pitches as movable-do digits on a single text row, producing the same
/// [ScoreLayout] primitives as the staff and tab engines, so the Flutter
/// renderer and the interaction layer work unchanged.
///
/// Coordinates (docs/JIANPU.md §4.1), in staff spaces: the digit baseline
/// sits at [digitBaseline] (y = 3.0); barlines span y = 1.0…4.0 (no staff
/// lines are drawn). Ties, slurs, dynamics and annotations go above the
/// digits; octave dots hug the digit; 减时线 (duration underlines) and
/// lyrics sit below.
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
import 'layout_settings.dart';
import 'score_layout.dart';

/// One placed rhythmic column: its digit centre x, written duration and
/// measure onset.
class _Col {
  final double x;
  final NoteDuration duration;
  final Fraction onset;
  final bool isRest;
  _Col(this.x, this.duration, this.onset, {this.isRest = false});
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

  static const double _barlineTop = 1.0;
  static const double _barlineBottom = 4.0;
  static const double _digitHalf = 0.55;

  /// Universal gap between the digit and any accessory symbol (octave dots,
  /// underlines, augmentation dots). All accessories sit this far from the
  /// digit edge, keeping visual spacing consistent across symbol types.
  static const double _symbolGap = 0.15;
  /// Half the BBox height of an augmentation dot (0.4 ss ÷ 2, from SMuFL).
  static const double _dotHalf = 0.20;
  /// Half the underline thickness (0.16 ÷ 2).
  static const double _lineHalf = 0.08;

  /// Upper octave dots: digit cap top (≈1.6) − _symbolGap − _dotHalf = 1.25.
  static const double _highDotY = 1.25;
  /// Lower octave dots (no underline): digitBaseline + _symbolGap + _dotHalf.
  static const double _lowDotY = 3.35;
  static const double _dotStep = 0.45;
  /// First 减时线 underline: digitBaseline + _symbolGap + _lineHalf = 3.23.
  static const double _underlineY = 3.23;
  static const double _underlineStep = 0.35;
  static const double _underlinePad = 0.45;
  static const double _dashY = 2.45;
  static const double _dashUnit = 1.15;
  static const double _dashLength = 0.85;

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
  /// [drawTimeSignature] false suppresses the leading time signature but
  /// still governs the underline (beam) grouping; [finalBarline] false
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
    bool drawTimeSignature = true,
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
    final lyricOf = {for (final l in score.lyrics) l.elementId: l};
    var deepestUnderline = 0.0;
    // Per-measure col lists and barline x, for cross-measure underlines.
    final measureColsList = <List<_Col>>[];
    final measureBarXs = <double>[];

    var key = score.keySignature;
    var time = score.timeSignature;

    void vline(double x, double thickness) {
      primitives.add(LinePrimitive(
          Point(x, _barlineTop), Point(x, _barlineBottom),
          thickness: thickness));
    }

    /// Estimated advance of a text run (core cannot measure text).
    double textWidth(String text, double size) => text.length * 0.52 * size;

    var x = s.leadingPadding;

    void drawKeyLabel(KeySignature k) {
      final text = '1=${_tonicName(k)}';
      final w = textWidth(text, 1.7);
      // Just above the digit baseline so the label is never mistaken for
      // a degree digit.
      primitives.add(TextPrimitive(
          text, Point(x + w / 2, digitBaseline - 0.15),
          size: 1.7));
      x += w + 0.7;
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

    double startRepeat(double at) {
      final thickX = at + s.thickBarlineThickness / 2;
      vline(thickX, s.thickBarlineThickness);
      final thinX = thickX +
          s.thickBarlineThickness / 2 +
          s.barlineSeparation +
          s.thinBarlineThickness / 2;
      vline(thinX, s.thinBarlineThickness);
      final dotX = thinX + s.thinBarlineThickness / 2 + 0.5;
      primitives.add(GlyphPrimitive(SmuflGlyph.repeatDot, Point(dotX, 2.2)));
      primitives.add(GlyphPrimitive(SmuflGlyph.repeatDot, Point(dotX, 2.8)));
      return dotX + 0.55;
    }

    double endRepeat(double at) {
      final dotX = at + 0.3;
      primitives.add(GlyphPrimitive(SmuflGlyph.repeatDot, Point(dotX, 2.2)));
      primitives.add(GlyphPrimitive(SmuflGlyph.repeatDot, Point(dotX, 2.8)));
      final thinX = dotX + 0.5 + s.thinBarlineThickness / 2;
      vline(thinX, s.thinBarlineThickness);
      final thickX = thickAfterThin(thinX);
      vline(thickX, s.thickBarlineThickness);
      return thickX + s.thickBarlineThickness / 2;
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
        // Dashed/dotted/tick/short degrade to a plain line in v1.
        default:
          vline(barX, s.thinBarlineThickness);
          return barX + s.thinBarlineThickness / 2;
      }
    }

    // --- leading furniture: the "1=X" key label, then the time signature.
    drawKeyLabel(key);
    if (time != null && drawTimeSignature) drawTimeSig(time);
    if (leadingWidth != null) x = max(x, leadingWidth);

    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];
      if (measure.keyChange != null) {
        key = measure.keyChange!;
        drawKeyLabel(key);
      }
      if (measure.timeChange != null) {
        time = measure.timeChange;
        if (drawTimeSignature) drawTimeSig(time!);
      }
      if (measure.startRepeat) x = startRepeat(x);
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
        final digitX =
            columnX == null ? x : measureContentStart + columnX;
        cols.add(_Col(digitX, duration, onset,
            isRest: element is! NoteElement));
        final id = element.id;

        final (dashes, augDots) = _durationMarks(duration);
        if (element is NoteElement) {
          // v1 degradation: a chord shows its highest pitch only.
          final shown = element.pitches
              .reduce((a, b) => a.midiNumber >= b.midiNumber ? a : b);
          final (digit, deviation, octaveDots) =
              _degreeOf(shown, key, tonicOctave);
          // Accidentals: a prefix is drawn when the pitch deviates from the
          // key differently than this (step, octave) did earlier in the bar.
          final memKey = (shown.step.index, shown.octave);
          final remembered = memory[memKey] ?? 0;
          if (deviation != remembered) {
            memory[memKey] = deviation;
            final prefix = _prefixFor(deviation);
            if (prefix != null && element.showAccidental != false) {
              primitives.add(TextPrimitive(
                  prefix, Point(digitX - 0.75, digitBaseline - 0.05),
                  size: 1.7, elementId: id));
            }
          }
          primitives.add(TextPrimitive(
              '$digit', Point(digitX, digitBaseline),
              size: digitSize, elementId: id));
          // Octave dots: n > 0 above, n < 0 below the digit.
          // For low dots, push below the deepest 减时线 underline this
          // element will receive (flagCount levels), so a 16th-note digit
          // with 2 low dots doesn't collide with the 2nd underline layer.
          final flagCount = duration.base.flagCount;
          final deepestUnderlineY =
              flagCount > 0
                  ? _underlineY + (flagCount - 1) * _underlineStep
                  : 0.0;
          // Push low dots below the deepest underline with the same
          // _symbolGap, so a 16th-note digit with 2 low dots doesn't
          // collide with the 2nd underline layer.
          final lowDotY = octaveDots < 0 && flagCount > 0
              ? max(_lowDotY,
                  deepestUnderlineY + _lineHalf + _symbolGap + _dotHalf)
              : _lowDotY;
          for (var d = 0; d < octaveDots.abs(); d++) {
            final y = octaveDots > 0
                ? _highDotY - d * _dotStep
                : lowDotY + d * _dotStep;
            _centeredGlyph(primitives, SmuflGlyph.augmentationDot, digitX, y,
                meta, id);
          }
          if (id != null) {
            anchorX[id] = digitX;
            anchorPitch[id] = shown;
          }
          // Articulations (staccato & co.) stack above the digit.
          var markY = 1.45;
          for (final art in element.articulations) {
            if (!_jianpuArticulations.contains(art)) continue;
            _centeredGlyph(
                primitives,
                SmuflGlyph.articulationGlyph(art, above: true),
                digitX,
                markY,
                meta,
                id);
            markY -= 0.8;
          }
        } else {
          // A rest is a plain 0 — no degree, dots or accidentals.
          primitives.add(TextPrimitive(
              '0', Point(digitX, digitBaseline),
              size: digitSize, elementId: id));
        }
        // 增时线 (dashes) and augmentation dots to the right of the digit.
        // Both use the universal _symbolGap from the digit's right edge.
        for (var d = 0; d < dashes; d++) {
          final from = digitX + _digitHalf + _symbolGap + d * _dashUnit;
          primitives.add(LinePrimitive(
              Point(from, _dashY), Point(from + _dashLength, _dashY),
              thickness: 0.18, elementId: id));
        }
        for (var d = 0; d < augDots; d++) {
          primitives.add(GlyphPrimitive(SmuflGlyph.augmentationDot,
              Point(digitX + _digitHalf + _symbolGap + d * 0.35, 2.9),
              elementId: id));
        }

        final lyric = id == null ? null : lyricOf[id];
        final advance = _advance(duration, s,
            dashes: dashes,
            lyricReserve: lyric?.text.length ?? 0,
            spacingStretch: spacingStretch);
        if (id != null) {
          regions.add(ElementRegion(
              id, Rectangle(digitX - 0.75, 1.1, max(advance - 0.4, 1.5), 3.6)));
        }
        x += advance;
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
      measureColsList.add(cols);

      var barX = max(x, startX + 2.0);
      if (measureWidths != null && m < measureWidths.length) {
        barX = max(barX, startX + measureWidths[m]);
      }
      if (barlineXs != null && m < barlineXs.length) {
        barX = max(barX, barlineXs[m]);
      }
      measureBarXs.add(barX);
      if (measure.volta != null) {
        const y = -0.3;
        primitives.add(LinePrimitive(
            Point(startX, y + 0.9), Point(startX, y),
            thickness: 0.14));
        primitives.add(LinePrimitive(
            Point(startX, y), Point(barX, y),
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
      final end = measure.endRepeat
          ? endRepeat(barX)
          : closingBarline(barX, barlineStyle);
      measureRegions.add(MeasureRegion(m, startX: startX, endX: barX));
      // Match the staff engine's advance: _addFinalBarline returns the right
      // ink edge of the closing barline with NO trailing barlineGap for the
      // default last measure (normal barline → final/thin barline), while
      // _addBarline/_addEndRepeat advance past the barline (with an extra
      // half-thickness for single-line styles) and add barlineGap. An
      // endRepeat's last line is thick, so its advance == right edge (like
      // finalBar).
      final isDefaultLast = isLast &&
          !measure.endRepeat &&
          measure.barline == BarlineStyle.normal;
      final effectiveStyle =
          measure.endRepeat ? BarlineStyle.finalBar : barlineStyle;
      x = isDefaultLast
          ? end
          : barlineAdvance(effectiveStyle, end) + s.barlineGap;
    }

    final width = x;

    // --- cross-measure underlines ---------------------------------------
    // When the last column of measure N and the first column of measure
    // N+1 are both eighth-or-shorter notes (not rests), draw the
    // connecting underline segments split at the barline — the standard
    // jianpu convention for beam groups that span a barline.
    for (var m = 0; m < measureColsList.length - 1; m++) {
      final colsN = measureColsList[m];
      final colsN1 = measureColsList[m + 1];
      if (colsN.isEmpty || colsN1.isEmpty) continue;
      final lastCol = colsN.last;
      final firstCol = colsN1.first;
      if (lastCol.isRest || firstCol.isRest) continue;
      final lastLevel = lastCol.duration.base.flagCount;
      final firstLevel = firstCol.duration.base.flagCount;
      if (lastLevel < 1 || firstLevel < 1) continue;
      final barX = measureBarXs[m];
      final maxLevel = min(lastLevel, firstLevel);
      for (var level = 1; level <= maxLevel; level++) {
        final y = _underlineY + (level - 1) * _underlineStep;
        primitives.add(LinePrimitive(
          Point(lastCol.x + _underlinePad, y),
          Point(barX - 0.15, y),
          thickness: 0.16,
        ));
        primitives.add(LinePrimitive(
          Point(barX + 0.15, y),
          Point(firstCol.x - _underlinePad, y),
          thickness: 0.16,
        ));
        deepestUnderline = max(deepestUnderline, y);
      }
    }

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
      final span = b - a;
      primitives.add(CurvePrimitive(
        Point(a + 0.55, 1.35),
        Point(a + span * 0.25, 0.75),
        Point(b - span * 0.25, 0.75),
        Point(b - 0.55, 1.35),
        thickness: 0.12,
      ));
    }
    for (final slur in score.slurs) {
      final a = anchorX[slur.startId], b = anchorX[slur.endId];
      if (a == null || b == null || b <= a) continue;
      final span = b - a;
      final lift = max(0.7, span * 0.15);
      primitives.add(CurvePrimitive(
        Point(a + 0.4, 1.3),
        Point(a + span * 0.3, 1.3 - lift),
        Point(b - span * 0.3, 1.3 - lift),
        Point(b - 0.4, 1.3),
        thickness: 0.14,
      ));
    }
    for (final dynamic_ in score.dynamics) {
      final at = anchorX[dynamic_.elementId];
      if (at == null) continue;
      primitives.add(TextPrimitive(
          dynamic_.level.name, Point(at, 0.5),
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
      final lyricY = max(5.0, deepestUnderline + 1.9);
      for (final lyric in score.lyrics) {
        final at = anchorX[lyric.elementId];
        if (at == null) continue;
        primitives.add(TextPrimitive(
            lyric.text, Point(at, lyricY),
            size: s.lyricSize));
      }
    }

    // Ink bounds from the actual primitives (the tab engine's approach), so
    // above/below ink is never clipped.
    var minY = _barlineTop, maxY = _barlineBottom;
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
  /// columns share one first-level line per beat window (`beamGroups`, the
  /// same source as staff beaming rule 7; a quarter-note window when
  /// unmetered). In an even-beat quarter-meter (4/4, 2/4) adjacent beat
  /// runs within the same half measure merge — the same convention as the
  /// staff engine's all-eighth merge, broadened to any beamable run, which
  /// is how mixed eighth/sixteenth runs are underlined in published jianpu.
  /// Deeper levels cover only the columns that need them.
  /// Returns the deepest underline y drawn (0 when none).
  double _layoutUnderlines(
      List<LayoutPrimitive> primitives, List<_Col> cols, TimeSignature? time) {
    int levelOf(_Col c) => c.duration.base.flagCount;

    final boundaries = <Fraction>[];
    if (time != null) {
      var acc = Fraction.zero;
      for (final g in time.beamGroups()) {
        boundaries.add(acc);
        acc += g;
      }
    }
    int windowOf(Fraction onset) {
      if (time == null) return (onset.toDouble() * 4).floor();
      var idx = 0;
      for (var b = 0; b < boundaries.length; b++) {
        if (onset < boundaries[b]) break;
        idx = b;
      }
      return idx;
    }

    final runs = <List<int>>[];
    List<int>? current;
    int? currentWindow;
    for (var i = 0; i < cols.length; i++) {
      if (levelOf(cols[i]) >= 1) {
        final w = windowOf(cols[i].onset);
        if (current != null && w == currentWindow) {
          current.add(i);
        } else {
          current = [i];
          currentWindow = w;
          runs.add(current);
        }
      } else {
        current = null;
        currentWindow = null;
      }
    }
    if (time != null && time.beatUnit == 4 && time.beats.isEven) {
      int halfOf(Fraction onset) => (onset.toDouble() * 2).floor();
      for (var i = 0; i < runs.length - 1;) {
        final a = runs[i], b = runs[i + 1];
        if (b.first == a.last + 1 &&
            halfOf(cols[a.first].onset) == halfOf(cols[b.first].onset)) {
          a.addAll(b);
          runs.removeAt(i + 1);
        } else {
          i++;
        }
      }
    }

    var deepest = 0.0;
    for (final run in runs) {
      final maxLevel = run.map((i) => levelOf(cols[i])).reduce(max);
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
          final y = _underlineY + (level - 1) * _underlineStep;
          primitives.add(LinePrimitive(
            Point(cols[run[k]].x - _underlinePad, y),
            Point(cols[run[l]].x + _underlinePad, y),
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

  /// The advance for one column: the staff engine's logarithmic ideal,
  /// floored by the dash cells (half/whole notes genuinely occupy more
  /// horizontal room — the anchor for mixed-notation alignment) and by the
  /// lyric syllable's estimated width. [spacingStretch] multiplies the
  /// ideal (≥ 1.0), matching the staff engine so a mixed system widens
  /// uniformly.
  double _advance(NoteDuration duration, LayoutSettings s,
      {required int dashes,
      required int lyricReserve,
      double spacingStretch = 1.0}) {
    final ideal = max(
        2.0,
        (s.spacingBase +
                s.spacingPerLog2 *
                    (4 + duration.base.log2Value + _dotLog2[duration.dots])) *
            spacingStretch);
    final dashFloor =
        dashes > 0 ? _digitHalf + 0.25 + dashes * _dashUnit + 0.7 : 0.0;
    final lyricFloor = lyricReserve * 0.52 * s.lyricSize;
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
    final dots =
        (pitch.diatonicIndex - (tonicOctave * 7 + tonicStep)) ~/ 7;
    return (digit, deviation, dots);
  }

  /// The prefix text for a deviation from the key (±1 ♯/♭, ±2 doubled).
  /// 0 → ♮ (only drawn when the in-measure memory differs, i.e., when
  /// returning to the key after an earlier accidental in the same bar).
  static String? _prefixFor(int deviation) => switch (deviation) {
        1 => '♯',
        -1 => '♭',
        2 => '♯♯',
        -2 => '♭♭',
        0 => '♮',
        _ => null,
      };

  /// The diatonic step index (C=0…B=6) of [key]'s major tonic — the same
  /// circle-of-fifths derivation the staff engine's shape notes use.
  /// Non-standard signatures fall back to C.
  static int _tonicStepIndex(KeySignature key) {
    if (!key.isStandard) return 0;
    const stepOfFifth = [0, 4, 1, 5, 2, 6, 3];
    return stepOfFifth[((key.fifths % 7) + 7) % 7];
  }

  /// The tonic's display name for the `1=X` label, accidentals first
  /// (`1=♭B`, `1=♯F`).
  static String _tonicName(KeySignature key) {
    const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    // Circle-of-fifths index of each step (F is one fifth below C).
    const fifthOfStep = [0, 2, 4, -1, 1, 3, 5];
    final step = _tonicStepIndex(key);
    final alter = key.isStandard
        ? (key.fifths - fifthOfStep[step]) ~/ 7
        : 0;
    const accidentals = {-2: '♭♭', -1: '♭', 0: '', 1: '♯', 2: '♯♯'};
    return '${accidentals[alter]}${letters[step]}';
  }

  /// Draws [glyph] centred horizontally on [x] with its origin (baseline)
  /// at [y].
  void _centeredGlyph(List<LayoutPrimitive> primitives, String glyph,
      double x, double y, SmuflMetadata meta, String? elementId) {
    final box = meta.bBoxOf(glyph);
    primitives.add(GlyphPrimitive(
        glyph, Point(x - box.width / 2 - box.swX, y),
        elementId: elementId));
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
