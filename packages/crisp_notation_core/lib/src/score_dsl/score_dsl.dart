/// Score DSL: multi-track score description language.
///
/// A text-based format for describing an entire score — metadata, multiple
/// staff tracks (standard/jianpu), and lyrics — in one file. The DSL compiles
/// to a [StaffSystem] for rendering. See docs/SCORE_DSL.md for the full spec.
library;

import '../layout/staff_system.dart';
import '../model/element.dart' show Lyric, NoteElement;
import '../model/score.dart' show Score, ScoreMetadata, StaffType;
import '../theory/clef.dart' show Clef;
import '../theory/key_signature.dart' show KeySignature;
import '../theory/tempo.dart' show Tempo;
import '../theory/time_signature.dart' show TimeSignature;

// ---------------------------------------------------------------------------
// Document model (parsed DSL before compilation)
// ---------------------------------------------------------------------------

/// Parsed metadata from the `---score` block.
class ScoreDslMeta {
  final String title;
  final String? description;
  final String? authors;
  final String? scale;
  final String? timeSignature;
  final int? tempo;

  /// Page layout mode: `page` (default — wrap into systems at the available
  /// width) or `single` (one continuous, horizontally scrolled line).
  final String layout;
  final List<ScoreDslTrackDecl> trackDecls;

  /// UI hint: space-separated integer indices of notes to highlight.
  final List<int> highlightIndices;

  /// UI hint: whether this score block is a practice question where the user
  /// must play the notes on the keyboard before playback is unlocked.
  final bool practice;

  /// UI hint: instrument name ("piano", "guitar", "木吉他", etc.) for this
  /// score block; consumed by the renderer layer only.
  final String? instrument;

  const ScoreDslMeta({
    required this.title,
    this.description,
    this.authors,
    this.scale,
    this.timeSignature,
    this.tempo,
    this.layout = 'page',
    required this.trackDecls,
    this.highlightIndices = const [],
    this.practice = false,
    this.instrument,
  });
}

/// One track declaration from the `tracks:` list.
class ScoreDslTrackDecl {
  final String? name;
  final String type;
  final String? clef;
  final String? forTrack;
  final String? instrument;
  final String? group;

  const ScoreDslTrackDecl({
    this.name,
    required this.type,
    this.clef,
    this.forTrack,
    this.instrument,
    this.group,
  });
}

/// The body of a `:trackName` block — field values parsed from text.
class ScoreDslTrackBody {
  final String name;
  final List<String> notes;
  final Map<int, String> lyrics;
  final List<String> annotations;

  const ScoreDslTrackBody({
    required this.name,
    this.notes = const [],
    this.lyrics = const {},
    this.annotations = const [],
  });
}

/// Fully parsed DSL document: metadata + track bodies.
class ScoreDslDocument {
  final ScoreDslMeta meta;
  final List<ScoreDslTrackBody> bodies;

  const ScoreDslDocument({required this.meta, required this.bodies});
}

/// Compiled result: a [StaffSystem] ready for rendering, plus global metadata.
class ScoreDslResult {
  final StaffSystem system;
  final ScoreMetadata metadata;
  final Tempo? tempo;
  final KeySignature keySignature;
  final TimeSignature? timeSignature;

  /// Layout mode from the `---score` block (`page` or `single`).
  final String layout;

  /// UI hint copied from metadata — renderer layer only.
  final List<int> highlightIndices;
  final bool practice;
  final String? instrument;

