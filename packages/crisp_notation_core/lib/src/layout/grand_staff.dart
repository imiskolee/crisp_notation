/// Grand staff (system) layout: two staves with aligned measures.
library;

import 'dart:math';

import '../model/element.dart';
import '../model/score.dart';
import '../theory/fraction.dart';
import '../theory/tuning.dart';
import 'jianpu_layout.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'score_layout.dart';
import 'tab_layout.dart';

/// Lays out one staff of a multi-staff system, routing to the engine the
/// score's [StaffType] picks. Jianpu takes the column-alignment contract
/// ([leadingWidth]/[measureWidths]/[forcedColumns]) but not the staff-only
/// overlays (deferred stems, note-name labels, target-width padding) —
/// those are no-ops on a digit row.
ScoreLayout layoutStaff(
  Score score,
  LayoutSettings settings, {
  required double? leadingWidth,
  required List<double>? measureWidths,
  required List<Map<Fraction, double>>? forcedColumns,
  required double spacingStretch,
  required bool drawTimeSignature,
  required bool finalBarline,
  Map<String, bool> deferredStems = const {},
  double? targetWidth,
  List<double>? measureStartXs,
  double? minimumWidth,
  bool showNoteNames = false,
  bool showNoteOctaves = false,
  NoteNameStyle noteNameStyle = NoteNameStyle.letter,
  bool showMeasureNumbers = false,
  int measureNumberInterval = 1,
  int measureNumberOffset = 0,
}) {
  if (score.staffType == StaffType.jianpu) {
    return const JianpuLayoutEngine().layout(
      score,
      settings,
      leadingWidth: leadingWidth,
      measureWidths: measureWidths,
      forcedColumns: forcedColumns,
      measureStartXs: measureStartXs,
      minimumWidth: minimumWidth,
      barlineXs: targetWidth == null
          ? null
          : [targetWidth - settings.thinBarlineThickness / 2],
      spacingStretch: spacingStretch,
      // 简谱不画行首的 "1=X 4/4"：调号标签本就不传（默认 false），拍号在
      // 这里也压掉。曲中变调/变拍由引擎无条件标出，不受此影响。
      drawTimeSignature: false,
      finalBarline: finalBarline,
    );
  }
  if (score.staffType == StaffType.tablature) {
    return const TabLayoutEngine().layout(
      score,
      Tuning.standardGuitar,
      settings,
      finalBarline: finalBarline,
      leadingWidth: leadingWidth,
      measureWidths: measureWidths,
      forcedColumns: forcedColumns,
      measureStartXs: measureStartXs,
      minimumWidth: minimumWidth,
      barlineXs: targetWidth == null
          ? null
          : [targetWidth - settings.thinBarlineThickness / 2],
    );
  }
  return const LayoutEngine().layout(
    score,
    settings,
    leadingWidth: leadingWidth,
    measureWidths: measureWidths,
    forcedColumns: forcedColumns,
    measureStartXs: measureStartXs,
    minimumWidth: minimumWidth,
    deferredStems: deferredStems,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    targetWidth: targetWidth,
    spacingStretch: spacingStretch,
    showNoteNames: showNoteNames,
    showNoteOctaves: showNoteOctaves,
    noteNameStyle: noteNameStyle,
    showMeasureNumbers: showMeasureNumbers,
    measureNumberInterval: measureNumberInterval,
    measureNumberOffset: measureNumberOffset,
  );
}

