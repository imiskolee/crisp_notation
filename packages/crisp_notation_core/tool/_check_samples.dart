import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

void main() {
  final dir = Directory('../crisp_notation/example/score_dsl_samples');
  for (final f in dir.listSync().whereType<File>()) {
    final src = f.readAsStringSync();
    try {
      final r = loadScoreDsl(src);
      stdout.writeln(
          'OK   ${f.uri.pathSegments.last}: ${r.system.staves.length} staves, '
          '${r.system.staves.first.measures.length} measures, layout=${r.layout}');
    } catch (e) {
      stdout.writeln('FAIL ${f.uri.pathSegments.last}: $e');
    }
  }
}