  const ScoreDslResult({
    required this.system,
    required this.metadata,
    this.tempo,
    required this.keySignature,
    this.timeSignature,
    this.layout = 'page',
    this.highlightIndices = const [],
    this.practice = false,
    this.instrument,
  });
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Parses score DSL text into a [ScoreDslDocument].
///
/// Throws [FormatException] on malformed input, with line numbers.
ScoreDslDocument parseScoreDsl(String source) {
  final lines = source.split(RegExp(r'\r?\n'));
  var i = 0;

  // Skip leading blank/comment lines.
  while (i < lines.length && _isSkippable(lines[i])) {
    i++;
  }
  if (i >= lines.length || lines[i].trim() != '---score') {
    throw FormatException('line ${i + 1}: file must start with ---score');
  }
  i++;

  // Collect metadata lines until closing ---.
  final metaStart = i;
  while (i < lines.length && lines[i].trim() != '---') {
    i++;
  }
  if (i >= lines.length) {
    throw FormatException(
      'line $metaStart: missing --- to close metadata block');
  }
  final meta = _parseMetadata(lines.sublist(metaStart, i), metaStart);
  i++; // skip ---

  // Parse track blocks.
  final bodies = <ScoreDslTrackBody>[];
  while (i < lines.length) {
    while (i < lines.length && _isSkippable(lines[i])) {
      i++;
    }
    if (i >= lines.length) break;

    final header = lines[i].trim();
    if (!header.startsWith(':')) {
      throw FormatException(
        'line ${i + 1}: expected track block (:name), got "$header"');
    }
    final trackName = header.substring(1).trim();
    if (trackName.isEmpty) {
      throw FormatException('line ${i + 1}: track name cannot be empty');
    }
    i++;

    // Collect field lines until the next :header or end of file.
    final fieldLines = <String, List<String>>{};
    var currentField = '';
    while (i < lines.length) {
      final raw = lines[i];
      if (_isSkippable(raw)) {
        i++;
        continue;
      }
      if (raw.trim().startsWith(':')) break; // next track block

      final fm = _fieldPattern.firstMatch(raw);
      if (fm != null) {
        currentField = fm[1]!;
        // A repeated `notes:` field starts a new segment (e.g. a repeated
        // strain with fresh lyrics): auto-close a previous run that is
        // missing its trailing barline so the two segments never merge
        // into one measure. Mid-measure wraps belong on continuation
        // lines (no `notes:` prefix), which are appended verbatim.
        if (currentField == 'notes') {
          final prev = fieldLines['notes'];
          if (prev != null && prev.isNotEmpty && !prev.last.endsWith('|')) {
            prev[prev.length - 1] = '${prev.last} |';
          }
        }
        fieldLines.putIfAbsent(currentField, () => []).add(fm[2]!.trim());
      } else if (currentField.isNotEmpty) {
        fieldLines[currentField]!.add(raw.trim());
      } else {
        throw FormatException(
          'line ${i + 1}: content before any field declaration');
      }
      i++;
    }

    final notes = fieldLines['notes'] ?? [];
    final annotations = fieldLines['annotations'] ?? [];
    final lyrics = <int, String>{};
    fieldLines.forEach((key, vals) {
      if (key == 'lyrics') {
        lyrics[1] = vals.join(' ');
      } else if (key.startsWith('lyrics') && key.length > 6) {
        final n = int.tryParse(key.substring(6));
        if (n != null && n > 1) lyrics[n] = vals.join(' ');
      }
    });

    bodies.add(ScoreDslTrackBody(
      name: trackName,
      notes: notes,
      lyrics: lyrics,
      annotations: annotations,
    ));
  }

  return ScoreDslDocument(meta: meta, bodies: bodies);
}

final _fieldPattern = RegExp(r'^(notes|lyrics|lyrics\d+|annotations):(.*)$');

bool _isSkippable(String line) {
  final t = line.trim();
  return t.isEmpty || t.startsWith('#');
}

ScoreDslMeta _parseMetadata(List<String> lines, int offset) {
  String? title, description, authors, scale, timeSignature, layout;
  int? tempo;
  final trackDecls = <ScoreDslTrackDecl>[];
  var inTracks = false;
  Map<String, String>? current;
  var highlightIndices = <int>[];
  var practice = false;
  String? instrument;

  void flushCurrent() {
    if (current != null) {
      trackDecls.add(_buildTrackDecl(current!));
      current = null;
    }
  }

  for (var j = 0; j < lines.length; j++) {
    final line = lines[j];
    if (_isSkippable(line)) continue;
    final lineNo = offset + j + 1;

    if (!inTracks) {
      final m = RegExp(r'^(\w+):\s*(.*)$').firstMatch(line);
      if (m == null) {
        throw FormatException('line $lineNo: invalid metadata line "$line"');
      }
      final key = m[1]!, value = _stripQuotes(m[2]!);
      switch (key) {
        case 'title':
          title = value;
        case 'description':
          description = value;
        case 'authors':
          authors = value;
        case 'scale':
          scale = value;
        case 'timeSignature':
          timeSignature = value;
        case 'tempo':
          tempo = int.tryParse(value);
          if (tempo == null) {
            throw FormatException(
              'line $lineNo: invalid tempo "$value" (expected integer BPM)');
          }
        case 'layout':
          if (value != 'page' && value != 'single') {
            throw FormatException(
              'line $lineNo: invalid layout "$value" '
              '(expected "page" or "single")');
          }
          layout = value;
        case 'tracks':
          inTracks = true;
        // ---- renderer-level hints (not part of the score model) ----
        case 'highlight':
          highlightIndices = value
              .split(RegExp(r'\s+'))
              .map(int.tryParse)
              .whereType<int>()
              .toList();
        case 'practice':
          final v = value.toLowerCase();
          practice = v == 'true' || v == 'yes' || v == '1';
        case 'instrument':
          instrument = value;
        default:
          // Unknown metadata fields are silently ignored — this keeps
          // the parser forward-compatible with renderer-level extensions.
      }
    } else {
      final t = line.trim();
      if (t.startsWith('- ')) {
        flushCurrent();
        current = {};
        final rest = t.substring(2);
        if (rest.startsWith('{')) {
          _parseFlowMap(rest, current!, lineNo);
        } else {
          _parseKeyValue(rest, current!, lineNo);
        }
      } else if (current != null && t.isNotEmpty) {
        _parseKeyValue(t, current!, lineNo);
      }
    }
  }
  flushCurrent();

  if (title == null || title.isEmpty) {
    throw const FormatException('metadata: title is required');
  }
  if (trackDecls.isEmpty) {
    throw const FormatException('metadata: tracks list is required');
  }

  return ScoreDslMeta(
    title: title,
    description: description,
    authors: authors,
    scale: scale,
    timeSignature: timeSignature,
    tempo: tempo,
    layout: layout ?? 'page',
    trackDecls: trackDecls,
    highlightIndices: highlightIndices,
    practice: practice,
    instrument: instrument,
  );
}

void _parseFlowMap(String src, Map<String, String> target, int lineNo) {
  final s = src.trim();
  if (!s.startsWith('{') || !s.endsWith('}')) {
    throw FormatException('line $lineNo: invalid flow map "$src"');
  }
  for (final part in s.substring(1, s.length - 1).split(',')) {
    _parseKeyValue(part.trim(), target, lineNo);
  }
}

void _parseKeyValue(String src, Map<String, String> target, int lineNo) {
  final m = RegExp(r'^(\w+):\s*(.*)$').firstMatch(src);
  if (m == null) {
    throw FormatException('line $lineNo: invalid key-value "$src"');
  }
  target[m[1]!] = _stripQuotes(m[2]!.trim());
}

ScoreDslTrackDecl _buildTrackDecl(Map<String, String> f) {
  final name = f['name']?.trim();
  final type = (f['type'] ?? '').toLowerCase();
  if (type.isEmpty) {
    throw FormatException('track "${f['name']}" missing required "type" field');
  }
  return ScoreDslTrackDecl(
    name: (name == null || name.isEmpty) ? null : name,
    type: type,
    clef: f['clef'],
    forTrack: f['for'],
    instrument: f['instrument'],
    group: f['group'],
  );
}

String _stripQuotes(String v) {
  final t = v.trim();
  if ((t.startsWith('"') && t.endsWith('"') && t.length >= 2) ||
      (t.startsWith("'") && t.endsWith("'") && t.length >= 2)) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

// ---------------------------------------------------------------------------
// Compiler
// ---------------------------------------------------------------------------

/// Compiles a [ScoreDslDocument] into a [ScoreDslResult].
///
/// Validates track declarations against track bodies, builds a [Score] per
/// staff track via [Score.simple], and assembles a [StaffSystem] with brackets
/// and barline groups from `group` fields.
ScoreDslResult compileScoreDsl(ScoreDslDocument doc) {
  final keySig = _parseScale(doc.meta.scale ?? 'C');
  final timeSig = doc.meta.timeSignature != null
      ? _parseTimeSignature(doc.meta.timeSignature!)
      : null;
  final tempo = doc.meta.tempo != null ? Tempo(doc.meta.tempo!.toDouble()) : null;
  final metadata = ScoreMetadata(
    title: doc.meta.title,
    composer: doc.meta.authors,
  );

  // Build a Score for each staff track (skip lyrics tracks).
  final staves = <Score>[];
  final staffTrackNames = <String>[];
  final declIndexToStaffIndex = <int, int>{};

  for (var di = 0; di < doc.meta.trackDecls.length; di++) {
    final decl = doc.meta.trackDecls[di];
    if (decl.type == 'lyrics') continue;
    if (decl.type == 'tablature' || decl.type == 'percussion') {
      throw FormatException(
        'track type "${decl.type}" is not yet implemented');
    }

    final body = doc.bodies.firstWhere(
      (b) => b.name == decl.name,
      orElse: () => throw FormatException(
        'track "${decl.name}" has no :${decl.name} block'),
    );

    // Join all notes: lines, then drop empty measure segments: a trailing
    // barline at a manual line break is a terminator, not a ghost measure.
    final notesStr = body.notes
        .join(' ')
        .split('|')
        .where((m) => m.trim().isNotEmpty)
        .join('|');
    if (notesStr.isEmpty) {
      throw FormatException(
        'track "${decl.name}" (type: ${decl.type}) is missing notes:');
    }

    final staffType = _parseStaffType(decl.type);
    final clef = (decl.clef != null && decl.type == 'standard')
        ? (Clef.values.asNameMap()[decl.clef!] ?? Clef.treble)
        : Clef.treble;

    var score = Score.simple(
      clef: clef,
      staffType: staffType,
      keySignature: keySig,
      timeSignature: timeSig,
      notes: notesStr,
      annotations:
          body.annotations.isNotEmpty ? body.annotations.join(' ') : null,
      metadata: metadata,
      tempo: tempo,
    );

    // Attach lyrics for every verse. Tied notes (and the closing note of a
    // same-pitch slur, i.e. 同音连音线) consume no syllable, just like rests.
    if (body.lyrics.isNotEmpty) {
      final allLyrics = <Lyric>[];
      final verses = body.lyrics.keys.toList()..sort();
      for (final v in verses) {
        allLyrics.addAll(_parseLyricsWithVerse(body.lyrics[v]!, score, v));
      }
      score = score.copyWith(lyrics: allLyrics);
    }

    staves.add(score);
    staffTrackNames.add(decl.name ?? 'track$di');
    declIndexToStaffIndex[di] = staves.length - 1;
  }

  // Validate measure-count consistency across staff tracks.
  if (staves.length > 1) {
    final ref = staves.first.measures.length;
    for (var si = 1; si < staves.length; si++) {
      if (staves[si].measures.length != ref) {
        throw FormatException(
          'measure count mismatch: '
          '${staffTrackNames[0]} $ref, '
          '${staffTrackNames[si]} ${staves[si].measures.length}');
      }
    }
  }

  // Build brackets and barline groups from `group` fields.
  final brackets = <StaffBracket>[];
  final barlineGroups = <BarlineGroup>[];
  final groupOrder = <String>[];
  final groupIndices = <String, List<int>>{};

  for (var di = 0; di < doc.meta.trackDecls.length; di++) {
    final decl = doc.meta.trackDecls[di];
    if (decl.type == 'lyrics') continue;
    final g = decl.group;
    if (g == null) continue;
    groupIndices.putIfAbsent(g, () => []);
    final si = declIndexToStaffIndex[di]!;
    groupIndices[g]!.add(si);
    if (!groupOrder.contains(g)) groupOrder.add(g);
  }

  for (final g in groupOrder) {
    final indices = groupIndices[g]!;
    if (indices.length < 2) continue;
    final first = indices.reduce((a, b) => a < b ? a : b);
    final last = indices.reduce((a, b) => a > b ? a : b);
    brackets.add(StaffBracket(first, last, kind: StaffBracketKind.brace));
    barlineGroups.add(BarlineGroup(first, last));
  }

  final system = StaffSystem(
    staves,
    brackets: brackets,
    barlineGroups: barlineGroups,
  );

  return ScoreDslResult(
    system: system,
    metadata: metadata,
    tempo: tempo,
    keySignature: keySig,
    timeSignature: timeSig,
    layout: doc.meta.layout,
    highlightIndices: doc.meta.highlightIndices,
    practice: doc.meta.practice,
    instrument: doc.meta.instrument,
  );
}

/// Parses and compiles in one call.
ScoreDslResult loadScoreDsl(String source) =>
    compileScoreDsl(parseScoreDsl(source));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _majorScaleToFifths = <String, int>{
  'C': 0, 'C#': 7, 'Cb': -7,
  'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5,
  'F#': 6,
  'F': -1, 'Bb': -2, 'Eb': -3, 'Ab': -4, 'Db': -5, 'Gb': -6,
};

const _minorScaleToFifths = <String, int>{
  'A': 0, 'E': 1, 'B': 2, 'F#': 3, 'C#': 4, 'G#': 5, 'D#': 6, 'A#': 7,
  'D': -1, 'G': -2, 'C': -3, 'F': -4, 'Bb': -5, 'Eb': -6, 'Ab': -7,
};

KeySignature _parseScale(String scale) {
  final trimmed = scale.trim();
  if (trimmed.isEmpty) return const KeySignature(0);

  // 'b' alone is illegal (ambiguous with the flat sign).
  if (trimmed == 'b') {
    throw FormatException(
      'invalid scale "b" — use "Bb" for B-flat major or "B" for B major');
  }

  final isMinor = trimmed.length > 1 && trimmed.toLowerCase().endsWith('m');
  final keyPart = isMinor ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  final normalized = keyPart.length == 1
      ? keyPart.toUpperCase()
      : keyPart[0].toUpperCase() + keyPart.substring(1).toLowerCase();

  final table = isMinor ? _minorScaleToFifths : _majorScaleToFifths;
  final fifths = table[normalized];
  if (fifths == null) {
    throw FormatException(
      'invalid scale "$scale" (expected e.g. C, G, Bb, F#, Am)');
  }
  return KeySignature(fifths);
}

TimeSignature _parseTimeSignature(String source) {
  final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(source.trim());
  if (m == null) {
    throw FormatException(
      'invalid time signature "$source" (expected "N/M")');
  }
  final beats = int.parse(m[1]!);
  final beatUnit = int.parse(m[2]!);
  final ts = TimeSignature.tryParse(beats, beatUnit);
  if (ts == null) {
    throw FormatException('invalid time signature "$source"');
  }
  return ts;
}

StaffType _parseStaffType(String type) {
  switch (type) {
    case 'standard':
      return StaffType.standard;
    case 'jianpu':
      return StaffType.jianpu;
    case 'tablature':
      return StaffType.tablature;
    case 'percussion':
      return StaffType.percussion;
    default:
      throw FormatException('unknown track type "$type"');
  }
}

/// Ids of voice-1 notes that receive no lyric syllable: tie continuations
/// (`c4~ c4`, also across barlines) and the closing note of a same-pitch
/// slur (简谱同音连音线 — the note is held, not re-sung). Like rests, they are
/// skipped during lyric assignment and consume no token.
Set<String> _lyricSkippedNoteIds(Score score) {
  final skip = <String>{};

  var pendingTie = false;
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement) {
        if (pendingTie && element.id != null) skip.add(element.id!);
        pendingTie = element.tieToNext;
      } else {
        // A tie into a rest draws no curve, so nothing to skip.
        pendingTie = false;
      }
    }
  }

  final byId = <String, NoteElement>{};
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement && element.id != null) {
        byId[element.id!] = element;
      }
    }
  }
  for (final slur in score.slurs) {
    final a = byId[slur.startId];
    final b = byId[slur.endId];
    if (a == null || b == null) continue;
    if (_samePitches(a, b)) skip.add(slur.endId);
  }
  return skip;
}

