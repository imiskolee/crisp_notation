/// One-off jianpu demo renderer — run with `flutter test
/// tool/render_jianpu_png.dart` from the crisp_notation package; writes PNGs
/// to the repository root as a side effect.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render jianpu demo pngs', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Bravura.debugOverrideMetadata(SmuflMetadata.fromJson(jsonDecode(
        File('assets/smufl/bravura_metadata.json').readAsStringSync())
        as Map<String, Object?>));
    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    await (FontLoader('packages/crisp_notation/Bravura')
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final roboto = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        final bytes = roboto.readAsBytesSync();
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.view(bytes.buffer))))
            .load();
      }
    }
    final theme =
        CrispNotationTheme.standard.copyWith(textFontFamily: 'Roboto');

    Future<void> render(String name, Score score) async {
      final png = await tester.runAsync(
          () => exportScoreToPng(score, staffSpace: 18, theme: theme));
      File('../../$name').writeAsBytesSync(png!);
    }

    // Degrees, octave dots, whole/half/quarter/eighth/sixteenth durations.
    await render(
      'jianpu_demo_scale.png',
      Score.simple(
        notes: 'c3:q c4 c5 | c4:q d4 e4 f4 | g4:h a4:h | b4:q c5 d5 e5 '
            '| f5:e f5 e5 d5 | c5:w',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );

    // G major (1=G) with lyrics and chord annotations.
    await render(
      'jianpu_demo_song.png',
      Score.simple(
        notes: 'd4:q d4 a4 a4 | b4:q b4 a4:h | g4:q g4 f#4 f#4 | e4:q e4 d4:h',
        timeSignature: TimeSignature.commonTime,
        keySignature: const KeySignature(1),
        lyrics: 'Twin- kle twin- kle lit- tle star twin- kle twin- kle star',
        annotations: 'G * * * C * G G * C * G *',
        staffType: StaffType.jianpu,
      ),
    );

    // Repeat signs, volta brackets, tie and slur (the gallery scenario).
    await render(
      'jianpu_demo_repeats.png',
      Score.simple(
        notes: '!repeat c4:q( d4 e4 f4) | g4:h~ g4:q r:q | '
            '!endrepeat !volta=1 a4:h g4:h | !volta=2 c5:h. c4:q',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );

    // Octaves: 2 dots below to 2 above.
    await render(
      'jianpu_demo_octaves.png',
      Score.simple(
        notes: 'c2:q c3 c4 c5 | c6:q c5 c4 c3 | c2:w c6:w',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );

    // Keys: D, Eb, A, F# with key changes.
    await render(
      'jianpu_demo_keys.png',
      Score.simple(
        notes: '!key=2 d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | '
            '!key=3 a4:q b4 c#4 d4 | !key=6 f#4:q g#4 a#4 b4',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );

    // Accidentals: sharps, flats, naturals, double sharps/flats.
    await render(
      'jianpu_demo_accidentals.png',
      Score.simple(
        notes: 'c4:q c#4 c4 cn4 | dbb4:q c##4 b4 bn4 | '
            'f#4:q bb4 e#4 f##4 | cn4:q d4 e4 f4',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );

    // Cross-measure underlines: eighths and sixteenths across barlines.
    await render(
      'jianpu_demo_cross_underlines.png',
      Score.simple(
        notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5 | '
            'c4:s d4 e4 f5 | g5:s f5 e5 c5',
        timeSignature: TimeSignature.commonTime,
        staffType: StaffType.jianpu,
      ),
    );
  });
}
