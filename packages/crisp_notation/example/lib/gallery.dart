import 'package:flutter/material.dart';
import 'package:crisp_notation/crisp_notation.dart';

import 'note_player.dart';

/// One entry of the gallery corpus.
class GalleryItem {
  final String title;
  final Score score;
  final CrispNotationTheme theme;
  final Set<String> highlightedIds;

  const GalleryItem(
    this.title,
    this.score, {
    this.theme = CrispNotationTheme.standard,
    this.highlightedIds = const {},
  });
}

/// The golden-test corpus, browsable on a device. Doubles as manual QA.
final List<GalleryItem> galleryItems = [
  GalleryItem(
    'C major scale (treble)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
    ),
  ),
  GalleryItem(
    'C major scale (bass)',
    Score.simple(
      clef: Clef.bass,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q d3 e3 f3 | g3 a3 b3 c4',
    ),
  ),
  GalleryItem(
    'Durations: whole to quarter',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:w | c5:h c5:h | c5:q c5 c5 c5',
    ),
  ),
  GalleryItem(
    'Dotted notes',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:h. e5:q | a4:q. b4:e c5:h | g4:h..  g4:s g4:s',
    ),
  ),
  GalleryItem(
    'Rests',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'r:w | r:h r:q r:e r:s r:s | c5:q r:q. c5:e r:h',
    ),
  ),
  GalleryItem(
    'Accidentals & measure memory',
    Score.simple(notes: 'f#4:q bb4 cn5 g##4 | dbb5:q f#4 f4 f#5'),
  ),
  GalleryItem(
    'C# major: 7 sharps',
    Score.simple(
      keySignature: const KeySignature(7),
      notes: 'c#4:q d#4 e#4 f#4',
    ),
  ),
  GalleryItem(
    'Cb major: 7 flats',
    Score.simple(
      keySignature: const KeySignature(-7),
      notes: 'cb5:q bb4 ab4 gb4',
    ),
  ),
  GalleryItem(
    'Ab major in bass clef',
    Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-4),
      notes: 'ab2:q bb2 c3 db3',
    ),
  ),
  GalleryItem(
    'Waltz time (3/4)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: 'g4:q b4 d5 | c5:h.',
    ),
  ),
  GalleryItem(
    '12/8 (two-digit numerator)',
    Score.simple(
      timeSignature: const TimeSignature(12, 8),
      notes: 'c5:h. c5:h.',
    ),
  ),
  GalleryItem(
    'Triads & inversions',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+e4+g4:h e4+g4+c5:h | d4+f4:q f4+a4 g4+b4 d5+f5+a5',
    ),
  ),
  GalleryItem(
    'Seconds cluster across the stem',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+d4:h e5+f5:h | b3+c4+d4:w',
    ),
  ),
  GalleryItem(
    'Beamed eighths (2 beams in 4/4)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
    ),
  ),
  GalleryItem(
    'Sixteenths & secondary beams',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:s d5 e5 f5 g5:e a5:s b5:s c6:q c5:q',
    ),
  ),
  GalleryItem(
    'Beam slant clamp',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:e c5 g4 c5 c4:e e4 g4 c5',
    ),
  ),
  GalleryItem(
    'Ledger lines',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'a3:q c4 a5 c6 | e6:h g3:h',
    ),
  ),
  GalleryItem(
    'Alle meine Entchen (G major)',
    Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:e a4 b4 c5 d5:q d5 | e5:e e5 e5 e5 d5:h',
    ),
  ),
  GalleryItem(
    'Highlights & element colors',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q e4 g4 c5',
    ),
    theme: const CrispNotationTheme(elementColors: {'e0': Color(0xFF43A047)}),
    highlightedIds: const {'e2'},
  ),
  GalleryItem(
    'Kids theme',
    Score.simple(
      timeSignature: TimeSignature.twoFour,
      notes: 'g4:q b4 | c5:e d5 e5 f5 | g5:h',
    ),
    theme: CrispNotationTheme.kids,
    highlightedIds: const {'e1'},
  ),
  GalleryItem(
    'Two voices (soprano/alto on one staff)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 ; c4:h e4:h | '
          'g5:e f5 e5 d5 e5:h ; c4:q r b3 c4 | '
          'e5:w ; c4:q c4 c4:h',
    ),
  ),
  GalleryItem(
    'Repeats, voltas & mid-score changes',
    Score.simple(
      keySignature: const KeySignature(2),
      timeSignature: TimeSignature.fourFour,
      notes: '!repeat d4:q f#4 a4 d5 | '
          '!endrepeat !volta=1 !key=-1 !time=3/4 bb4:q c5 d5 | '
          '!volta=2 !clef=bass d3:h.',
    ),
  ),
  GalleryItem(
    '32nds, 64ths & breve',
    Score.simple(
      notes: 'c5:t d5 e5 f5 g5:x a5 b5 c6 g5:t r:t a4:x r:x | c5:b',
    ),
  ),
  GalleryItem(
    'Grace notes (acciaccatura)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: '{g4}a4:q {f4,g4}a4:q {b4}c5:q | {c4}g4:h.',
    ),
  ),
  GalleryItem(
    'Dynamics & hairpins',
    () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:h e5:h',
      );
      return Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [
          DynamicMarking('e0', DynamicLevel.p),
          DynamicMarking('e4', DynamicLevel.ff),
          DynamicMarking('e5', DynamicLevel.mp),
        ],
        hairpins: const [
          Hairpin('e0', 'e3', HairpinType.crescendo),
          Hairpin('e4', 'e5', HairpinType.diminuendo),
        ],
      );
    }(),
  ),
  GalleryItem(
    'Articulations & fermata',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: "c5:q' a4_ g4> c5^ | c4+e4:q' d5>' f4:h@",
    ),
  ),
  GalleryItem(
    'Tuplets (triplet, rest inside, quintuplet)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: '3[c5:e d5 e5] 3[c4:e r e4] 5[g4:s a4 b4 c5 d5] e5:q',
    ),
  ),
  GalleryItem(
    'Slurs (phrasing over any pitches)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: 'c4:q( d4 e4) | g5:e( a5 g5 f5 e5 d5) | c5:q( c6 g4) ',
    ),
  ),
  GalleryItem(
    'Ties (within and across measures)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:h~ c5:q a4:q~ | a4:h c4+e4:h~ | c4+e4:w~ | c4+e4:w',
    ),
  ),
  GalleryItem(
    'Alto clef: viola line (F major)',
    Score.simple(
      clef: Clef.alto,
      keySignature: const KeySignature(-1),
      timeSignature: TimeSignature.threeFour,
      notes: 'f3:q a3 c4 | c4:e d4 e4 f4 g4:q | a4+c4:h.',
    ),
  ),
  GalleryItem(
    'Tenor clef: cello line (D major)',
    Score.simple(
      clef: Clef.tenor,
      keySignature: const KeySignature(2),
      timeSignature: TimeSignature.fourFour,
      notes: 'd3:q f#3 a3 d4 | c#4:e b3 a3 g3 f#3:h',
    ),
  ),
  GalleryItem(
    'Unmetered bass chords (D major)',
    Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(2),
      notes: 'd3:q f#3+a3 d3+f#3+a3:h | g2+b2+d3:w',
    ),
  ),
  GalleryItem(
    'Chord symbols (annotations above the staff)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
      annotations: 'C Am F G7 C',
    ),
  ),
  GalleryItem(
    'Lyrics (hyphens, melisma extender)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q c4 g4 g4 | a4:q a4 g4:q g4 | f4:q f4 e4 e4 |'
          'd4:q d4 c4:h',
      lyrics: 'Twin- kle twin- kle lit- tle star_ * how I won- der '
          'what you are',
    ),
  ),
  GalleryItem(
    'Accidental stacking (dense chords)',
    Score.simple(
      notes: 'f#4+f#5:h c#4+d#4+e#4:h | c#4+f#4+a#4+c#5+f#5:w |'
          'bb3+eb4+ab4+db5:w',
    ),
  ),
  GalleryItem(
    'Ornaments (trill, short trill, mordent, turn)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: r'c5:q% d5$ e5& f5? | g5:h@% c6:h?',
    ),
  ),
  GalleryItem(
    'Multi-measure rest',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | !mrest=16 | g4:w',
    ),
  ),
  GalleryItem(
    'Octave clef (choral tenor, treble8vb)',
    Score.simple(
      clef: Clef.treble8vb,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q e3 g3 c4 | b3:h. r:q',
    ),
  ),
  GalleryItem(
    'Navigation marks (Segno, Coda, D.S., Fine)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: '!nav=segno c4:q e4 g4 e4 | !nav=fine g4:q e4 c4 r | '
          '!nav=coda c4:q e4 g4 c5 | !nav=dalSegnoAlFine g4:h e4',
    ),
    theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
  ),
  GalleryItem(
    'Fingering numbers',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q=1 d4:q=2 e4:q=3 f4:q=4 | g4:q=5 e4:q=3 c4:q=1 r:q | '
          'c4+e4+g4:h=1,3,5 r:h',
    ),
  ),
  GalleryItem(
    'Arpeggiated chords (roll up / down)',
    Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement(
            pitches: [
              Pitch.parse('c4'),
              Pitch.parse('e4'),
              Pitch.parse('g4'),
              Pitch.parse('c5'),
            ],
            duration: NoteDuration.half,
            arpeggio: Arpeggio.up,
          ),
          NoteElement(
            pitches: [
              Pitch.parse('d4'),
              Pitch.parse('f4'),
              Pitch.parse('a4'),
              Pitch.parse('d5'),
            ],
            duration: NoteDuration.half,
            arpeggio: Arpeggio.down,
          ),
        ]),
      ],
    ),
  ),
  GalleryItem(
    'Glissando / slide',
    Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('c4'), NoteDuration.half, id: 'a'),
          NoteElement.note(Pitch.parse('g5'), NoteDuration.half, id: 'b'),
        ]),
      ],
      glissandos: const [Glissando('a', 'b')],
    ),
  ),
  GalleryItem(
    'Tremolo (1–3 strokes)',
    Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('b4'), NoteDuration.quarter, tremolo: 1),
          NoteElement.note(Pitch.parse('b4'), NoteDuration.quarter, tremolo: 2),
          NoteElement.note(Pitch.parse('b4'), NoteDuration.quarter, tremolo: 3),
          NoteElement.note(Pitch.parse('g4'), NoteDuration.quarter, tremolo: 3),
        ]),
      ],
    ),
  ),
  GalleryItem(
    'Sustain pedal (Ped. … *)',
    Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('c4'), NoteDuration.quarter, id: 'a'),
          NoteElement.note(Pitch.parse('e4'), NoteDuration.quarter),
          NoteElement.note(Pitch.parse('g4'), NoteDuration.quarter),
          NoteElement.note(Pitch.parse('c5'), NoteDuration.quarter, id: 'd'),
        ]),
      ],
      pedals: const [Pedal('a', 'd')],
    ),
  ),
  GalleryItem(
    'Feathered beams (accel. / rit.)',
    () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:e a4 b4 c5 d5 e5 f5 g5 | g5:e f5 e5 d5 c5 b4 a4 g4',
      );
      return Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        featheredBeams: const [
          FeatheredBeam('e0', 'e7', beginBeams: 1, endBeams: 4),
          FeatheredBeam('e8', 'e15', beginBeams: 4, endBeams: 1),
        ],
      );
    }(),
  ),
  GalleryItem(
    'Forced horizontal beam',
    () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
      );
      return Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        beamSlants: const [BeamSlant('e0', 'e7')],
      );
    }(),
  ),

  // --- Jianpu (numbered notation) — routed by Score.staffType ----------
  GalleryItem(
    'Jianpu: C major scale & octave dots',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c3:q c4 c5 r:q | c4:q d4 e4 f4 | g4:h a4:h | b4:q c5 d5 e5 '
          '| f5:e f5 e5 d5 c5:h | c5:w',
    ),
  ),
  GalleryItem(
    'Jianpu: durations, rests & underlines',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:w | c4:h c4:h | c4:q. c4:e r:q r:q | '
          'c4:e c4 c4 c4 c4:s c4 c4 c4 c4:e c4 | r:w',
    ),
  ),
  GalleryItem(
    'Jianpu: ties, slurs & repeats',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: '!repeat c4:q( d4 e4 f4) | g4:h~ g4:q r:q | '
          '!endrepeat !volta=1 a4:h g4:h | !volta=2 c5:h. c4:q',
    ),
  ),
  GalleryItem(
    'Jianpu: G major song (lyrics & chords)',
    Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'd4:q d4 a4 a4 | b4:q b4 a4:h | g4:q g4 f#4 f#4 | e4:q e4 d4:h',
      lyrics: 'Twin- kle twin- kle lit- tle star twin- kle twin- kle star',
      annotations: 'G * * * C * G G * C * G *',
    ),
  ),
  GalleryItem(
    'Jianpu: dynamics & hairpins',
    () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        staffType: StaffType.jianpu,
        notes: 'c4:q d4 e4 f4 | g4:h e4:h | c4:w',
      );
      return Score(
        clef: base.clef,
        staffType: base.staffType,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [
          DynamicMarking('e0', DynamicLevel.p),
          DynamicMarking('e4', DynamicLevel.ff),
          DynamicMarking('e6', DynamicLevel.mp),
        ],
        hairpins: const [
          Hairpin('e0', 'e3', HairpinType.crescendo),
          Hairpin('e4', 'e5', HairpinType.diminuendo),
        ],
      );
    }(),
  ),
  GalleryItem(
    'Jianpu: octaves (2 dots below to 2 above)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c2:q c3 c4 c5 | c6:q c5 c4 c3 | c2:w c6:w',
    ),
  ),
  GalleryItem(
    'Jianpu: keys (D, ♭E, A, ♯F)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: '!key=2 d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | '
          '!key=3 a4:q b4 c#4 d4 | !key=6 f#4:q g#4 a#4 b4',
    ),
  ),
  GalleryItem(
    'Jianpu: accidentals (♯ ♭ ♮ ♯♯ ♭♭)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:q c#4 c4 cn4 | dbb4:q c##4 b4 bn4 | '
          'f#4:q bb4 e#4 f##4 | cn4:q d4 e4 f4',
    ),
  ),
  GalleryItem(
    'Jianpu: cross-measure underlines',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5 | '
          'c4:s d4 e4 f5 | g5:s f5 e5 c5',
    ),
  ),
  GalleryItem(
    'Jianpu: 减时线 + 下方八度点组合',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      // 下方八度点(c2=2点, c3=1点)与减时线(八分=1层, 十六分=2层)叠加
      notes: 'c3:e d3 c2:e d2 | c2:s d2 c3:s d3 | '
          'c3:q c2:e d2 e3 | c2:s d2 e2 f2',
    ),
  ),
];