/// Cross-staff onset gridding (§2.9): shared per-measure column positions
/// (onset → the **notehead** x from the measure's content start) that align
/// simultaneous notes across [staves], which must share measures (all voices
/// participate). Feed the result to `LayoutEngine.layout`'s `forcedColumns` for
/// every staff so their noteheads land on the same columns and accidentals
/// extend left. Column gaps are the optical time-spacing, floored so one
/// column's right ink (notehead/stem/dots) never collides with the next
/// column's left ink (accidental).
List<Map<Fraction, double>> alignedColumns(
  List<Score> staves,
  LayoutSettings settings, {
  double spacingStretch = 1.0,
  double? timelineBeatWidth,
}) {
  final timeline = _collectTimeline(staves);
  if (timeline.isEmpty) return const [];
  if (timelineBeatWidth != null) {
    return [
      for (final measure in timeline)
        {
          for (final time in measure.times)
            time - measure.start:
                (time - measure.start).toDouble() * 4 * timelineBeatWidth,
          for (var time = Fraction.zero;
              time < measure.end - measure.start;
              time += Fraction(1, 4))
            time: time.toDouble() * 4 * timelineBeatWidth,
        },
    ];
  }
  final durationInk = [
    for (final _ in staves) <String, List<double>>{},
  ];
  final ink = [
    for (var si = 0; si < staves.length; si++)
      _inkMetrics(
        layoutStaff(staves[si], settings,
            leadingWidth: null,
            measureWidths: null,
            forcedColumns: null,
            spacingStretch: 1,
            drawTimeSignature: true,
            finalBarline: true),
        settings,
        isJianpu: staves[si].staffType == StaffType.jianpu,
        isTab: staves[si].staffType == StaffType.tablature,
        durationInk: durationInk[si],
      ),
  ];
  return [
    for (final measure in timeline)
      _mapTimeline(measure, staves, ink, settings, spacingStretch, durationInk),
  ];
}

typedef _TimedEvent = ({
  int staff,
  MusicElement element,
  Fraction start,
  Fraction end,
});

typedef _MeasureTimeline = ({
  Fraction start,
  Fraction end,
  List<_TimedEvent> events,
  Set<Fraction> times,
});

List<_MeasureTimeline> _collectTimeline(List<Score> staves) {
  if (staves.isEmpty) return const [];
  final result = <_MeasureTimeline>[];
  var start = Fraction.zero;
  for (var m = 0; m < staves.first.measures.length; m++) {
    final events = <_TimedEvent>[];
    var contentEnd = start;
    var noteEnd = start;
    for (var si = 0; si < staves.length; si++) {
      final measure = staves[si].measures[m];
      final voices = [
        measure.elements,
        measure.voice2,
        measure.voice3,
        measure.voice4,
      ];
      for (var v = 0; v < voices.length; v++) {
        var onset = start;
        for (var i = 0; i < voices[v].length; i++) {
          final element = voices[v][i];
          final duration = measure.effectiveDurationAt(i, voice: v);
          final end = onset + duration;
          events.add((staff: si, element: element, start: onset, end: end));
          onset = end;
          if (element is NoteElement && duration > Fraction.zero) {
            if (onset > noteEnd) noteEnd = onset;
          }
        }
        if (onset > contentEnd) contentEnd = onset;
      }
    }
    final capacity = _sharedMeasureCapacity(staves, m);
    final capacityEnd = start + capacity.length;
    final end = capacity.hasExplicitDuration ||
            contentEnd >= capacityEnd ||
            contentEnd == start ||
            (noteEnd < contentEnd && contentEnd < capacityEnd)
        ? capacityEnd
        : contentEnd;
    final times = <Fraction>{start, end};
    for (final event in events) {
      for (final time in [event.start, event.end]) {
        if (time >= start && time <= end) times.add(time);
      }
    }
    result.add((start: start, end: end, events: events, times: times));
    start = end;
  }
  return result;
}

