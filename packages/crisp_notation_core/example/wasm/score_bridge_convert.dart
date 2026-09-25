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
  final String pageSize;
  final double paddingPx;

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
        showTitle = (json['showTitle'] as bool?) ?? true,
        pageSize = (json['pageSize'] as String?) ?? '',
        paddingPx = (json['paddingPx'] as num?)?.toDouble() ?? 0;

  ({double w, double h})? pageSizeMm() {
    switch (pageSize) {
      case 'A4':
        return (w: 210, h: 297);
      case 'A4L':
        return (w: 297, h: 210);
      default:
        return null;
    }
  }

  String resolveBackground() {
    switch (background) {
      case 'scroll': return '#ffffff';
      case 'sky': return '#eaf3fb';
      case 'custom': return backgroundCustom;
      case 'paper':
      default: return '#fffaf0';
    }
  }

  double spacingMultiplier() {
    switch (density) {
      case 'compact': return 0.8;
      case 'spacious': return 1.25;
      default: return 1.0;
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
    return 'error: ${e.message}';
  } on Object catch (e) {
    return 'error: $e';
  }
}

String abcToStudioNotes(String abcText) {
  try {
    final score = scoreFromAbc(abcText);
    final ts = score.timeSignature;
    final tsStr = ts == null ? '4/4' : '${ts.beats}/${ts.beatUnit}';
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
        final durationBeats = (duration.$1 * 4 / duration.$2).toDouble();
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
    return 'error: ${e.message}';
  } on Object catch (e) {
    return 'error: $e';
  }
}

StaffType _parseStaffType(String value) {
  switch (value) {
    case 'jianpu': return StaffType.jianpu;
    case 'tablature': return StaffType.tablature;
    case 'percussion': return StaffType.percussion;
    default: return StaffType.standard;
  }
}

