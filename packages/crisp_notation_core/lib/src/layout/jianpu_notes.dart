part of 'jianpu_layout.dart';

// Note, chord, rest, and duration-mark rendering — the largest block of the
// original monolithic layout().  Extracted so the main build() loop reads as
// orchestration and the rendering logic can be tested in isolation.

/// Result of rendering a note element: the (possibly shifted) digit centre x,
/// the column's bottom ink edge (for underline/lyric clearance), and the
/// pre-accessory top cursor (for tie/slur endpoint placement).
class _NoteRender {
  final double digitX;
  final double columnBottom;
  final double topCursor;
  _NoteRender(this.digitX, this.columnBottom, this.topCursor);
}

extension _JianpuNotes on _JianpuBuilder {
  /// Renders a [NoteElement] (single note or chord) at [digitX], drawing the
  /// digit(s), accidental prefixes, octave dots, technique marks, articulations,
  /// and ornaments.  Sets [anchorX], [anchorPitch], [topOf], and [lowestInk]
  /// on the builder.  Returns the placed digit x, column bottom, and
  /// pre-accessory top cursor.
  _NoteRender renderNoteElement(
    NoteElement element,
    NoteDuration duration,
    double digitX,
    double? columnX,
    Map<(int, int), int> memory,
    String? id,
  ) {
    if (element.pitches.length > 1) {
      final r = _renderChord(element, duration, digitX, columnX, memory, id);
      if (id != null) topOf[id] = r.topCursor;
      _renderNoteAccessories(element, digitX, r.topCursor, id);
      return r;
    }
    final r = _renderSingleNote(element, duration, digitX, columnX, memory, id);
    if (id != null) topOf[id] = r.topCursor;
    _renderNoteAccessories(element, digitX, r.topCursor, id);
    return r;
  }