Map<Fraction, double> _mapTimeline(
  _MeasureTimeline measure,
  List<Score> staves,
  List<Map<String, ({double anchor, double left, double right})>> ink,
  LayoutSettings settings,
  double spacingStretch,
  List<Map<String, List<double>>> durationInk,
) {
  final times = measure.times.toList()..sort();
  final bounds = [
    for (var si = 0; si < staves.length; si++)
      <Fraction, ({double left, double right})>{},
  ];
  final groups = <(int, Fraction), List<_TimedEvent>>{};
  for (final event in measure.events) {
    if (event.start < measure.start || event.start >= measure.end) continue;
    final centered = staves[event.staff].staffType == StaffType.standard &&
        event.element is RestElement &&
        event.start == measure.start &&
        event.end == measure.end;
    final elementId = event.element.id;
    if (centered || elementId == null || ink[event.staff][elementId] == null) {
      continue;
    }
    groups.putIfAbsent((event.staff, event.start), () => []).add(event);
  }
  var padding = 0.0;
  for (final entry in groups.entries) {
    final metrics = [
      for (final event in entry.value) ink[event.staff][event.element.id]!,
    ];
    final anchor = metrics.map((metric) => metric.anchor).reduce(min);
    final left = metrics
        .map((metric) => metric.left - (metric.anchor - anchor))
        .reduce(max);
    final right = metrics
        .map((metric) => metric.right + metric.anchor - anchor)
        .reduce(max);
    final time = entry.key.$2 - measure.start;
    bounds[entry.key.$1][time] = (left: max(0, left), right: max(0, right));
    if (time == Fraction.zero) padding = max(padding, left);
  }
  var x = padding;
  final columns = <Fraction, double>{times.first - measure.start: x};
  for (var i = 1; i < times.length; i++) {
    final from = times[i - 1] - measure.start;
    final to = times[i] - measure.start;
    var right = 0.0;
    var left = 0.0;
    for (final staff in bounds) {
      right = max(right, staff[from]?.right ?? 0);
      left = max(left, staff[to]?.left ?? 0);
    }
    final advance = max(
      _idealAdvanceFor(to - from, settings, 1),
      right + left + settings.minNoteGap,
    );
    x += advance * spacingStretch;
    columns[to] = x;
  }
  if (settings.spacingPolicy != SpacingPolicy.equalBeat || times.length < 2) {
    return columns;
  }

  final start = times.first - measure.start;
  final end = times.last - measure.start;
  final opticalWidth = columns[end]! - columns[start]!;
  final equal = <Fraction, double>{
    start: columns[start]!,
    for (var i = 1; i < times.length; i++)
      times[i] - measure.start: columns[start]! +
          opticalWidth *
              ((times[i] - measure.start).toDouble() / end.toDouble()),
  };
  for (final event in measure.events) {
    if (event.start < measure.start || event.start >= measure.end) continue;
    final widths = durationInk[event.staff][event.element.id];
    if (widths == null) continue;
    for (var i = 0; i < widths.length; i++) {
      final time = event.start - measure.start + Fraction(i + 1, 4);
      final previous = bounds[event.staff][time];
      bounds[event.staff][time] = (
        left: max(previous?.left ?? 0, widths[i]),
        right: max(previous?.right ?? 0, widths[i]),
      );
    }
  }
  for (final staff in bounds) {
    final entries = staff.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    var rightEdge = double.negativeInfinity;
    for (final entry in entries) {
      final position = equal[start]! +
          opticalWidth * (entry.key.toDouble() / end.toDouble()).clamp(0, 1);
      if (position - entry.value.left + 1e-9 <
          rightEdge + settings.minNoteGap) {
        return columns;
      }
      rightEdge = max(rightEdge, position + entry.value.right);
    }
  }
  return equal;
}

Map<String, ({double anchor, double left, double right})> _inkMetrics(
  ScoreLayout layout,
  LayoutSettings settings, {
  bool isJianpu = false,
  bool isTab = false,
  required Map<String, List<double>> durationInk,
}) {
  final anchors = <String, double>{};
  final left = <String, double>{};
  final right = <String, double>{};
  for (final primitive in layout.primitives) {
    final id = primitive.elementId;
    if (id == null) continue;
    if (primitive is GlyphPrimitive &&
        (primitive.smuflName.startsWith('notehead') ||
            primitive.smuflName.startsWith('rest'))) {
      anchors.putIfAbsent(id, () => primitive.position.x);
    } else if (primitive is TextPrimitive &&
        ((isJianpu && RegExp(r'^[0-7]$').hasMatch(primitive.text)) ||
            (isTab &&
                RegExp(r'^(?:-?\d{1,2}|\(\d{1,2}\)|<\d{1,2}>|x)$')
                    .hasMatch(primitive.text)))) {
      anchors.putIfAbsent(id, () => primitive.position.x);
    }
  }
  for (final primitive in layout.primitives) {
    final id = primitive.elementId;
    if (id == null) continue;
    double l;
    double r;
    if (primitive is GlyphPrimitive) {
      final box = settings.metadata.bBoxOf(primitive.smuflName);
      l = primitive.position.x + box.swX * primitive.scale;
      r = primitive.position.x + box.neX * primitive.scale;
    } else if (primitive is TextPrimitive) {
      if (isJianpu &&
          anchors[id] != primitive.position.x &&
          primitive.text == '0') {
        durationInk.putIfAbsent(id, () => []).add(0.225 * primitive.size);
        continue;
      }
      final half = isJianpu && RegExp(r'^[0-7]$').hasMatch(primitive.text)
          ? 0.225 * primitive.size
          : 0.28 * primitive.size * primitive.text.length;
      l = primitive.position.x - half;
      r = primitive.position.x + half;
    } else if (primitive is LinePrimitive) {
      if (isJianpu && primitive.from.y == primitive.to.y) {
        if (anchors[id] != null &&
            (primitive.from.x + primitive.to.x) / 2 > anchors[id]!) {
          durationInk.putIfAbsent(id, () => []).add(
              (primitive.to.x - primitive.from.x).abs() / 2 +
                  primitive.thickness / 2);
        }
        continue;
      }
      l = min(primitive.from.x, primitive.to.x) - primitive.thickness / 2;
      r = max(primitive.from.x, primitive.to.x) + primitive.thickness / 2;
    } else {
      continue;
    }
    left[id] = min(left[id] ?? l, l);
    right[id] = max(right[id] ?? r, r);
  }
  return {
    for (final entry in anchors.entries)
      entry.key: (
        anchor: entry.value,
        left: max(0, entry.value - (left[entry.key] ?? entry.value)),
        right: max(0, (right[entry.key] ?? entry.value) - entry.value)
      ),
  };
}

