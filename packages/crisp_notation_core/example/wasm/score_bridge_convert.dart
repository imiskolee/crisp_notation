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
  final bool showAuthor;
  final InstrumentLabels instrumentLabels;

  /// 'system' = a number at each system start, 'all' = every measure.
  final String measureNumbers;
  final String pageSize;
  final double? pageWidthPx;
  final double? pageHeightPx;
  final double paddingPx;

  /// How paged output is assembled: 'horizontal' stacks pages left-to-right in
  /// one SVG (the score view's filmstrip); 'vertical' emits one SVG per page
  /// joined by a `<!--crisp-page-->` marker so the frontend can stack and print
  /// them (the full-score preview).
  final String pageFlow;

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
        showAuthor = (json['showAuthor'] as bool?) ?? true,
        instrumentLabels =
            _parseInstrumentLabels(json['instrumentLabels'] as String?),
        measureNumbers = (json['measureNumbers'] as String?) ?? 'system',
        pageSize = (json['pageSize'] as String?) ?? '',
        pageWidthPx = (json['pageWidthPx'] as num?)?.toDouble(),
        pageHeightPx = (json['pageHeightPx'] as num?)?.toDouble(),
        paddingPx = (json['paddingPx'] as num?)?.toDouble() ?? 0,
        pageFlow = (json['pageFlow'] as String?) ?? 'horizontal';

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

InstrumentLabels _parseInstrumentLabels(String? value) {
  switch (value) {
    case 'none':
      return InstrumentLabels.none;
    case 'page':
      return InstrumentLabels.page;
    default:
      return InstrumentLabels.first;
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

    final staffType = _parseStaffType(staffTypeName);
    final system = _prepareSystem(
      staffSystemFromAbc(abcText),
      staffType,
      opts,
    );
    return _renderStaffSystemToSvg(system, metadata, opts);
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  } on Object catch (e) {
    return 'error: $e';
  }
}

/// Resolves one engraved-header field: hidden → cleared (''), an explicit
/// override wins, else the value the score already carries.
String _resolvedField(bool show, String? override, String? current) {
  if (!show) return '';
  if (override == null) return current ?? '';
  return override.isEmpty ? '' : override;
}

/// Applies [staffType] and the requested title/author to every staff of a
/// multi-voice [system] (title/composer land on the top staff only — the one
/// the engraved title block reads). A staff whose own [Score.staffType] is
/// already non-standard (an ABC `V:… st=…` declaration) keeps its own type —
/// the per-track notation choice wins over the global [staffType].
StaffSystem _prepareSystem(
    StaffSystem system, StaffType staffType, _RenderOptions opts) {
  var staves = system.staves;
  if (staffType != StaffType.standard) {
    staves = [
      for (final s in staves)
        s.staffType == StaffType.standard
            ? s.copyWith(staffType: staffType)
            : s,
    ];
  }
  if (opts.title != null ||
      opts.author != null ||
      !opts.showTitle ||
      !opts.showAuthor) {
    final first = staves.first;
    staves = [
      first.copyWith(
        metadata: first.metadata.copyWith(
          title:
              _resolvedField(opts.showTitle, opts.title, first.metadata.title),
          composer: _resolvedField(
              opts.showAuthor, opts.author, first.metadata.composer),
        ),
      ),
      ...staves.skip(1),
    ];
  }
  return StaffSystem(staves);
}

