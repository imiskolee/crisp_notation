import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('generate simplified jianpu batch', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final outDir = 'D:/develop/src/fortdyn/jianpu_ocr/data/raw';
    final count = 10000;

    final outPath = Directory(outDir);
    if (!outPath.existsSync()) outPath.createSync(recursive: true);

    print('Loading fonts...');
    Bravura.debugOverrideMetadata(SmuflMetadata.fromJson(
      jsonDecode(
        File('assets/smufl/bravura_metadata.json').readAsStringSync(),
      ) as Map<String, Object?>,
    ));
    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    await (FontLoader('packages/crisp_notation/Bravura')
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    String? fontFamily;
    if (flutterRoot != null) {
      final roboto = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        final bytes = roboto.readAsBytesSync();
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.view(bytes.buffer))))
            .load();
        fontFamily = 'Roboto';
      }
    }
    final theme =
        CrispNotationTheme.standard.copyWith(textFontFamily: fontFamily);
    print('Fonts loaded. Starting generation...');

    final rand = Random(42);

    // Reset manifest
    final manifestFile = File('${outDir}/manifest.jsonl');
    if (manifestFile.existsSync()) manifestFile.deleteSync();

    Future<void> renderSample(int idx) async {
      final sample = _generateSample(rand);
      final score = sample['score'] as Score;
      final tokenList = sample['tokens'] as List<String>;

      final png = await tester.runAsync(
          () => exportScoreToPng(score, staffSpace: 18, theme: theme));
      if (png == null || png.isEmpty) {
        stderr.writeln('FAIL sample_${idx.toString().padLeft(5, '0')}');
        return;
      }

      final id = 'sample_${idx.toString().padLeft(5, '0')}';
      final imgDir = Directory('${outDir}/images');
      final tokDir = Directory('${outDir}/tokens');
      imgDir.createSync(recursive: true);
      tokDir.createSync(recursive: true);

      File('${imgDir.path}/$id.png').writeAsBytesSync(png);
      File('${tokDir.path}/$id.txt').writeAsStringSync(tokenList.join(' '));

      final manifest = <String, dynamic>{
        'id': id,
        'image': 'images/$id.png',
        'token': 'tokens/$id.txt',
      };

      manifestFile.writeAsStringSync('${jsonEncode(manifest)}\n',
          mode: FileMode.append);

      if ((idx + 1) % 100 == 0) {
        print('Generated ${idx + 1}/$count');
      }
    }

    for (int i = 0; i < count; i++) {
      await renderSample(i);
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Write vocab: one composite token per note, matching Python vocab.py.
    // Order: specials, then N{pitch}{octave}{duration}{dots}
    // pitch 0-6, octave 0-2, duration w/h/q/e/s, dots 0-1
    final vocabList = <String>[
      '[BLANK]',
      '[PAD]',
      '[SOS]',
      '[EOS]',
      '[BAR]',
    ];
    const durations = ['w', 'h', 'q', 'e', 's'];
    for (int p = 0; p < 7; p++) {
      for (int o = 0; o < 3; o++) {
        for (final d in durations) {
          for (int f = 0; f < 2; f++) {
            vocabList.add('N$p$o$d$f');
          }
        }
      }
    }
    File('${outDir}/vocab.json').writeAsStringSync(jsonEncode(vocabList));

    print('Done! Generated $count samples.');
  });
}

// ---------------------------------------------------------------------------
// Simplified jianpu sample generator
//
// Constraints:
//   - Pitch: 1..7 (c d e f g a b)
//   - Octave: 3 (low/1dot below), 4 (mid/no dots), 5 (high/1dot above)
//   - Duration: w(hole), h(alf), q(uarter), e(ighth), s(ixteenth)
//   - Dots: 0 or 1; dotted only on h and q
//   - Accidentals: none (A1 always natural, token dropped)
//   - Common beam patterns for 8th/16th notes
// ---------------------------------------------------------------------------

final _pitchNames = <String>['c', 'd', 'e', 'f', 'g', 'a', 'b'];

// Beat value of each duration in 16th-note units (for 4/4 counting)
const _durBeats = <String, int>{
  'w': 16, // whole = 16 sixteenths
  'h': 8, // half = 8 sixteenths
  'q': 4, // quarter = 4 sixteenths
  'e': 2, // eighth = 2 sixteenths
  's': 1, // sixteenth = 1 sixteenth
};

// Dotted version of a base duration, in 16th-note units
int _dottedBeats(String base) {
  final b = _durBeats[base]!;
  return b + b ~/ 2;
}