({Fraction length, bool hasExplicitDuration}) _sharedMeasureCapacity(
  List<Score> staves,
  int measureIndex,
) {
  var length = Fraction.zero;
  var hasExplicitDuration = false;

  for (final score in staves) {
    if (measureIndex >= score.measures.length) continue;

    var meter = score.timeSignature;
    for (var i = 0; i <= measureIndex; i++) {
      final change = score.measures[i].timeChange;
      if (change != null) meter = change;
    }

    final measure = score.measures[measureIndex];
    final capacity = measure.capacityGiven(meter);
    if (capacity != null && capacity > length) {
      length = capacity;
    }
    if (measure.actualDuration != null) hasExplicitDuration = true;
  }

  return (
    length: length == Fraction.zero ? Fraction(1, 1) : length,
    hasExplicitDuration: hasExplicitDuration,
  );
}

/// The optical time-based spacing for an onset gap of [delta] (mirrors the
/// engine's `_idealAdvance`).
double _idealAdvanceFor(Fraction delta, LayoutSettings s, double stretch) {
  if (delta.numerator <= 0) return 0;
  final log2Delta = log(delta.numerator / delta.denominator) / ln2;
  return (s.spacingBase + s.spacingPerLog2 * (4 + log2Delta)) * stretch;
}

/// A beam that spans both staves of a grand staff, joining notes written on
/// the [upper] and [lower] staves under one beam — the keyboard "cross-staff"
/// beam (e.g. a broken-chord figure that reaches from the bass staff up into
/// the treble). Lists the ids of the notes it beams; each note stays on the
/// staff it is written on. Upper-staff notes stem down toward the beam, lower-
/// staff notes stem up, and the beam is drawn between the staves.
///
/// The notes should be eighths or shorter (they carry a beam) and span both
/// staves; a group confined to one staff should use ordinary beaming instead.
class CrossStaffBeam {
  /// Ids of the notes joined by this beam, left to right.
  final List<String> noteIds;

  /// Creates a cross-staff beam over [noteIds].
  const CrossStaffBeam(this.noteIds);

  @override
  bool operator ==(Object other) =>
      other is CrossStaffBeam && _sameIds(other.noteIds, noteIds);

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(noteIds);

  @override
  String toString() => 'CrossStaffBeam($noteIds)';
}

/// Two scores stacked as one system — typically a treble [upper] and a
/// bass [lower] staff (piano/grand staff).
///
/// Element ids should be unique across both scores so interaction stays
/// unambiguous.
class GrandStaff {
  /// The upper staff.
  final Score upper;

  /// The lower staff.
  final Score lower;

  /// Beams that span both staves (keyboard cross-staff beams). Empty for an
  /// ordinary grand staff.
  final List<CrossStaffBeam> crossStaffBeams;

