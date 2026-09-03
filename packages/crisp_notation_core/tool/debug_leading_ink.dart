import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

void main() {
  final source = File(
          '../crisp_notation/assets/smufl/bravura_metadata.json')
      .readAsStringSync();
  final metadata =
      SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
  final settings = LayoutSettings(metadata: metadata);
  final layout = const JianpuLayoutEngine().layout(
    Score.simple(notes: 'c4:q d4 e4 f4', staffType: StaffType.jianpu),
    settings,
  );
  for (final p in layout.primitives) {
    final (x0, y0, x1, y1) = switch (p) {
      LinePrimitive l => (l.from.x, l.from.y, l.to.x, l.to.y),
      TextPrimitive t => (t.position.x - 0.5, t.position.y - 1.4,
          t.position.x + 0.5, t.position.y),
      GlyphPrimitive g => (g.position.x, g.position.y - 2, g.position.x + 1,
          g.position.y + 2),
      _ => (9.0, 9.0, 9.0, 9.0),
    };
    if (x0 < 0.6 && y1 > 1.0 && y0 < 3.2) {
      print('$p  ~x[$x0..$x1] y[$y0..$y1]');
    }
  }
}
