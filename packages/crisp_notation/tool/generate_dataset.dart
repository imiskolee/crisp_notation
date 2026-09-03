/// Generates a synthetic jianpu OCR dataset.
///
/// For each sample, this script:
/// 1. Generates a random Score DSL string.
/// 2. Renders it as a PNG image using `exportScoreToPng`.
/// 3. Saves the DSL string as the ground-truth label.
///
/// Run from the `crisp_notation` package directory:
/// `flutter test tool/generate_dataset.dart --dart-define=COUNT=1000`

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _random = Random();

/// Generates a random score DSL string.
///
/// [measureCount] is the number of measures (bars).
String generateRandomDsl({int measureCount = 2}) {
  final sb = StringBuffer();

  // Random key signature (fifths from -5 to 5).
  final fifths = _random.nextInt(11) - 5;
  sb.writeln('key: $fifths');

  // Random time signature.
  final times = [
    '4/4', '3/4', '2/4', '6/8',
  ];
  sb.writeln('time: ${times[_random.nextInt(times.length)]}');

  sb.writeln('staffType: jianpu');

  // Notes line with multiple measures.
  final measureNotes = <String>[];
  for (var m = 0; m < measureCount; m++) {
    final notes = <String>[];
    // Generate between 2 and 6 notes per measure for simplicity.
    final noteCount = 2 + _random.nextInt(5);
    for (var i = 0; i < noteCount; i++) {
      notes.add(_randomNote());
    }
    measureNotes.add(notes.join(' '));
  }
  sb.writeln('notes: ${measureNotes.join(' | ')}');

  return sb.toString();
}

/// Generates a random note token like "c4:q", "d5:e", or "r:h".
String _randomNote() {
  if (_random.nextInt(10) == 0) {
    // 10% chance of a rest.
    return 'r:${_randomDuration()}';
  }
  final pitch = _randomPitch();
  final duration = _randomDuration();
  return '$pitch:$duration';
}

/// Generates a random pitch token like "c4", "d#5".
String _randomPitch() {
  final steps = ['c', 'd', 'e', 'f', 'g', 'a', 'b'];
  final step = steps[_random.nextInt(steps.length)];
  final octave = 3 + _random.nextInt(4); // 3, 4, 5, 6
  final accidental = _random.nextInt(5);
  String acc = '';
  if (accidental == 1) acc = '#';
  if (accidental == 2) acc = '##';
  if (accidental == 3) acc = 'b';
  if (accidental == 4) acc = 'bb';
  return '$step$acc$octave';
}

/// Generates a random duration token like "q", "e", "h.", "s".
String _randomDuration() {
  final durations = ['w', 'h', 'q', 'e', 's'];
  final d = durations[_random.nextInt(durations.length)];
  final dots = _random.nextInt(3); // 0, 1, 2
  return '$d${'.' * dots}';
}

void main() {
  testWidgets('generate jianpu ocr dataset', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // --- Setup SMuFL and Fonts ---
    final fontLoader = FontLoader('Bravura');
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
      final roboto = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        final bytes = roboto.readAsBytesSync();
        final robotoLoader = FontLoader('Roboto');
        robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await robotoLoader.load();
      }
    }
    final theme =
        CrispNotationTheme.standard.copyWith(textFontFamily: 'Roboto');

    // --- Dataset generation ---
    final count = int.parse(Platform.environment['COUNT'] ?? '100');
    final datasetDir = Directory('../../jianpu_ocr/dataset');
    final imagesDir = Directory('${datasetDir.path}/images');
    final labelsDir = Directory('${datasetDir.path}/labels');
    final manifestFile = File('${datasetDir.path}/manifest.jsonl');

    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    if (!await labelsDir.exists()) await labelsDir.create(recursive: true);

    print('Generating $count jianpu samples...');
    final sink = manifestFile.openWrite();
    try {
      for (var i = 0; i < count; i++) {
        final id = i.toString().padLeft(4, '0');
        final dsl = generateRandomDsl(measureCount: 1 + _random.nextInt(3));

        try {
          final score = Score.simple(
            keySignature: KeySignature(0),
            timeSignature: TimeSignature.commonTime,
            staffType: StaffType.jianpu,
            notes: '',
          );
          // Parse the DSL manually because Score.simple does not accept the full format.
          final parsedScore = _parseFullDsl(dsl);

          final png = await tester.runAsync(
            () => exportScoreToPng(parsedScore!, staffSpace: 18, theme: theme),
          );
          if (png != null) {
            final imgPath = '${imagesDir.path}/sample_$id.png';
            await File(imgPath).writeAsBytes(png);

            final labelPath = '${labelsDir.path}/sample_$id.txt';
            await File(labelPath).writeAsString(dsl);

            // Write manifest entry.
            sink.writeln(jsonEncode({
              'id': id,
              'image': 'images/sample_$id.png',
              'label': 'labels/sample_$id.txt',
              'dsl': dsl,
            }));

            if (i % 10 == 0) {
              print('Generated $i / $count');
            }
          }
        } catch (e) {
          // Skip failed samples.
          print('Failed sample $id: $e');
        }
      }
    } finally {
      await sink.close();
    }

    print('Done! Dataset saved to ${datasetDir.path}');
  });
}

/// Parses a full DSL string with metadata headers and notes.
///
/// This is a simplified parser that handles the format generated by
/// [generateRandomDsl]. It assumes lines like "key: 1", "time: 4/4",
/// "notes: c4:q d4 | e4:h".
Score? _parseFullDsl(String dsl) {
  try {
    final lines = dsl.split('\n');
    int fifths = 0;
    String timeStr = '4/4';
    String notesStr = '';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('key:')) {
        fifths = int.parse(trimmed.substring(4).trim());
      } else if (trimmed.startsWith('time:')) {
        timeStr = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('notes:')) {
        notesStr = trimmed.substring(6).trim();
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
    );
  } catch (e) {
    // Return null if parsing fails.
    return null;
  }
}
