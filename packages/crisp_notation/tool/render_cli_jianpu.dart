import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render jianpu from CLI', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final inputPath = const String.fromEnvironment('INPUT');
    final outputPath = const String.fromEnvironment('OUTPUT');
    final staffSpace =
        double.tryParse(const String.fromEnvironment('STAFF_SPACE')) ?? 18;
    if (inputPath.isEmpty || outputPath.isEmpty) {
      stderr.writeln('Usage: flutter test tool/render_cli_jianpu.dart --dart-define=INPUT=<dsl_file> --dart-define=OUTPUT=<png_file> [--dart-define=STAFF_SPACE=18]');
      return;
    }

    final fontLoader = FontLoader('packages/crisp_notation/Bravura');
    final metadata = SmuflMetadata.fromJson(
      jsonDecode(
        File('assets/smufl/bravura_metadata.json').readAsStringSync(),
      ) as Map<String, Object?>,
    );
    Bravura.debugOverrideMetadata(metadata);

    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    fontLoader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await fontLoader.load();

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final roboto = File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        final bytes = roboto.readAsBytesSync();
        final robotoLoader = FontLoader('Roboto');
        robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await robotoLoader.load();
      }
    }
    // CJK fallback for lyrics/annotations: the test environment has no
    // system fonts, so load one explicitly when available.
    final cjkLoaded = <String>[];
    final msyh = File(r'C:\Windows\Fonts\msyh.ttc');
    if (msyh.existsSync()) {
      final bytes = msyh.readAsBytesSync();
      final cjkLoader = FontLoader('Microsoft YaHei');
      cjkLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await cjkLoader.load();
      cjkLoaded.add('Microsoft YaHei');
    }
    final theme = CrispNotationTheme.standard.copyWith(
      textFontFamily: 'Roboto',
      textFontFamilyFallback: cjkLoaded.isEmpty ? null : cjkLoaded,
    );

    final dslText = File(inputPath).readAsStringSync();
    final score = _parseDsl(dslText);
    if (score == null) {
      stderr.writeln('Failed to parse DSL: $inputPath');
      return;
    }

    stdout.writeln('parse ok: ${score.measures.length} measures, exporting...');
    final png = await tester.runAsync(
      () => exportScoreToPng(score, staffSpace: staffSpace, theme: theme)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw StateError('exportScoreToPng timed out after 60s');
      }),
    );
    if (png == null || png.isEmpty) {
      stderr.writeln('Failed to render: $inputPath');
      return;
    }
    stdout.writeln('export ok: ${png.length} bytes');

    File(outputPath).writeAsBytesSync(png);
    stdout.writeln('OK: $outputPath');
  });
}

Score? _parseDsl(String dsl) {
  try {
    final lines = dsl.split('\n');
    int fifths = 0;
    String timeStr = '4/4';
    String notesStr = '';
    String? lyricsStr;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('key:')) {
        fifths = int.parse(trimmed.substring(4).trim());
      } else if (trimmed.startsWith('time:')) {
        timeStr = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('notes:')) {
        notesStr = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('lyrics:')) {
        lyricsStr = trimmed.substring(7).trim();
      }
    }
    final timeParts = timeStr.split('/');
    final beats = int.parse(timeParts[0]);
    final beatUnit = int.parse(timeParts[1]);
    return Score.simple(
      keySignature: KeySignature(fifths),
      timeSignature: TimeSignature(beats, beatUnit),
      staffType: StaffType.jianpu,
      notes: notesStr,
      lyrics: lyricsStr,
    );
  } catch (e) {
    return null;
  }
}