Map<String, dynamic> _generateSample(Random rand) {
  final notes = <String>[];
  final tokens = <String>[];

  // 4/4 time signature, 1 bar per sample for simplicity
  // This ensures samples are short phrases like a single line of a song
  const beatsPerBar = 16; // 16 sixteenths per 4/4 bar
  int beats = 0;

  // Generate rhythmic pattern first, then fill with pitches
  while (beats < beatsPerBar) {
    final remaining = beatsPerBar - beats;
    final pattern = _pickRhythmPattern(rand, remaining);

    for (final dur in pattern) {
      final pitchIdx = rand.nextInt(7); // P0-P6 (c..b = 简谱 1..7)
      final octaveIdx = rand.nextInt(3); // O0=low, O1=mid, O2=high

      // Map to Western octave number
      final westernOctave = 3 + octaveIdx; // 3, 4, 5

      // Determine if dotted
      String durLetter;
      int dot;
      if (dur.startsWith('d')) {
        durLetter = dur.substring(1);
        dot = 1;
      } else {
        durLetter = dur;
        dot = 0;
      }

      final pitchLetter = _pitchNames[pitchIdx];

      // DSL token like "c4:q" or "d4:h."
      var noteStr = '$pitchLetter$westernOctave:$durLetter';
      if (dot == 1) noteStr += '.';
      notes.add(noteStr);

      // Composite token: one class per note, N{pitch}{octave}{duration}{dots}
      tokens.add('N$pitchIdx$octaveIdx$durLetter$dot');
    }

    // Use a 4/4 default so we don't need to specify clef/time in DSL
    break;
  }

  final score = Score.simple(
    keySignature: const KeySignature(0), // default C clef
    timeSignature: const TimeSignature(4, 4),
    staffType: StaffType.jianpu,
    notes: notes.join(' '),
  );

  return {
    'score': score,
    'tokens': tokens,
  };
}

/// Pick a rhythmic pattern that fits within [maxBeats] (in 16th-note units).
/// Returns a list of duration strings like ['q', 'e', 'e', 's', 's', 's', 's'].
/// Prefers patterns that form natural beams.
List<String> _pickRhythmPattern(Random rand, int maxBeats) {
  // Common rhythmic "cells" used in jianpu songs
  // Durations: w, h, dh(dotted-half), q, dq(dotted-quarter), e, s
  const cells = <List<int>>[
    // [16] quarter-note beats mapped to _durBeats values
    [16], // whole note
    [8, 8], // half + half
    [8, 4, 4], // half + q + q
    [4, 4, 4, 4], // 4 quarters
    [4, 4, 4, 2, 2], // q q q 8 8
    [4, 4, 2, 2, 2, 2], // q q 8 8 8 8
    [4, 2, 2, 2, 2, 2, 2], // q 8*6
    [2, 2, 2, 2, 2, 2, 2, 2], // 8*8
    [4, 2, 1, 1, 2, 1, 1], // q 8 16 16 8 16 16 (前十六后八 + 前八后十六)
    [2, 1, 1, 2, 2, 2, 2], // 8 16 16 8*4
    [2, 2, 1, 1, 1, 1, 2, 2], // 8 8 16*4 8 8
    [4, 1, 1, 1, 1, 1, 1, 1, 1], // q + 16*8
    [2, 1, 1, 2, 1, 1, 2, 1, 1], // 8 16 16 repeated
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // 16*16
    [12, 4], // dotted-half + q (dotted = 12 sixteenths)
    [6, 2, 2, 2, 2, 2], // dotted-q (6) + 8*5 (wait 6+2*5=16, yes: dotted q is 6 units)
  ];

  // Filter cells that fit
  final candidates = cells.where((c) => c.reduce((a, b) => a + b) <= maxBeats).toList();
  if (candidates.isEmpty) {
    // Fallback: fill with quarters
    final qCount = maxBeats ~/ 4;
    return List.filled(qCount, 'q');
  }

  final cell = candidates[rand.nextInt(candidates.length)];
  return _expandCell(cell, rand);
}

/// Convert a cell of 16th-note beat counts into duration letters.
/// Dotted durations are marked with 'd' prefix.
List<String> _expandCell(List<int> cell, Random rand) {
  final result = <String>[];
  for (final beats in cell) {
    switch (beats) {
      case 16:
        result.add('w');
      case 12:
        result.add('dh'); // dotted half = 12 sixteenths
      case 8:
        result.add('h');
      case 6:
        result.add('dq'); // dotted quarter = 6 sixteenths
      case 4:
        result.add('q');
      case 2:
        result.add('e');
      case 1:
        result.add('s');
      default:
        // Split into smaller durations
        result.add('q');
    }
  }
  return result;
}
