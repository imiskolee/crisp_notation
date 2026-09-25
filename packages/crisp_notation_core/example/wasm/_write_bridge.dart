import "dart:io";
void main() {
  final code = """
library;

import 'dart:convert';

import 'package:crisp_notation_core/crisp_notation_core.dart';

class _RenderOptions {
  final String layout;
  final double maxWidth;
  final int measuresPerLine;
  final double staffSpace;
  final String background;
  final String backgroundCustom;
  final String density;
  final String? title;
  final String? author;
  final bool showTitle;

  _RenderOptions.fromJson(Map<String, dynamic> json)
      : layout = (json['layout'] as String?) ?? 'wrapped',
        maxWidth = (json['maxWidth'] as num?)?.toDouble() ?? 0.0,
        measuresPerLine = (json['measuresPerLine'] as int?) ?? 0,
        staffSpace = (json['staffSpace'] as num?)?.toDouble() ?? 7.5,
        background = (json['background'] as String?) ?? 'paper',
        backgroundCustom = (json['backgroundCustom'] as String?) ?? '#ffffff',
        density = (json['density'] as String?) ?? 'normal',
        title = json['title'] as String?,
        author = json['author'] as String?,
        showTitle = (json['showTitle'] as bool?) ?? true;

  String resolveBackground() {
    switch (background) {
      case 'scroll':
        return '#ffffff';
      case 'sky':
        return '#eaf3fb';
      case 'custom':
        return backgroundCustom;
      case 'paper':
      default:
        return '#fffaf0';
    }
  }

  double spacingMultiplier() {
    switch (density) {
      case 'compact':
        return 0.8;
      case 'spacious':
        return 1.25;
      default:
        return 1.0;
    }
  }
}

String abcToSvg(String abcText, String bravuraMetaJson, String staffTypeName,
    [String optionsJson = '{}']) {
  try {
    final metaJson = jsonDecode(bravuraMetaJson);
    if (metaJson is! Map<String, dynamic>) {
      throw const FormatException('bravura metadata must be a JSON object');
    }
    final metadata =
        SmuflMetadata.fromJson(Map<String, Object?>.from(metaJson));
    final opts = optionsJson.isEmpty
        ? _RenderOptions.fromJson({})
        : _RenderOptions.fromJson(
            jsonDecode(optionsJson) as Map<String, dynamic>);

    var score = scoreFromAbc(abcText);
    final staffType = _parseStaffType(staffTypeName);
    if (staffType != StaffType.standard) {
      score = score.copyWith(staffType: staffType);
    }

    if (opts.title != null || opts.author != null) {
      score = score.copyWith(
        metadata: score.metadata.copyWith(
          title: opts.title == null
              ? score.metadata.title
              : (opts.title!.isEmpty ? '' : opts.title),
          composer: opts.author == null
              ? score.metadata.composer
              : (opts.author!.isEmpty ? '' : opts.author),
        ),
      );
    }

    return _renderScoreToSvg(score, metadata, opts);
  } on FormatException catch (e) {
    return 'error: \${e.message}';
  } on Object catch (e) {
    return 'error: \$e';
  }
}

String abcToStudioNotes(String abcText) {
  try {
    final score = scoreFromAbc(abcText);

    final ts = score.timeSignature;
    final tsStr = ts == null ? '4/4' : '\${ts.beats}/\${ts.beatUnit}';
    final quarterBpm = score.tempo?.quarterBpm ?? 100.0;
    final title = score.metadata.title ?? '';

    final lyricById = <String, String>{};
    final v1 = score.lyrics.where((l) => l.verse == 1).toList();
    final verseLyrics = v1.isNotEmpty ? v1 : score.lyrics;
    for (final lyric in verseLyrics) {
      lyricById.putIfAbsent(lyric.elementId, () => lyric.text);
    }

    final notes = <Map<String, Object?>>[];
    double beatCursor = 0;
    for (final measure in score.measures) {
      for (final element in measure.elements) {
        final duration = element.duration.fraction;
        final durationBeats = (duration.\$1 * 4 / duration.\$2).toDouble();
        if (element is NoteElement && element.pitches.isNotEmpty) {
          notes.add({
            'beat': beatCursor,
            'duration': durationBeats,
            'pitch': element.pitches.first.midiNumber,
            'lyric': lyricById[element.id] ?? '',
          });
        }
        beatCursor += durationBeats;
      }
    }

    return jsonEncode({
      'title': title,
      'bpm': quarterBpm,
      'timeSignature': tsStr,
      'notes': notes,
    });
  } on FormatException catch (e) {
    return 'error: \${e.message}';
  } on Object catch (e) {
    return 'error: \$e';
  }
}

StaffType _parseStaffType(String value) {
  switch (value) {
    case 'jianpu':
      return StaffType.jianpu;
    case 'tablature':
      return StaffType.tablature;
    case 'percussion':
      return StaffType.percussion;
    default:
      return StaffType.standard;
  }
}

String _renderScoreToSvg(
    Score score, SmuflMetadata metadata, _RenderOptions opts) {
  final m = opts.spacingMultiplier();
  final settings = LayoutSettings(
    metadata: metadata,
    spacingBase: 1.8 * m,
    spacingPerLog2: 0.75 * m,
    minNoteGap: 0.6 * m,
  );

  final staffSpace = opts.staffSpace;
  final background = opts.resolveBackground();
  const glyphFontFamily = 'Bravura';
  const textFontFamily = "Academico, 'New York', 'Times New Roman', Times, serif";
  const color = '#1e232b';
  const systemGap = 8.0;

  final useWrap = opts.layout == 'wrapped';
  final maxWidth = opts.maxWidth;

  if (useWrap && maxWidth > 0) {
    final MultiSystemLayout wrapped =
        layoutSystems(score, settings, maxWidth: maxWidth);
    final metadataForTitle =
        opts.showTitle ? score.metadata : const ScoreMetadata();
    return systemsToSvg(
      wrapped,
      staffSpace: staffSpace,
      systemGap: systemGap,
      metadata: metadataForTitle,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: background,
    );
  }

  final ScoreLayout layout;
  if (score.staffType == StaffType.jianpu) {
    layout = const JianpuLayoutEngine().layout(score, settings);
  } else {
    layout = const LayoutEngine().layout(score, settings);
  }
  return scoreToSvg(
    layout,
    staffSpace: staffSpace,
    glyphFontFamily: glyphFontFamily,
    textFontFamily: textFontFamily,
    color: color,
    background: background,
  );
}
""";
  File(r"d:\develop\src\fortdyn\crisp_notation\packages\crisp_notation_core\example\wasm\score_bridge_convert.dart").writeAsStringSync(code.trimLeft());
  print("wrote score_bridge_convert.dart");
}
