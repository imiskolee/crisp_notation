part of 'jianpu_layout.dart';

// Barlines, repeats, voltas — extracted from the original monolithic
// layout() local functions.  Behaviour is unchanged; the closures are now
// extension methods on _JianpuBuilder so they can be unit-tested in
// isolation and the main build() loop reads as orchestration.

extension _JianpuBarlines on _JianpuBuilder {
  /// Draws a vertical barline segment at [x] with [thickness], spanning the
  /// jianpu barline range [_barlineTop]→[_barlineBottom].
  void vline(double x, double thickness) {
    primitives.add(LinePrimitive(
        Point(x, _barlineTop), Point(x, _barlineBottom),
        thickness: thickness));
  }

  /// x of the thick line that follows a thin line at [thinX].
  double thickAfterThin(double thinX) =>
      thinX +
      s.thinBarlineThickness / 2 +
      s.barlineSeparation +
      s.thickBarlineThickness / 2;

  /// The x past the barline (before barlineGap) matching the staff engine's
  /// `_addBarline` advance.  [rightEdge] is the right ink edge returned by
  /// `closingBarline`/`endRepeat`.
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

  /// 反复圆点对：中心分列数字墨盒的上、下四分之一处。
  void repeatDots(double cx) {
    _glyphCenteredAt(SmuflGlyph.repeatDot, cx, _repeatDotHigh, 1.0);
    _glyphCenteredAt(SmuflGlyph.repeatDot, cx, _repeatDotLow, 1.0);
  }

  /// `|:` — thick line, thin line, dots.  Returns right ink edge.
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

  /// `:|` — dots, thin line, thick line.  Returns right ink edge.
  double endRepeat(double at) {
    final dotX = at + 0.4 + _dotHalf;
    repeatDots(dotX);
    final thinX = dotX + _dotHalf + _symbolGap + s.thinBarlineThickness / 2;
    vline(thinX, s.thinBarlineThickness);
    final thickX = thickAfterThin(thinX);
    vline(thickX, s.thickBarlineThickness);
    return thickX + s.thickBarlineThickness / 2;
  }

  /// GB/T 46845-2025 §5.8.2.2c: 前后紧邻的两个反复段落合并为一个符号。
  /// Left-to-right: left dots + left thin + shared thick + right thin + right dots.
  double combinedRepeat(double at) {
    final leftDotX = at + 0.4 + _dotHalf;
    repeatDots(leftDotX);
    final leftThinX =
        leftDotX + _dotHalf + _symbolGap + s.thinBarlineThickness / 2;
    vline(leftThinX, s.thinBarlineThickness);
    final thickX = thickAfterThin(leftThinX);
    vline(thickX, s.thickBarlineThickness);
    final rightThinX = thickX +
        s.thickBarlineThickness / 2 +
        s.barlineSeparation +
        s.thinBarlineThickness / 2;
    vline(rightThinX, s.thinBarlineThickness);
    final rightDotX =
        rightThinX + s.thinBarlineThickness / 2 + _symbolGap + _dotHalf;
    repeatDots(rightDotX);
    return rightDotX + _dotHalf + 0.4;
  }

  /// Draws a measure's closing barline in [style]; returns the right ink edge.
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
        final second = barX + s.thinBarlineThickness + s.barlineSeparation;
        vline(second, s.thinBarlineThickness);
        return second + s.thinBarlineThickness / 2;
      case BarlineStyle.heavy:
        vline(barX, s.thickBarlineThickness);
        return barX + s.thickBarlineThickness / 2;
      case BarlineStyle.dashed:
        const dashLen = 0.32, dashStep = 0.52;
        var segY = _barlineTop;
        while (segY <= _barlineBottom + 1e-9) {
          primitives.add(LinePrimitive(Point(barX, segY),
              Point(barX, min(segY + dashLen, _barlineBottom)),
              thickness: s.thinBarlineThickness));
          segY += dashStep;
        }
        return barX + s.thinBarlineThickness / 2;
      default:
        vline(barX, s.thinBarlineThickness);
        return barX + s.thinBarlineThickness / 2;
    }
  }

  /// GB/T 46845-2025 §5.11: 跳房子记号（volta/ending bracket）。
  void drawVolta(double startX, double barX, int volta) {
    const y = -0.3;
    primitives.add(LinePrimitive(Point(startX, y + 0.9), Point(startX, y),
        thickness: 0.14));
    primitives
        .add(LinePrimitive(Point(startX, y), Point(barX, y), thickness: 0.14));
    primitives.add(
        LinePrimitive(Point(barX, y), Point(barX, y + 0.9), thickness: 0.14));
    primitives.add(
        TextPrimitive('$volta.', Point(startX + 0.25, y - 0.25), size: 1.1));
  }
}
