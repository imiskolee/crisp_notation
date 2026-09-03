/// Generates synthetic jianpu OCR dataset using crisp_notation.
///
/// Runs from packages/crisp_notation directory:
///   flutter test tool/generate_ocr_dataset.dart --dart-define=COUNT=2000
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _random = Random();

String _randomPitch() {
  final steps = ['c', 'd', 'e', 'f', 'g', 'a', 'b'];
  final step = steps[_random.nextInt(steps.length)];
  final octave = 3 + _random.nextInt(4);
  final accidental = _random.nextInt(5);
  String acc = '';
  if (accidental == 1) acc = '#';
  if (accidental == 2) acc = '##';
  if (accidental == 3) acc = 'b';
  if (accidental == 4) acc = 'bb';
  return '$step$acc$octave';
}

String _randomDuration() {
  final durations = ['w', 'h', 'q', 'e', 's'];
  final d = durations[_random.nextInt(durations.length)];
  final dots = _random.nextInt(3);
  return '$d${'.' * dots}';
}

String _randomNote() {
  if (_random.nextInt(10) == 0) {
    return 'r:${_randomDuration()}';
  }
  return '${_randomPitch()}:${_randomDuration()}';
}

String generateRandomDsl({int measureCount = 2}) {
  final sb = StringBuffer();
  final fifths = _random.nextInt(11) - 5;
  sb.writeln('key: $fifths');
  final times = ['4/4', '3/4', '2/4', '6/8'];
  sb.writeln('time: ${times[_random.nextInt(times.length)]}');
  sb.writeln('staffType: jianpu');
  final measureNotes = <String>[];
  for (var m = 0; m < measureCount; m++) {
    final notes = <String>[];
    final noteCount = 2 + _random.nextInt(5);
    for (var i = 0; i < noteCount; i++) {
      notes.add(_randomNote());
    }
    measureNotes.add(notes.join(' '));
  }
  sb.writeln('notes: ${measureNotes.join(' | ')}');
  return sb.toString();
}

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
    return null;
  }
}

void main() {
  testWidgets('generate jianpu ocr dataset with crisp_notation', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

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
      final roboto = File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        final bytes = roboto.readAsBytesSync();
        final robotoLoader = FontLoader('Roboto');
        robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await robotoLoader.load();
      }
    }
    final theme = CrispNotationTheme.standard.copyWith(textFontFamily: 'Roboto');

    final count = int.parse(Platform.environment['COUNT'] ?? '100');
    final datasetDir = Directory('../../jianpu_ocr/data/raw');
    final imagesDir = Directory('${datasetDir.path}/images');
    final labelsDir = Directory('${datasetDir.path}/labels');

    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    if (!await labelsDir.exists()) await labelsDir.create(recursive: true);

    final manifestFile = File('${datasetDir.path}/manifest.jsonl');
    final vocabFile = File('${datasetDir.path}/vocab.json');

    print('Generating $count jianpu samples with crisp_notation...');
    final sink = manifestFile.openWrite();
    final vocab = <String, int>{
      '[PAD]': 0, '[SOS]': 1, '[EOS]': 2, '[BAR]': 3,
    };
    var vocabCounter = 4;

    int getOrCreateToken(String token) {
      if (!vocab.containsKey(token)) {
        vocab[token] = vocabCounter++;
      }
      return vocab[token]!;
    }

    try {
      for (var i = 0; i < count; i++) {
        final id = i.toString().padLeft(5, '0');
        final measureCount = 1 + _random.nextInt(3);
        final dsl = generateRandomDsl(measureCount: measureCount);

        final score = _parseFullDsl(dsl);
        if (score == null) {
          print('Failed to parse sample $id');
          continue;
        }

        try {
          final png = await tester.runAsync(
            () => exportScoreToPng(score, staffSpace: 18, theme: theme),
          );
          if (png == null) {
            print('Failed to render sample $id');
            continue;
          }

          final imgPath = '${imagesDir.path}/sample_$id.png';
          await File(imgPath).writeAsBytes(png);

          final tokens = <int>[getOrCreateToken('[SOS]')];
          final notesLine = dsl.split('\n').firstWhere(
                (l) => l.startsWith('notes:'),
                orElse: () => '',
              );
          if (notesLine.isNotEmpty) {
            final notesStr = notesLine.substring(6).trim();
            final noteGroups = notesStr.split(' | ');
            for (var gi = 0; gi < noteGroups.length; gi++) {
              if (gi > 0) tokens.add(getOrCreateToken('[BAR]'));
              final notes = noteGroups[gi].split(' ');
              for (final note in notes) {
                if (note.isEmpty) continue;
                tokens.add(getOrCreateToken(note));
              }
            }
          }
          tokens.add(getOrCreateToken('[EOS]'));

          final labelPath = '${labelsDir.path}/sample_$id.txt';
          await File(labelPath).writeAsString(tokens.join(' '));

          final entry = {
            'id': 'sample_$id',
            'image': 'images/sample_$id.png',
            'token': 'labels/sample_$id.txt',
            'dsl': dsl,
            'num_tokens': tokens.length,
          };
          sink.writeln(jsonEncode(entry));

          if ((i + 1) % 50 == 0) {
            print('  Generated ${i + 1}/$count');
          }
        } catch (e) {
          print('Error processing sample $id: $e');
        }
      }
    } finally {
      await sink.close();

      final vocabJson = <String, dynamic>{
        'token_to_id': vocab,
        'id_to_token': {
          for (final entry in vocab.entries) entry.value.toString(): entry.key,
        },
        'size': vocab.length,
      };
      vocabFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(vocabJson));
    }

    print('Done! Dataset saved to ${datasetDir.path}');
    print('  Images: ${count}');
    print('  Labels: ${count}');
    print('  Vocab size: ${vocab.length}');
  });
}
