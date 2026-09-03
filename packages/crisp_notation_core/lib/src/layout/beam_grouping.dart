import '../theory/fraction.dart';
import '../theory/time_signature.dart';

/// How one element participates in beam/underline grouping (shared by the
/// staff beam pass and the jianpu 减时线 pass).
enum BeamItemRole {
  /// Carries beam segments and joins a run (a note of eighth or shorter —
  /// and, in jianpu, a short rest, which carries its own underline).
  beamable,

  /// Never joins a run but does not break one either: a staff rest the beam
  /// simply passes over within the same metric window.
  transparent,

  /// Breaks the current run (a quarter-or-longer element).
  breaker,
}

/// The beam-window start onsets of one measure (cumulative, always starting
/// at zero) — the metric units notes beam within. This is the single source
/// of grouping for every notation type: staff beams, jianpu underlines.
///
/// For most meters these are [TimeSignature.beamGroups] accumulated. One
/// layout-level rule goes beyond the raw meter model: three-beat meters on
/// an eighth/sixteenth beat (3/8, 3/16) beam the whole measure as one group
/// (GB/T 46845-2025 §6.3.5.3 for jianpu; the same whole-measure group is
/// standard staff practice for 3/8).
List<Fraction> beamGroupBoundaries(TimeSignature time) {
  if ((time.beatUnit == 8 || time.beatUnit == 16) && time.beats == 3) {
    return [Fraction.zero];
  }
  final boundaries = <Fraction>[];
  var acc = Fraction.zero;
  for (final g in time.beamGroups()) {
    boundaries.add(acc);
    acc += g;
  }
  return boundaries;
}

/// Groups the beamable items of one measure into runs of consecutive
/// indices sharing one metric window ([beamGroupBoundaries]; a quarter-note
/// window when [time] is null). Both beam runs never cross a [spanAt]
/// boundary in either direction (tuplet isolation).
///
/// Roles: [BeamItemRole.beamable] joins/starts a run,
/// [BeamItemRole.transparent] is skipped without breaking the current run,
/// [BeamItemRole.breaker] ends it. Runs of any length are returned; the
/// caller decides the minimum (staff beams need ≥ 2, a lone jianpu digit
/// still gets its underline).
List<List<int>> computeBeamRuns({
  required int count,
  required Fraction Function(int index) onsetAt,
  required BeamItemRole Function(int index) roleAt,
  required TimeSignature? time,
  int Function(int index)? spanAt,
}) {
  final boundaries = time == null ? null : beamGroupBoundaries(time);
  int windowOf(Fraction onset) {
    if (boundaries == null) return (onset.toDouble() * 4).floor();
    var idx = 0;
    for (var b = 0; b < boundaries.length; b++) {
      if (onset < boundaries[b]) break;
      idx = b;
    }
    return idx;
  }

  final runs = <List<int>>[];
  List<int>? current;
  int? currentWindow;
  int? currentSpan;
  for (var i = 0; i < count; i++) {
    switch (roleAt(i)) {
      case BeamItemRole.beamable:
        final window = windowOf(onsetAt(i));
        final span = spanAt?.call(i) ?? -1;
        if (current != null && window == currentWindow && span == currentSpan) {
          current.add(i);
        } else {
          current = [i];
          currentWindow = window;
          currentSpan = span;
          runs.add(current);
        }
      case BeamItemRole.transparent:
        break;
      case BeamItemRole.breaker:
        current = null;
        currentWindow = null;
        currentSpan = null;
    }
  }
  return runs;
}
