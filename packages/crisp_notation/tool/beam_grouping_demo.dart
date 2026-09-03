/// Beam-grouping consistency check: the same rhythms rendered as staff
/// notation and jianpu in one system — both share `computeBeamRuns`
/// (beam_grouping.dart), so the grouping must match beat-for-beat.
///
/// Run from the crisp_notation package:
///   flutter test tool/beam_grouping_demo.dart
///
/// Writes a PNG to ../../score_dsl_renders/ (repo root).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final outDir = '../../score_dsl_renders';
  const staffSpace = 24.0;
  final ts =
      DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

  testWidgets('render beam grouping consistency', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final metadata = SmuflMetadata.fromJson(jsonDecode(
            File('assets/smufl/bravura_metadata.json').readAsStringSync())
        as Map<String, Object?>);
    Bravura.debugOverrideMetadata(metadata);
    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    await (FontLoader('packages/crisp_notation/Bravura')
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();

    String? textFontFamily;
    for (final path in [
      'C:/Windows/Fonts/msyh.ttc',
      'C:/Windows/Fonts/simsun.ttc',
      'C:/Windows/Fonts/simhei.ttf',
    ]) {
      if (File(path).existsSync()) {
        textFontFamily = 'CjkText';
        await (FontLoader(textFontFamily)
              ..addFont(Future.value(
                  ByteData.view(File(path).readAsBytesSync().buffer))))
            .load();
        break;
      }
    }
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (textFontFamily == null && flutterRoot != null) {
      final roboto = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        await (FontLoader('Roboto')
              ..addFont(Future.value(
                  ByteData.view(roboto.readAsBytesSync().buffer))))
            .load();
        textFontFamily = 'Roboto';
      }
    }
    final theme = textFontFamily == null
        ? CrispNotationTheme.standard
        : CrispNotationTheme.standard.copyWith(textFontFamily: textFontFamily);

    Directory(outDir).createSync(recursive: true);
    final settings = LayoutSettings(metadata: metadata);

    final result = loadScoreDsl('''
---score
title: 符杠/减时线分组一致性
scale: C
timeSignature: 4/4
tempo: 96
tracks:
  - name: 五线谱
    type: standard
    clef: treble
  - name: 简谱
    type: jianpu
---
:五线谱
notes: c5:e d5 e5 f5 g5 a5 b5 c6 | c5:s d5 e5 f5 g5 a5 b5 c6 c6 b5 a5 g5 f5 e5 d5 c5 | !time=3/8 c5:e d5 e5 | c5:s d5 e5 f5 g5 a5 | !time=2/4 c5:e d5 e5 f5
:简谱
notes: c4:e d4 e4 f4 g4 a4 b4 c5 | c4:s d4 e4 f4 g4 a4 b4 c5 c5 b4 a4 g4 f4 e4 d4 c4 | !time=3/8 c4:e d4 e4 | c4:s d4 e4 f4 g4 a4 | !time=2/4 c4:e d4 e4 f4
''');
    final wrapped = layoutStaffSystemSystems(
      result.system,
      settings,
      maxWidth: 140,
      staffGap: 6,
    );
    final png = await tester.runAsync(
      () => renderStaffSystemSystemsToPng(
        wrapped,
        staffSpace: staffSpace,
        systemGap: 8,
        leftMargin: 10,
        showInstrumentLabels: true,
        showTitle: true,
        theme: theme,
      ),
    );
    final name = 'beam_grouping_consistency_$ts.png';
    File('$outDir/$name').writeAsBytesSync(png!);
    expect(File('$outDir/$name').lengthSync(), greaterThan(1000));
  });
}
