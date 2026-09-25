import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main() {
  // Demo 数据：4/4，11 个音符（按 beat 顺序）
  final score = Score.simple(
    clef: Clef.treble,
    timeSignature: TimeSignature(4, 4),
    // Demo "送别" 的 melody: C E G C E G A A G E C + 2 rests → 11 个音符
    notes: "c4 e4 g4 c5 e5 g5 | a4 a4 g4 e4 c5 | c4 c4",  // 简化版，确保 11 个 NoteElement
  );
  final elementIds = score.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .map((el) => el.id)
      .whereType<String>()
      .toList();
  print("elementIds (${elementIds.length}): $elementIds");

  final lyricsRaw = "长亭外 古道边\n芳草碧连天\n晚风拂柳笛声残";
  final rows = lyricsRaw.split(RegExp(r'\r?\n')).map((l) => l.replaceAll(RegExp(r'\s+$'), '')).where((l) => l.isNotEmpty).toList();
  print("rows: $rows");

  final result = <Lyric>[];
  for (var v = 0; v < rows.length && v < 4; v++) {
    final verseNum = v + 1;
    final tokens = rows[v].runes.map((r) => String.fromCharCode(r)).where((c) => !RegExp(r'[\s,，、;；。.!？：:·\-]').hasMatch(c)).toList();
    for (var i = 0; i < elementIds.length && i < tokens.length; i++) {
      result.add(Lyric(elementIds[i], tokens[i], verse: verseNum));
    }
  }
  print("Total lyrics: ${result.length}");
  final byVerse = <int, int>{};
  for (final l in result) byVerse[l.verse] = (byVerse[l.verse] ?? 0) + 1;
  print("By verse: $byVerse");

  final withLyrics = score.copyWith(lyrics: result);
  print("withLyrics.lyrics length: ${withLyrics.lyrics.length}");
  print("verses present: ${withLyrics.lyrics.map((l) => l.verse).toSet().toList()}");

  // 渲染 SVG
  final settings = LayoutSettings(metadata: SmuflMetadata.fromJson({}));
  final wrapped = layoutSystems(withLyrics, settings, maxWidth: 60);
  final svg = systemsToSvg(wrapped, staffSpace: 12);
  final textCount = RegExp(r'<text').allMatches(svg).length;
  print("SVG text elements: $textCount");

  final chineseInSvg = RegExp(r'[\u4e00-\u9fff]{1,}').allMatches(svg).map((m) => m.group(0)!).toList();
  print("Chinese in SVG: $chineseInSvg");

  // 找 <text y="..."> 的 y 值
  final ys = RegExp(r'<text[^>]*y="([\d.]+)"').allMatches(svg).map((m) => double.parse(m.group(1)!)).toList();
  final uniqueYs = ys.toSet().toList()..sort();
  print("Unique y values: $uniqueYs");
  File('test_verse3.svg').writeAsStringSync(svg);
}
