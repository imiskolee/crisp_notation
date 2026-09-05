part of 'jianpu_layout.dart';

// Leading furniture: the "1=X" key label and time signature, plus the
// volta number that sits above the bracket.  Extracted from the original
// monolithic layout() local functions.

extension _JianpuFurniture on _JianpuBuilder {
  /// Estimated full advance of a text run (core cannot measure text).
  double textWidth(String text, double size) => text.length * 0.52 * size;

  /// Draws the `1=X` key label (e.g. `1=♭E`) at the current cursor [x],
  /// advancing [x] past the label.
  void drawKeyLabel(KeySignature k) {
    const size = 1.7;
    const labelBaseline = _digitBaseline - 0.15;
    var cx = x;
    void putText(String t) {
      final w = textWidth(t, size);
      primitives
          .add(TextPrimitive(t, Point(cx + w / 2, labelBaseline), size: size));
      cx += w;
    }

    putText('1=');
    final (glyph, letter) = JianpuLayoutEngine._tonicNameParts(k);
    if (glyph != null) {
      const scale = _accidentalScale * (size / _digitSize);
      final w = meta.bBoxOf(glyph).width * scale;
      _glyphCenteredAt(
          glyph, cx + w / 2 + 0.05, labelBaseline - 0.34 * size, scale);
      cx += w + 0.15;
    }
    putText(letter);
    x = cx + 0.7;
  }

  /// Draws the time signature (e.g. `4/4`) at the current cursor [x].
  void drawTimeSig(TimeSignature t) {
    final numerator = t.components?.join('+') ?? '${t.beats}';
    final cx = x + 0.55;
    primitives.add(TextPrimitive(numerator, Point(cx, 2.0), size: 1.7));
    primitives.add(TextPrimitive('${t.beatUnit}', Point(cx, 3.65), size: 1.7));
    x += 1.6;
  }
}