String _n(double value) {
  if (value.isInfinite || value.isNaN) return value.toString();
  final s = value.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _svgOpen(double widthPx, double heightPx, String fontFamily,
    String background) {
  final sb = StringBuffer();
  sb.write('<svg xmlns="http://www.w3.org/2000/svg" ');
  sb.write('xmlns:xlink="http://www.w3.org/1999/xlink" ');
  sb.write('width="${_n(widthPx)}" height="${_n(heightPx)}" ');
  sb.writeln('viewBox="0 0 ${_n(widthPx)} ${_n(heightPx)}">');
  sb.writeln('<rect x="0" y="0" width="${_n(widthPx)}" '
      'height="${_n(heightPx)}" fill="$background"/>');
  sb.writeln('<defs><style>text{font-family:$fontFamily}</style></defs>');
  return sb.toString();
}

({String content, double w, double h}) _stripSvg(String systemsSvg) {
  final m = RegExp(
          r'<svg[^>]*width="([^"]+)"[^>]*height="([^"]+)"[^>]*>([\s\S]*?)</svg>')
      .firstMatch(systemsSvg);
  if (m == null) return (content: '', w: 0.0, h: 0.0);
  final w = double.tryParse(m.group(1)!) ?? 0.0;
  final h = double.tryParse(m.group(2)!) ?? 0.0;
  return (content: m.group(3)!, w: w, h: h);
}

double _probeWidthForMeasures(
    Score score, LayoutSettings settings, int n) {
  if (score.measures.isEmpty) return 56.0;
  final take = n < 1 ? score.measures.length : n;
  final sub = Score(
    measures: score.measures.sublist(0, take.clamp(1, score.measures.length)),
    timeSignature: score.timeSignature,
    keySignature: score.keySignature,
    clef: score.clef,
    staffType: score.staffType,
  );
  final layout = const LayoutEngine().layout(sub, settings);
  return layout.width + 4.0;
}

List<List<SystemLayout>> _planPages(
    List<SystemLayout> systems,
    double pageHStaffSpaces,
    double systemGap,
    double titleTopStaff) {
  const footer = 3.0;
  final pages = <List<SystemLayout>>[];
  var cur = <SystemLayout>[];
  var used = 0.0;
  var avail = pageHStaffSpaces - titleTopStaff - footer;

  for (final system in systems) {
    final need = cur.isEmpty
        ? system.layout.height
        : systemGap + system.layout.height;
    if (cur.isNotEmpty && used + need > avail) {
      pages.add(cur);
      cur = [];
      used = 0.0;
      avail = pageHStaffSpaces - footer;
    }
    cur.add(system);
    used += (cur.length == 1
            ? system.layout.height
            : systemGap + system.layout.height);
  }
  if (cur.isNotEmpty) pages.add(cur);
  return pages;
}

double _titleBlockHeight(ScoreMetadata metadata) {
  final titles = (metadata.title ?? '')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final composers = (metadata.composer ?? '')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  var h = 1.8;
  if (titles.isNotEmpty) {
    h += 1.55;
    if (titles.length > 1) {
      h += 1.45 + (titles.length - 2) * 1.25;
    } else {
      h += 0.6;
    }
  }
  if (composers.isNotEmpty) {
    for (var i = 0; i < composers.length; i++) {
      h += (i == 0 ? 0.35 : 0.0) + 1.05;
    }
  }
  return h + 0.8;
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

  final pageMm = opts.pageSizeMm();
  final maxWidthFromPage = pageMm == null
      ? null
      : ((pageMm.w * 96 / 25.4) - opts.paddingPx * 2) / staffSpace;
  final maxHeightFromPage = pageMm == null
      ? null
      : ((pageMm.h * 96 / 25.4) - opts.paddingPx * 2) / staffSpace;

  final useWrap = opts.layout == 'wrapped';
  double maxWidth;
  if (!useWrap) {
    maxWidth = double.infinity;
  } else if (opts.maxWidth > 0) {
    maxWidth = opts.maxWidth;
  } else if (maxWidthFromPage != null && maxWidthFromPage > 0) {
    maxWidth = maxWidthFromPage;
  } else if (opts.measuresPerLine > 0) {
    maxWidth = _probeWidthForMeasures(score, settings, opts.measuresPerLine);
  } else {
    maxWidth = 56;
  }

  final ScoreLayout? singleLineLayout;
  final MultiSystemLayout? wrapped;

  if (!useWrap) {
    if (score.staffType == StaffType.jianpu) {
      singleLineLayout = const JianpuLayoutEngine().layout(score, settings);
    } else {
      singleLineLayout = const LayoutEngine().layout(score, settings);
    }
    wrapped = null;
  } else {
    singleLineLayout = null;
    wrapped = layoutSystems(score, settings, maxWidth: maxWidth);
  }

  final metadataForTitle =
      opts.showTitle ? score.metadata : const ScoreMetadata();
  final hasTitle = opts.showTitle &&
      ((metadataForTitle.title ?? '').isNotEmpty ||
          (metadataForTitle.composer ?? '').isNotEmpty);

  if (pageMm == null) {
    if (wrapped != null) {
      return systemsToSvg(
        wrapped,
        staffSpace: staffSpace,
        systemGap: systemGap,
        metadata: hasTitle ? metadataForTitle : null,
        glyphFontFamily: glyphFontFamily,
        textFontFamily: textFontFamily,
        color: color,
        background: background,
      );
    }
    assert(singleLineLayout != null);
    return scoreToSvg(
      singleLineLayout!,
      staffSpace: staffSpace,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: background,
    );
  }

  final pageWpx = pageMm.w * 96 / 25.4;
  final pageHpx = pageMm.h * 96 / 25.4;
  final padPx = opts.paddingPx;
  const gapBetweenPagesPx = 16.0;

  if (wrapped == null) {
    assert(singleLineLayout != null);
    final inner = scoreToSvg(
      singleLineLayout!,
      staffSpace: staffSpace,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: 'none',
    );
    final innerW = singleLineLayout!.width * staffSpace;
    final innerH = singleLineLayout.height * staffSpace;
    final availW = pageWpx - padPx * 2;
    final availH = pageHpx - padPx * 2;
    var scale = 1.0;
    if (innerW > 0 && innerH > 0) {
      final sw = availW / innerW;
      final sh = availH / innerH;
      scale = sw < sh ? sw : sh;
      if (scale > 1.0) scale = 1.0;
    }
    final out = StringBuffer();
    out.write(_svgOpen(pageWpx, pageHpx, glyphFontFamily, background));
    out.writeln(
        '<g transform="translate(${_n(padPx + (availW - innerW * scale) / 2)} '
        '${_n(padPx + (availH - innerH * scale) / 2)}) scale(${_n(scale)})">');
    final s = _stripSvg(inner);
    out.write(s.content);
    out.writeln('</g></svg>');
    return out.toString();
  }

  final titleTopStaff = hasTitle
      ? _titleBlockHeight(metadataForTitle)
      : 0.0;
  final pages = maxHeightFromPage == null
      ? [wrapped.systems]
      : _planPages(
          wrapped.systems, maxHeightFromPage, systemGap, titleTopStaff);
  final numPages = pages.isEmpty ? 1 : pages.length;

  final totalWpx = numPages * pageWpx + (numPages - 1) * gapBetweenPagesPx;
  final b = StringBuffer();
  b.write(_svgOpen(totalWpx, pageHpx, glyphFontFamily, 'none'));

  var pageOrigX = 0.0;
  for (var p = 0; p < numPages; p++) {
    b.writeln('<rect x="${_n(pageOrigX)}" y="0" width="${_n(pageWpx)}" '
        'height="${_n(pageHpx)}" fill="$background"/>');

    final sub = MultiSystemLayout(
        systems: pages[p], maxWidth: wrapped.maxWidth);
    final pageSvg = systemsToSvg(
      sub,
      staffSpace: staffSpace,
      systemGap: systemGap,
      metadata: (p == 0 && hasTitle) ? metadataForTitle : null,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: 'none',
    );
    final s = _stripSvg(pageSvg);

    b.writeln(
        '<g transform="translate(${_n(pageOrigX + padPx)} ${_n(padPx)})">');
    b.write(s.content);
    b.writeln('</g>');

    pageOrigX += pageWpx + gapBetweenPagesPx;
  }
  b.writeln('</svg>');
  return b.toString();
}