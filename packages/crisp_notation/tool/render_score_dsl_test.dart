/// Score DSL scenario renderer — generates PNGs for all four basic scenarios.
///
/// Run from the crisp_notation package:
///   flutter test tool/render_score_dsl_test.dart
///
/// Writes PNGs to ../../score_dsl_renders/ (repo root).
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
  final staffSpace = 24.0;
  final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

  testWidgets('render score_dsl scenarios', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // --- Font setup ---
    final metadata = SmuflMetadata.fromJson(jsonDecode(
            File('assets/smufl/bravura_metadata.json').readAsStringSync())
        as Map<String, Object?>);
    Bravura.debugOverrideMetadata(metadata);
    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    await (FontLoader('packages/crisp_notation/Bravura')
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();

    // Try to load a CJK-capable text font for lyrics.
    String? textFontFamily;
    final cjkCandidates = <String>[
      'C:/Windows/Fonts/msyh.ttc',
      'C:/Windows/Fonts/simsun.ttc',
      'C:/Windows/Fonts/simhei.ttf',
    ];
    for (final path in cjkCandidates) {
      if (File(path).existsSync()) {
        textFontFamily = 'CjkText';
        final bytes = File(path).readAsBytesSync();
        await (FontLoader(textFontFamily)
              ..addFont(Future.value(ByteData.view(bytes.buffer))))
            .load();
        break;
      }
    }
    // Fallback: Roboto from Flutter SDK.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final roboto =
          File('$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
      if (roboto.existsSync()) {
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.view(roboto.readAsBytesSync().buffer))))
            .load();
        textFontFamily ??= 'Roboto';
      }
    }

    final theme = textFontFamily == null
        ? CrispNotationTheme.standard
        : CrispNotationTheme.standard.copyWith(textFontFamily: textFontFamily);

    Directory(outDir).createSync(recursive: true);
    final settings = LayoutSettings(metadata: metadata);

    Future<void> renderSingle(String name, String dsl) async {
      final result = loadScoreDsl(dsl);
      final png = await tester.runAsync(
        () => exportScoreToPng(
          result.system.staves.first,
          staffSpace: staffSpace,
          theme: theme,
        ),
      );
      File('$outDir/$name').writeAsBytesSync(png!);
    }

    Future<void> renderMulti(String name, String dsl) async {
      final result = loadScoreDsl(dsl);
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
      File('$outDir/$name').writeAsBytesSync(png!);
    }

    // --- Scenario 1: jianpu solo ---
    await renderSingle('scenario1_jianpu_solo_$ts.png', '''
---score
title: 小星星
scale: C
timeSignature: 4/4
tempo: 96
tracks:
  - name: 旋律
    type: jianpu
---
:旋律
notes: c4:q c4 g4 g4 | a4:q a4 g4:h | f4:q f4 e4 e4 | d4:q d4 c4:h
''');

    // --- Scenario 2: jianpu + lyrics ---
    await renderSingle('scenario2_lyrics_$ts.png', '''
---score
title: 欢乐颂
description: 贝多芬《第九交响曲》- 合唱部分
authors: 贝多芬
scale: Bb
timeSignature: 4/4
tempo: 80
tracks:
  - name: 合唱
    type: jianpu
---
:合唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | e4:q. d4:e d4:h | e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | d4:q. c4:e c4:h
lyrics: 欢 乐 女 神 圣 洁 美 丽 你 的 光 芒 照 大 地
lyrics2: 灿 烂 星 光 照 大 地 我 们 充 满 欢 乐 和 喜
''');

    // --- Scenario 3: piano solo (grand staff) ---
    await renderMulti('scenario3_piano_solo_$ts.png', '''
---score
title: 我的祖国（钢琴独奏）
authors: 集体
scale: G
timeSignature: 4/4
tempo: 110
tracks:
  - name: piano_right
    type: standard
    clef: treble
    group: piano
  - name: piano_left
    type: standard
    clef: bass
    group: piano
---
:piano_right
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | e4:q. d4:e d4:h
:piano_left
notes: c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q | c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q | g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q | c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q
''');

    // --- Scenario 4: piano + jianpu + lyrics ---
    await renderMulti('scenario4_$ts.png', '''
---score
title: 我的祖国
scale: G
timeSignature: 4/4
tempo: 110
tracks:
  - name: 独唱
    type: jianpu
  - name: piano_right
    type: standard
    clef: treble
    group: piano
  - name: piano_left
    type: standard
    clef: bass
    group: piano
---
:独唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | d4:q. c4:e c4:h
lyrics: 一 条 大 河 波 浪 宽 风 吹 稻 花 香 两 岸
lyrics2: 我 家 就 在 岸 上 住 听 惯 了 艄 公 的 号 子
:piano_right
notes: c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q | c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q | g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q | g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q
:piano_left
notes: c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q | c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q | g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q | c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q
''');

    // --- Scenario 5: staff notation + lyrics ---
    await renderSingle('scenario5_staff_lyrics_$ts.png', '''
---score
title: 送别
authors: 李叔同
scale: C
timeSignature: 4/4
tempo: 72
tracks:
  - name: 旋律
    type: standard
    clef: treble
---
:旋律
notes: g4:e. c4:s c4:q d4:q e4:q c4:q c4:h | g4:e. c4:s c4:q d4:q e4:q c4:q c4:h | d4:e. d4:s d4:q e4:q g4:q e4:q d4:q c4:q | g4:e. g4:s g4:q e4:q g4:q c4:q c4:h
lyrics: 长 亭 外 古 道 边 芳 草 碧 连 天 晚 风 拂 柳 笛 声 残 夕 阳 山 外 山
lyrics2: 天 之 涯 地 之 角 知 交 半 零 落 一 瓢 浊 酒 尽 余 欢 今 宵 别 梦 寒
''');

    // Verify files exist.
    for (final name in [
      'scenario1_jianpu_solo_$ts.png',
      'scenario2_lyrics_$ts.png',
      'scenario3_piano_solo_$ts.png',
      'scenario4_$ts.png',
      'scenario5_staff_lyrics_$ts.png',
    ]) {
      final f = File('$outDir/$name');
      expect(f.existsSync(), isTrue, reason: '$name should exist');
      expect(f.lengthSync(), greaterThan(1000),
          reason: '$name should be a real image');
    }
  });
}