/// Renders a multi-voice [system] (one staff per `V:` voice) to SVG — wrapped
/// at [maxWidth] with instrument labels in the left margin, or one continuous
/// line when the layout is not `wrapped`. With a [pageSize] the score
/// paginates (`layoutMultiPartPages`) and every page is stacked vertically in
/// one SVG (screen preview; print CSS splits the pages). Measure numbers:
/// 'system' prints a number at each system start, 'all' above every measure.
String _renderStaffSystemToSvg(
    StaffSystem system, SmuflMetadata metadata, _RenderOptions opts) {
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
  const textFontFamily =
      "Academico, 'New York', 'Times New Roman', Times, serif";
  const color = '#1e232b';
  const systemGap = 8.0;
  // Left margin (staff spaces) reserved for the instrument labels.
  const leftMargin = 10.0;
  final showEveryMeasure = opts.measureNumbers == 'all';
  final showSystemNumbers = opts.measureNumbers == 'system';

  if (opts.layout != 'wrapped') {
    final layout = layoutStaffSystemSingleLine(system, settings);
    return staffSystemToSvg(
      layout,
      staffSpace: staffSpace,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: background,
    );
  }

  final pageMm = opts.pageSizeMm();

  double maxWidth;
  if (pageMm != null) {
    // The page's content width drives the line breaks.
    maxWidth =
        ((pageMm.w * 96 / 25.4) - opts.paddingPx * 2) / staffSpace - leftMargin;
  } else if (opts.maxWidth > 0) {
    maxWidth = opts.maxWidth;
  } else if (opts.measuresPerLine > 0) {
    maxWidth = _probeSystemWidthForMeasures(
        system, settings, opts.measuresPerLine, leftMargin);
  } else {
    maxWidth = 56.0;
  }
  if (maxWidth <= 0) maxWidth = 56.0;

  if (pageMm == null) {
    final fullWidth = maxWidth +
        (opts.instrumentLabels == InstrumentLabels.none ? 0.0 : leftMargin);
    final wrapped = layoutStaffSystemSystems(
      system,
      settings,
      maxWidth: fullWidth,
      widthForSystem: (index) =>
          fullWidth -
          (_showInstrumentLabels(opts.instrumentLabels, index == 0)
              ? leftMargin
              : 0.0),
      justify: true,
      showMeasureNumbers: showEveryMeasure,
    );
    return staffSystemSystemsToSvg(
      wrapped,
      staffSpace: staffSpace,
      systemGap: systemGap,
      leftMargin: leftMargin,
      instrumentLabels: opts.instrumentLabels,
      showSystemMeasureNumbers: showSystemNumbers,
      numberFirstSystem: showSystemNumbers,
      showTitle: opts.showTitle,
      glyphFontFamily: glyphFontFamily,
      textFontFamily: textFontFamily,
      color: color,
      background: background,
    );
  }

  // Paged: A4 portrait/landscape, pages stacked vertically in one SVG (the
  // screen preview; print CSS splits the pages). Mirrors the single-voice
  // `_planPages`: line-break to the content width, then pack systems into
  // pages, reserving the title-block height on the first page.
  final pageWpx = opts.pageWidthPx ?? pageMm.w * 96 / 25.4;
  final pageHpx = opts.pageHeightPx ?? pageMm.h * 96 / 25.4;
  final padPx = opts.paddingPx;
  final padSs = padPx / staffSpace;
  final fullContentWidthSs = pageWpx / staffSpace - 2 * padSs;
  final contentHeightSs = pageHpx / staffSpace - 2 * padSs;

  final metadataForTitle =
      opts.showTitle ? system.staves.first.metadata : const ScoreMetadata();
  final hasTitle = opts.showTitle &&
      ((metadataForTitle.title ?? '').trim().isNotEmpty ||
          (metadataForTitle.composer ?? '').trim().isNotEmpty);
  final titleTopSs = hasTitle ? _titleBlockHeight(metadataForTitle) : 0.0;

  final wrapped = layoutStaffSystemSystems(
    system,
    settings,
    maxWidth: fullContentWidthSs > 0 ? fullContentWidthSs : 56.0,
    widthForSystem: (index) {
      final fullWidth = fullContentWidthSs > 0 ? fullContentWidthSs : 56.0;
      return fullWidth -
          (_showInstrumentLabels(opts.instrumentLabels, index == 0)
              ? leftMargin
              : 0.0);
    },
    justify: true,
    showMeasureNumbers: showEveryMeasure,
  );

  final pages = <List<StaffSystemSystem>>[];
  var current = <StaffSystemSystem>[];
  var used = 0.0;
  var available = contentHeightSs - titleTopSs;
  for (final line in wrapped.systems) {
    final need =
        current.isEmpty ? line.layout.height : systemGap + line.layout.height;
    if (current.isNotEmpty && used + need > available) {
      pages.add(current);
      current = [];
      used = 0.0;
      available = contentHeightSs;
    }
    current.add(line);
    used += need;
  }
  if (current.isNotEmpty) pages.add(current);

  final numPages = pages.isEmpty ? 1 : pages.length;

  // One SVG per page, joined by a marker the frontend splits on — screen CSS
  // stacks the pages, print CSS breaks after each so every page prints whole.
  final b = StringBuffer();
  var systemIndex = 0;
  for (var p = 0; p < numPages; p++) {
    if (p > 0) b.write('\n<!--crisp-page-->\n');
    b.write(_svgOpen(pageWpx, pageHpx, glyphFontFamily, 'none'));
    b.writeln('<rect x="0" y="0" width="${_n(pageWpx)}" '
        'height="${_n(pageHpx)}" fill="$background"/>');
    if (p == 0 && hasTitle) {
      b.writeln('<g transform="translate(${_n(padPx)} ${_n(padPx)})">');
      _emitTitleBlock(
          metadataForTitle,
          staffSpace,
          fullContentWidthSs > 0 ? fullContentWidthSs : 56.0,
          color,
          textFontFamily,
          b);
      b.writeln('</g>');
    }
    if (p < pages.length) {
      var ySs = padSs + (p == 0 ? titleTopSs : 0.0);
      for (final line in pages[p]) {
        final layout = line.layout;
        final showLabels =
            _showInstrumentLabels(opts.instrumentLabels, systemIndex == 0);
        final margin = showLabels ? leftMargin : 0.0;
        final innerX = padPx + margin * staffSpace;
        final baseY = ySs * staffSpace;
        final yPx = (ySs - layout.top) * staffSpace;
        if (showLabels) {
          _emitPagedInstrumentLabels(b, layout, staffSpace, padPx, baseY,
              margin, color, textFontFamily);
        }
        b.writeln('<g transform="translate(${_n(innerX)} ${_n(yPx)})">');
        if (showSystemNumbers) {
          // System-start bar number, same placement as
          // `staffSystemSystemsToSvg` (half a space in, one space above the
          // top staff's top line).
          b.writeln('<text x="${_n(0.5 * staffSpace)}" '
              'y="${_n((layout.staffTop(0) - layout.top - 1.0) * staffSpace)}" '
              'font-family="$textFontFamily" '
              'font-size="${_n(0.9 * staffSpace)}" text-anchor="start" '
              'fill="$color" stroke="none">${line.firstMeasure + 1}</text>');
        }
        b.write(_stripSvg(staffSystemToSvg(
          layout,
          staffSpace: staffSpace,
          glyphFontFamily: glyphFontFamily,
          textFontFamily: textFontFamily,
          color: color,
          background: 'none',
        )).content);
        b.writeln('</g>');
        ySs += layout.height + systemGap;
        systemIndex++;
      }
    }
    b.writeln('</svg>');
  }
  return b.toString();
}

