part of 'jianpu_layout.dart';

// Post-pass overlays: ties, slurs, tuplets, dynamics, annotations, lyrics,
// and the ink-bounds finalisation.  These run after the measure loop has
// placed all digits, accidentals, octave dots, underlines, and barlines.

extension _JianpuOverlays on _JianpuBuilder {
  /// Draws ties between consecutive notes with the same shown pitch.
  void layoutTies() {
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
      if (anchorPitch[note.id] != anchorPitch[next.id]) continue;
      final yA = min(1.35, (topOf[note.id] ?? _digitTop) - _symbolGap);
      final yB = min(1.35, (topOf[next.id] ?? _digitTop) - _symbolGap);
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
  }

  /// Draws slurs from score span data.
  void layoutSlurs() {
    for (final slur in score.slurs) {
      final a = anchorX[slur.startId], b = anchorX[slur.endId];
      if (a == null || b == null || b <= a) continue;
      final span = b - a;
      final yA = min(1.3, (topOf[slur.startId] ?? _digitTop) - _symbolGap);
      final yB = min(1.3, (topOf[slur.endId] ?? _digitTop) - _symbolGap);
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
  }

  /// Draws tuplet brackets (三连音 etc.) above the digit row.
  void layoutTuplets() {
    for (final measure in score.measures) {
      for (final tuplet in measure.tuplets) {
        if (tuplet.voice != 0) continue;
        double? firstX, lastX;
        var spanTop = _digitTop;
        for (var i = tuplet.startIndex;
            i <= tuplet.endIndex && i < measure.elements.length;
            i++) {
          final eid = measure.elements[i].id;
          final at = eid == null ? null : anchorX[eid];
          if (at == null) continue;
          firstX ??= at;
          lastX = at;
          spanTop = min(spanTop, topOf[eid] ?? _digitTop);
        }
        if (firstX == null || lastX == null) continue;
        _drawTuplet(firstX, lastX, tuplet.actual, spanTop);
      }
    }
  }

  /// 连音符括线：开口横线 + 端钩 + 比例数字。
  void _drawTuplet(
      double firstDigitX, double lastDigitX, int actual, double spanTop) {
    final x1 = firstDigitX - _digitInkHalf - 0.2;
    final x2 = lastDigitX + _digitInkHalf + 0.2;
    final bracketY = min(_tupletY, spanTop - _symbolGap - _tupletHook);
    final label = '$actual';
    final halfLabel = textWidth(label, _tupletDigitSize) / 2 + 0.18;
    final midX = (x1 + x2) / 2;
    const th = 0.14;
    primitives.add(LinePrimitive(
        Point(x1, bracketY), Point(max(x1, midX - halfLabel), bracketY),
        thickness: th));
    primitives.add(LinePrimitive(
        Point(min(x2, midX + halfLabel), bracketY), Point(x2, bracketY),
        thickness: th));
    primitives.add(LinePrimitive(
        Point(x1, bracketY), Point(x1, bracketY + _tupletHook),
        thickness: th));
    primitives.add(LinePrimitive(
        Point(x2, bracketY), Point(x2, bracketY + _tupletHook),
        thickness: th));
    primitives.add(TextPrimitive(
        label, Point(midX, bracketY + 0.34 * _tupletDigitSize),
        size: _tupletDigitSize));
  }

  /// Draws dynamics (p, mf, etc.) — below for instrumental, above for vocal.
  void layoutDynamics() {
    final isVocal = score.lyrics.isNotEmpty;
    final dynamicY = isVocal ? 0.5 : 4.7;
    for (final dynamic_ in score.dynamics) {
      final at = anchorX[dynamic_.elementId];
      if (at == null) continue;
      primitives.add(
          TextPrimitive(dynamic_.level.name, Point(at, dynamicY), size: 1.6));
    }
  }

  /// Draws annotations (text labels) above the digit row.
  void layoutAnnotations() {
    for (final annotation in score.annotations) {
      final at = anchorX[annotation.elementId];
      if (at == null) continue;
      primitives.add(TextPrimitive(annotation.text, Point(at, 0.5),
          size: s.annotationSize));
    }
  }

  /// Draws lyrics: syllables grouped into verses, stacked below the digit row,
  /// nudged right to avoid horizontal overlap.
  void layoutLyrics() {
    if (score.lyrics.isEmpty) return;
    final size = s.lyricSize;
    final lineHeight = size * 1.7;
    final firstBaseline = max(5.5, max(deepestUnderline, lowestInk) + 2.5);

    final byVerse = <int, List<Lyric>>{};
    for (final lyric in score.lyrics) {
      byVerse.putIfAbsent(lyric.verse, () => []).add(lyric);
    }
    final verses = byVerse.keys.toList()..sort();

    for (var row = 0; row < verses.length; row++) {
      final lyrics = byVerse[verses[row]]!;
      final baselineY = firstBaseline + row * lineHeight;

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
      _spreadRight(centers, halfWidths, 0.8 * size);

      for (var j = 0; j < valid.length; j++) {
        final lyric = lyrics[valid[j]];
        primitives.add(TextPrimitive(lyric.text, Point(centers[j], baselineY),
            size: size));
      }
    }
  }

  /// Computes ink bounds from all primitives and returns the final
  /// [ScoreLayout].
  ScoreLayout finalizeInkBounds() {
    final width = x;
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
}