  /// Creates a grand staff.
  const GrandStaff({
    required this.upper,
    required this.lower,
    this.crossStaffBeams = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is GrandStaff &&
      other.upper == upper &&
      other.lower == lower &&
      _sameBeams(other.crossStaffBeams, crossStaffBeams);

  static bool _sameBeams(List<CrossStaffBeam> a, List<CrossStaffBeam> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(upper, lower, Object.hashAll(crossStaffBeams));

  @override
  String toString() => 'GrandStaff($upper / $lower)';
}

/// The laid-out grand staff: both staff layouts share leading width,
/// per-measure widths and total width, so barlines align vertically.
///
/// Staff-space coordinates are **per staff** (each layout has its own
/// origin at its top line); the renderer stacks them [staffGap] spaces
/// apart (bottom line of the upper staff to top line of the lower).
class GrandStaffLayout {
  /// Layout of the upper staff.
  final ScoreLayout upper;

  /// Layout of the lower staff.
  final ScoreLayout lower;

  /// Vertical distance in staff spaces from the upper staff's bottom
  /// line (y = 4) to the lower staff's top line (y = 0).
  final double staffGap;

  /// Creates a grand-staff layout.
  const GrandStaffLayout({
    required this.upper,
    required this.lower,
    required this.staffGap,
  });

  /// Shared total width in staff spaces.
  double get width => upper.width;

  /// Total height in staff spaces: the upper staff's box, the gap, and
  /// the lower staff's box below its top line.
  double get height =>
      (4 - upper.top) + staffGap + (lower.top + lower.height - 0);

  @override
  String toString() => 'GrandStaffLayout(${width}x$height)';
}

/// Lays out a [GrandStaff]: each staff is laid out once to discover its
/// natural leading and per-measure widths, then both are laid out again
/// with the column-wise maxima so barlines align.
///
/// Throws an [ArgumentError] if the staves disagree on measure count.
GrandStaffLayout layoutGrandStaff(
  GrandStaff grandStaff,
  LayoutSettings settings, {
  double staffGap = 4.0,
  bool drawTimeSignature = true,
  bool finalBarline = true,
  double spacingStretch = 1.0,
  bool gridAlign = true,
  bool showNoteNames = false,
  bool showNoteOctaves = false,
  NoteNameStyle noteNameStyle = NoteNameStyle.letter,
}) {
  if (grandStaff.upper.measures.length != grandStaff.lower.measures.length) {
    throw ArgumentError(
      'Grand staff staves must have the same measure count '
      '(${grandStaff.upper.measures.length} vs '
      '${grandStaff.lower.measures.length})',
    );
  }
  // The natural passes carry the same [spacingStretch] as the final passes, so
  // the shared [measureWidths] grow with the stretch and both staves stay
  // aligned (a wider stretch fills the line, distributed as note spacing).
  // Each staff routes to its own engine (staff vs jianpu) so a mixed system
  // measures each notation's natural leading and widths correctly.
  final upperNatural = layoutStaff(grandStaff.upper, settings,
      leadingWidth: null,
      measureWidths: null,
      forcedColumns: null,
      spacingStretch: spacingStretch,
      drawTimeSignature: drawTimeSignature,
      finalBarline: finalBarline);
  final lowerNatural = layoutStaff(grandStaff.lower, settings,
      leadingWidth: null,
      measureWidths: null,
      forcedColumns: null,
      spacingStretch: spacingStretch,
      drawTimeSignature: drawTimeSignature,
      finalBarline: finalBarline);

  double leadingOf(ScoreLayout layout) => layout.measureRegions.isEmpty
      ? layout.width
      : layout.measureRegions.first.startX;
  final leading =
      [leadingOf(upperNatural), leadingOf(lowerNatural)].reduce(_max);
  final measureWidths = <double>[
    for (var i = 0; i < upperNatural.measureRegions.length; i++)
      _max(
        upperNatural.measureRegions[i].endX -
            upperNatural.measureRegions[i].startX,
        lowerNatural.measureRegions[i].endX -
            lowerNatural.measureRegions[i].startX,
      ),
  ];

  // Cross-staff beams: an upper-staff note stems down toward the beam, a
  // lower-staff note stems up. Defer those stems so the engine draws the
  // notehead but no stem/flag, then draw the connecting beam here where the
  // inter-staff [staffGap] is known. Jianpu staves have no stems, so the
  // beam's ids never resolve on a jianpu staff and the deferral map stays
  // empty — cross-staff beams are a standard-staff-only feature.
  final upperIds = _elementIds(grandStaff.upper);
  final lowerIds = _elementIds(grandStaff.lower);
  final deferUpper = <String, bool>{};
  final deferLower = <String, bool>{};
  for (final beam in grandStaff.crossStaffBeams) {
    for (final id in beam.noteIds) {
      if (upperIds.contains(id)) {
        deferUpper[id] = true; // stem down
      } else if (lowerIds.contains(id)) {
        deferLower[id] = false; // stem up
      }
    }
  }

  // §2.9: align simultaneous notes across the two staves (all voices).
  // alignedColumns uses the staff engine's notehead positions for every
  // staff — a jianpu digit anchors at the same x as a staff notehead at
  // the same onset, which is exactly the alignment we want.
  final columns = gridAlign
      ? alignedColumns([grandStaff.upper, grandStaff.lower], settings,
          spacingStretch: spacingStretch)
      : null;

  final upper = layoutStaff(
    grandStaff.upper,
    settings,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    spacingStretch: spacingStretch,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    deferredStems: deferUpper,
    showNoteNames: showNoteNames,
    showNoteOctaves: showNoteOctaves,
    noteNameStyle: noteNameStyle,
  );
  final lower = layoutStaff(
    grandStaff.lower,
    settings,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    spacingStretch: spacingStretch,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    deferredStems: deferLower,
    showNoteNames: showNoteNames,
    showNoteOctaves: showNoteOctaves,
    noteNameStyle: noteNameStyle,
  );

  final beamPrimitives = _crossStaffBeamPrimitives(
    grandStaff.crossStaffBeams,
    upper,
    lower,
    settings,
    staffGap,
  );

  return GrandStaffLayout(
    // The cross-staff beams are drawn in the upper staff's frame (the lower
    // staff sits `4 + staffGap` spaces below), so appending them to the upper
    // layout paints them with the existing renderer, spanning both staves.
    upper: beamPrimitives.isEmpty
        ? upper
        : ScoreLayout(
            width: upper.width,
            height: upper.height,
            top: upper.top,
            primitives: [...upper.primitives, ...beamPrimitives],
            regions: upper.regions,
            measureRegions: upper.measureRegions,
            crossStaffStubs: upper.crossStaffStubs,
          ),
    lower: lower,
    staffGap: staffGap,
  );
}

/// The ids of every element in [score] (across all voices).
Set<String> _elementIds(Score score) => {
      for (final measure in score.measures)
        for (final voice in measure.voices)
          for (final element in voice)
            if (element.id != null) element.id!,
    };

/// Builds the stem + beam primitives for each [beams] group, in the upper
/// staff's frame (a lower-staff stub's y is shifted down by `4 + staffGap`).
List<LayoutPrimitive> _crossStaffBeamPrimitives(
  List<CrossStaffBeam> beams,
  ScoreLayout upper,
  ScoreLayout lower,
  LayoutSettings settings,
  double staffGap,
) {
  final out = <LayoutPrimitive>[];
  for (final beam in beams) {
    // (stemX, attachY in the upper frame, whether the note stems down).
    final pts = <({double x, double attachY, bool down})>[];
    for (final id in beam.noteIds) {
      final u = upper.crossStaffStubs[id];
      if (u != null) {
        pts.add((x: u.stemX, attachY: u.attachY, down: true));
        continue;
      }
      final l = lower.crossStaffStubs[id];
      if (l != null) {
        pts.add((x: l.stemX, attachY: l.attachY + 4 + staffGap, down: false));
      }
    }
    if (pts.length < 2) continue;
    pts.sort((a, b) => a.x.compareTo(b.x));

    // The beam sits between the innermost notes of the two staves (or midway
    // in the gap if the notes are all on one staff).
    final downYs = [
      for (final p in pts)
        if (p.down) p.attachY
    ];
    final upYs = [
      for (final p in pts)
        if (!p.down) p.attachY
    ];
    final beamY = downYs.isNotEmpty && upYs.isNotEmpty
        ? (downYs.reduce(max) + upYs.reduce(min)) / 2
        : 4 + staffGap / 2;

    for (final p in pts) {
      out.add(LinePrimitive(
        Point(p.x, p.attachY),
        Point(p.x, beamY),
        thickness: settings.stemThickness,
      ));
    }
    out.add(BeamPrimitive(
      Point(pts.first.x, beamY),
      Point(pts.last.x, beamY),
      thickness: settings.beamThickness,
    ));
  }
  return out;
}

double _max(double a, double b) => a > b ? a : b;