/// Scrollable gallery of the corpus (plus grand-staff and multi-system
/// showcase cards).
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _notePlayer = NotePlayer();

  @override
  void dispose() {
    _notePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: galleryItems.length + 7,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == galleryItems.length + 6) {
          // Interactive: tap to highlight + play pitch.
          final score = StaffSystem([
            Score.simple(
              timeSignature: TimeSignature.fourFour,
              staffType: StaffType.jianpu,
              notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | '
                  'c4:e d4 e4 f4 | g4:w',
            ),
          ]);
          // Build a playback timeline to resolve element-id → pitches.
          final firstStaff = score.staves.first;
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tap to highlight + play (点击高亮 + 播放音高)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'tapToHighlight + onElementTap — 点击音符高亮并播放 1 秒音频',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  StaffSystemView(
                    system: score,
                    layoutMode: SystemLayoutMode.wrapped,
                    staffSpace: 10,
                    tapToHighlight: true,
                    onElementTap: (id) {
                      final midis =
                          pitchesForElements(firstStaff, [id]);
                      if (midis.isEmpty) return;
                      _notePlayer.playChord(midis.toList());
                    },
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length + 5) {
          // Layout mode 2: single-line horizontal scroll (piano roll / 卷帘).
          final score = StaffSystem([
            Score.simple(
              timeSignature: TimeSignature.fourFour,
              notes: 'c5:q d5 e5 f5 | g5:e a5 b5 c6 d6 e6 | f6:h e6 d6 | c6:w',
            ),
            Score.simple(
              clef: Clef.bass,
              timeSignature: TimeSignature.fourFour,
              notes: 'c3:h g3:h | a2:e b2 c3 d3 e3 f3 | g3:h f3 e3 | c3:w',
            ),
            Score.simple(
              timeSignature: TimeSignature.fourFour,
              staffType: StaffType.jianpu,
              notes: 'c4:q d4 e4 f4 | g4:e a4 b4 c5 d5 e5 | f5:h e5 d5 | c5:w',
            ),
          ], brackets: [
            StaffBracket(0, 1, kind: StaffBracketKind.brace),
          ]);
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Single-line horizontal scroll (piano + jianpu 卷帘模式)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '所有小节排成一行，横向滚动（一行 = 整个 multi-staff system）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 260,
                    child: StaffSystemScrollView(
                      system: score,
                      staffSpace: 8,
                      staffGap: 4,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length + 4) {
          // Layout mode 1: wrapped multi-line (multi-system) via StaffSystemView.
          final longScore = StaffSystem([
            Score.simple(
              keySignature: const KeySignature(1),
              timeSignature: TimeSignature.fourFour,
              notes: 'g4:q a4 b4 c5 | d5:e c5 b4 a4 g4:h |'
                  'e4:q g4 b4 d5 | c5:q a4 f#4 d4 |'
                  'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w |'
                  'a4:e b4 c5 d5 e5 f#5 g5 a5 | b5:h a5 g5 | f#5:q e5 d5 | c5:w',
            ),
          ]);
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wrapped multi-line layout (自动换行多行)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'StaffSystemView 默认 layoutMode: wrapped — 超宽时自动断行，多系统从上到下堆叠。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  StaffSystemView(
                    system: longScore,
                    layoutMode: SystemLayoutMode.wrapped,
                    staffSpace: 8,
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length + 3) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mixed staff system (piano + jianpu 弹唱谱)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  StaffSystemView(
                    system: StaffSystem([
                      Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c5:q d5 e5 f5 | g5 a5 b5 c6',
                      ),
                      Score.simple(
                        clef: Clef.bass,
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c3:h g3:h | c3:h g3:h',
                      ),
                      Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        staffType: StaffType.jianpu,
                        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
                      ),
                    ]),
                    staffGap: 4.0,
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length + 2) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mixed grand staff (standard + jianpu)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  GrandStaffView(
                    grandStaff: GrandStaff(
                      upper: Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
                      ),
                      lower: Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        staffType: StaffType.jianpu,
                        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
                      ),
                    ),
                    staffGap: 2.0,
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length + 1) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Line breaking (multi-system)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  MultiSystemView(
                    score: Score.simple(
                      keySignature: const KeySignature(1),
                      timeSignature: TimeSignature.fourFour,
                      notes: 'g4:q a4 b4 c5 | d5:e c5 b4 a4 g4:h |'
                          'e4:q g4 b4 d5 | c5:q a4 f#4 d4 |'
                          'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w',
                    ),
                    staffSpace: 10,
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grand staff (piano system)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  GrandStaffView(
                    grandStaff: GrandStaff(
                      upper: Score.simple(
                        keySignature: const KeySignature(1),
                        timeSignature: TimeSignature.fourFour,
                        notes: 'd5:q b4 g4 b4 | c5:e d5 e5 c5 d5:h',
                      ),
                      lower: Score.simple(
                        clef: Clef.bass,
                        keySignature: const KeySignature(1),
                        timeSignature: TimeSignature.fourFour,
                        notes: 'g2:h d3:h | c3:q e3 g3+b3:h',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final item = galleryItems[index];
        return Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                StaffView(
                  score: item.score,
                  theme: item.theme,
                  highlightedIds: item.highlightedIds,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