bool _showInstrumentLabels(InstrumentLabels mode, bool first) =>
    mode == InstrumentLabels.first ? first : mode == InstrumentLabels.page;

void _emitPagedInstrumentLabels(
  StringBuffer b,
  StaffSystemLayout layout,
  double staffSpace,
  double contentX,
  double baseY,
  double leftMargin,
  String color,
  String textFontFamily,
) {
  var start = 0;
  while (start < layout.source.staves.length) {
    final label = layout.source.staves[start].metadata.instrument;
    if (label == null || label.trim().isEmpty) {
      start++;
      continue;
    }
    var end = start;
    while (end + 1 < layout.source.staves.length &&
        layout.source.staves[end + 1].metadata.instrument == label) {
      end++;
    }
    final top = layout.staffTop(start);
    final bottom = layout.staffTop(end) + 4;
    final x = contentX + (leftMargin - 1.0) * staffSpace;
    final y = baseY + ((top + bottom) / 2 - layout.top) * staffSpace;
    b.writeln('<text x="${_n(x)}" y="${_n(y)}" '
        'font-family="$textFontFamily" font-size="${_n(1.1 * staffSpace)}" '
        'text-anchor="end" dominant-baseline="middle" '
        'fill="$color" stroke="none">${_escape(label)}</text>');
    start = end + 1;
  }
}

double _probeSystemWidthForMeasures(
    StaffSystem system, LayoutSettings settings, int n, double leftMargin) {
  var width = 0.0;
  for (final part in system.staves) {
    if (part.measures.isEmpty) continue;
    final take = n.clamp(1, part.measures.length);
    final sub = Score(
      measures: part.measures.sublist(0, take),
      timeSignature: part.timeSignature,
      keySignature: part.keySignature,
      clef: part.clef,
      staffType: part.staffType,
    );
    final layout = layoutStaffSystemSingleLine(StaffSystem([sub]), settings);
    if (layout.width > width) width = layout.width;
  }
  return width + leftMargin + 4.0;
}

/// The engraved title/composer block (matches svg_export's `_emitTitleBlock`):
/// the title centred over [maxWidth], the composer right-aligned below.
void _emitTitleBlock(ScoreMetadata metadata, double staffSpace, double maxWidth,
    String color, String textFontFamily, StringBuffer b) {
  List<String> lines(String? text) => (text ?? '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final titleLines = lines(metadata.title);
  final composerLines = lines(metadata.composer);
  final centerX = maxWidth * staffSpace / 2;
  var y = 1.8 * staffSpace;
  for (var i = 0; i < titleLines.length; i++) {
    final size = (i == 0 ? 1.55 : 1.05) * staffSpace;
    b.writeln('<text x="${_n(centerX)}" y="${_n(y)}" '
        'font-family="$textFontFamily" font-size="${_n(size)}" '
        'font-weight="${i == 0 ? '600' : '400'}" '
        'text-anchor="middle" fill="$color" stroke="none">'
        '${_escape(titleLines[i])}</text>');
    y += (i == 0 ? 1.45 : 1.25) * staffSpace;
  }
  if (composerLines.isNotEmpty) {
    y += 0.35 * staffSpace;
    for (final line in composerLines) {
      b.writeln('<text x="${_n(maxWidth * staffSpace)}" y="${_n(y)}" '
          'font-family="$textFontFamily" font-size="${_n(0.9 * staffSpace)}" '
          'text-anchor="end" fill="$color" stroke="none">'
          '${_escape(line)}</text>');
      y += 1.05 * staffSpace;
    }
  }
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

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
            'pitches': [
              for (final pitch in element.pitches) pitch.midiNumber,
            ],
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

String _n(double value) {
  if (value.isInfinite || value.isNaN) return value.toString();
  final s = value.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _svgOpen(
    double widthPx, double heightPx, String fontFamily, String background) {
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