bool _samePitches(NoteElement a, NoteElement b) {
  if (a.pitches.length != b.pitches.length) return false;
  for (var i = 0; i < a.pitches.length; i++) {
    if (a.pitches[i] != b.pitches[i]) return false;
  }
  return true;
}

/// Parses a lyrics string into [Lyric] objects with the given [verse] number.
/// Tokens map onto the voice-1 notes of [score] in reading order; rests and
/// the notes in [_lyricSkippedNoteIds] are passed over without consuming a
/// token, `*` explicitly skips a note.
List<Lyric> _parseLyricsWithVerse(String source, Score score, int verse) {
  final skip = _lyricSkippedNoteIds(score);
  final noteIds = <String>[
    for (final measure in score.measures)
      for (final element in measure.elements)
        if (element is NoteElement &&
            element.id != null &&
            !skip.contains(element.id))
          element.id!,
  ];
  final result = <Lyric>[];
  var index = 0;
  for (final token in source.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (index >= noteIds.length) {
      throw FormatException('more lyric tokens than notes: "$token"');
    }
    if (token == '*') {
      index++;
      continue;
    }
    final hyphen = token.endsWith('-') && token.length > 1;
    final extender = token.endsWith('_') && token.length > 1;
    final text =
        hyphen || extender ? token.substring(0, token.length - 1) : token;
    result.add(Lyric(
      noteIds[index],
      text,
      hyphenToNext: hyphen,
      extender: extender,
      verse: verse,
    ));
    index++;
  }
  return result;
}