  /// Renders a chord: digits stacked vertically, accidentals per note,
  /// octave dots on outermost notes only.
  _NoteRender _renderChord(
    NoteElement element,
    NoteDuration duration,
    double digitX,
    double? columnX,
    Map<(int, int), int> memory,
    String? id,
  ) {
    var topCursor = _digitTop;
    final sorted = [...element.pitches]
      ..sort((a, b) => b.midiNumber.compareTo(a.midiNumber));
    final degrees = [
      for (final p in sorted) JianpuLayoutEngine._degreeOf(p, key, tonicOctave)
    ];
    const chordSize = _digitSize * _chordDigitFactor;
    final cap = 0.68 * chordSize;
    final n = sorted.length;
    final stackH = n * cap + (n - 1) * _chordGap;
    final stackTop = _digitMid - stackH / 2;
    final stackBottom = _digitMid + stackH / 2;

    final drawDevs = <int, int>{};
    var overhang = 0.0;
    for (var mi = 0; mi < n; mi++) {
      final dev = degrees[mi].$2;
      final memKey = (sorted[mi].step.index, sorted[mi].octave);
      if (dev == (memory[memKey] ?? 0)) continue;
      memory[memKey] = dev;
      if (element.showAccidental == false) continue;
      drawDevs[mi] = dev;
      overhang = max(overhang, _prefixOverhang(dev));
    }
    if (columnX == null) digitX += overhang;
    const chordInkHalf = _digitInkHalf * _chordDigitFactor;
    for (var mi = 0; mi < n; mi++) {
      final baseline = stackBottom - (n - 1 - mi) * (cap + _chordGap);
      primitives.add(TextPrimitive('${degrees[mi].$1}', Point(digitX, baseline),
          size: chordSize, elementId: id));
      final dev = drawDevs[mi];
      if (dev != null) {
        _drawAccidentalPrefix(dev, digitX, id,
            cy: baseline - cap / 2, inkHalf: chordInkHalf);
      }
    }
    topCursor = stackTop;
    var columnBottom = stackBottom;

    if (degrees.first.$3 > 0) {
      var cy = stackTop - _symbolGap - _dotHalf;
      for (var d = 0; d < degrees.first.$3; d++) {
        _glyphCenteredAt(SmuflGlyph.augmentationDot, digitX, cy, 1.0, id);
        cy -= _dotStep;
      }
      topCursor = cy + _dotStep - _dotHalf;
    }
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
        _glyphCenteredAt(SmuflGlyph.augmentationDot, digitX, cy, 1.0, id);
        cy += _dotStep;
      }
      columnBottom = max(columnBottom, cy - _dotStep + _dotHalf);
    }
    if (id != null) {
      anchorX[id] = digitX;
      anchorPitch[id] = sorted.first;
    }
    lowestInk = max(lowestInk, columnBottom);
    return _NoteRender(digitX, columnBottom, topCursor);
  }

  /// Renders a single note: digit, accidental prefix, octave dots.
  _NoteRender _renderSingleNote(
    NoteElement element,
    NoteDuration duration,
    double digitX,
    double? columnX,
    Map<(int, int), int> memory,
    String? id,
  ) {
    var topCursor = _digitTop;
    final shown = element.pitches.first;
    final (digit, deviation, octaveDots) =
        JianpuLayoutEngine._degreeOf(shown, key, tonicOctave);
    final memKey = (shown.step.index, shown.octave);
    final remembered = memory[memKey] ?? 0;
    if (deviation != remembered) {
      memory[memKey] = deviation;
      if (element.showAccidental != false) {
        if (columnX == null) {
          digitX += _prefixOverhang(deviation);
        }
        _drawAccidentalPrefix(deviation, digitX, id);
      }
    }
    primitives.add(TextPrimitive('$digit', Point(digitX, _digitBaseline),
        size: _digitSize, elementId: id));
    if (octaveDots > 0) {
      var cy = _digitTop - _symbolGap - _dotHalf;
      for (var d = 0; d < octaveDots; d++) {
        _glyphCenteredAt(SmuflGlyph.augmentationDot, digitX, cy, 1.0, id);
        cy -= _dotStep;
      }
      topCursor = cy + _dotStep - _dotHalf;
    } else if (octaveDots < 0) {
      final flagCount = duration.base.flagCount;
      final belowCursor = flagCount > 0
          ? _underlineY + (flagCount - 1) * _underlineStep + _lineHalf
          : _digitBaseline;
      var cy = belowCursor + _symbolGap + _dotHalf;
      for (var d = 0; d < -octaveDots; d++) {
        _glyphCenteredAt(SmuflGlyph.augmentationDot, digitX, cy, 1.0, id);
        cy += _dotStep;
      }
    }
    if (id != null) {
      anchorX[id] = digitX;
      anchorPitch[id] = shown;
    }
    return _NoteRender(digitX, _digitBaseline, topCursor);
  }

  /// Draws technique marks (slides), articulations, ornaments, and remaining
  /// technique marks above the note.  Modifies the local [topCursor] which
  /// starts at [initialTop].
  void _renderNoteAccessories(
    NoteElement element,
    double digitX,
    double initialTop,
    String? id,
  ) {
    var topCursor = initialTop;
    final techniques = element.techniques;

    // 装饰滑音（GB 7.6 主从滑音）
    if (techniques.contains(TechniqueMark.slideUp)) {
      topCursor = _glyphInkBottomAt(SmuflGlyph.brassScoop, digitX,
          topCursor - _symbolGap, _articScale, id);
    }
    if (techniques.contains(TechniqueMark.slideDown)) {
      topCursor = _glyphInkBottomAt(SmuflGlyph.brassFallLipShort, digitX,
          topCursor - _symbolGap, _articScale, id);
    }
    if (techniques.contains(TechniqueMark.slideReturn)) {
      final sW = meta.bBoxOf(SmuflGlyph.brassScoop).width * _articScale;
      final fW = meta.bBoxOf(SmuflGlyph.brassFallLipShort).width * _articScale;
      final inkBottom = topCursor - _symbolGap;
      final totalW = sW + _symbolGap + fW;
      final topA = _glyphInkBottomAt(SmuflGlyph.brassScoop,
          digitX - totalW / 2 + sW / 2, inkBottom, _articScale, id);
      final topB = _glyphInkBottomAt(SmuflGlyph.brassFallLipShort,
          digitX + totalW / 2 - fW / 2, inkBottom, _articScale, id);
      topCursor = min(topA, topB);
    }
    // 音符记号（断音、重音、保持音等）
    for (final art in element.articulations) {
      if (!_jianpuArticulations.contains(art)) continue;
      final inkBottom = topCursor - _symbolGap;
      if (art == Articulation.staccato) {
        const size = 1.0;
        primitives.add(TextPrimitive('▼', Point(digitX, inkBottom),
            size: size, elementId: id));
        topCursor = inkBottom - 0.72 * size;
      } else {
        topCursor = _glyphInkBottomAt(
            SmuflGlyph.articulationGlyph(art, above: true),
            digitX,
            inkBottom,
            _articScale,
            id);
      }
    }
    // 装饰音（颤音/波音/回音等）
    final ornament = element.ornament;
    if (ornament != null) {
      topCursor = _glyphInkBottomAt(SmuflGlyph.ornamentGlyph(ornament), digitX,
          topCursor - _symbolGap, _articScale, id);
      final alter = ornament.trillAccidentalAlter;
      if (alter != null) {
        final accGlyph = switch (alter) {
          1 => SmuflGlyph.accidentalSharp,
          -1 => SmuflGlyph.accidentalFlat,
          _ => SmuflGlyph.accidentalNatural,
        };
        topCursor = _glyphInkBottomAt(accGlyph, digitX, topCursor - _symbolGap,
            _accidentalScale * 0.7, id);
      }
    }
    // 其余技法记号
    for (final mark in TechniqueMark.values) {
      if (!techniques.contains(mark)) continue;
      final inkBottom = topCursor - _symbolGap;
      switch (mark) {
        case TechniqueMark.slideUp:
        case TechniqueMark.slideDown:
        case TechniqueMark.slideReturn:
          break;
        case TechniqueMark.vibrato:
          topCursor = _glyphInkBottomAt(
              SmuflGlyph.wiggleVibratoWide, digitX, inkBottom, _articScale, id);
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
  }

  /// Renders a rest element: single `0` for quarter-and-shorter, multiple `0`s
  /// for longer rests per GB/T 46845-2025 §6.3.7.2.
  void renderRestElement(NoteDuration duration, double digitX, String? id) {
    final longRestUnits = JianpuLayoutEngine._longRestQuarterUnits(duration);
    if (longRestUnits <= 1) {
      primitives.add(TextPrimitive('0', Point(digitX, _digitBaseline),
          size: _digitSize, elementId: id));
    } else {
      for (var u = 0; u < longRestUnits; u++) {
        final ux = digitX + u * quarterCell;
        primitives.add(TextPrimitive('0', Point(ux, _digitBaseline),
            size: _digitSize, elementId: id));
      }
    }
    if (id != null) anchorX[id] = digitX;
  }

  /// Draws 增时线 (duration dashes) and augmentation dots for a column.
  void renderDurationMarks(double digitX, int dashes, int augDots, String? id) {
    for (var d = 0; d < dashes; d++) {
      final cx = digitX + quarterCell * (d + 1);
      primitives.add(LinePrimitive(Point(cx - _dashLength / 2, _digitMid),
          Point(cx + _dashLength / 2, _digitMid),
          thickness: 0.18, elementId: id));
    }
    for (var d = 0; d < augDots; d++) {
      primitives.add(GlyphPrimitive(
          SmuflGlyph.augmentationDot,
          Point(
              digitX +
                  _digitInkHalf +
                  _symbolGap +
                  d * (2 * _dotHalf + _symbolGap),
              _augDotY),
          elementId: id));
    }
  }

  /// The underline groups of one measure (减时线).  Returns the deepest
  /// underline y drawn (0 when none).
  double layoutUnderlines(List<_Col> cols) {
    int levelOf(_Col c) => c.duration.base.flagCount;

    final runs = computeBeamRuns(
      count: cols.length,
      onsetAt: (i) => cols[i].onset,
      roleAt: (i) =>
          levelOf(cols[i]) >= 1 ? BeamItemRole.beamable : BeamItemRole.breaker,
      time: time,
    );

    var deepest = 0.0;
    for (final run in runs) {
      final maxLevel = run.map((i) => levelOf(cols[i])).reduce(max);
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
}
