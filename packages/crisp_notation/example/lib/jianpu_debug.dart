import 'package:flutter/material.dart';
import 'package:crisp_notation/crisp_notation.dart';

import 'note_player.dart';

/// 简谱渲染专用调试页面
///
/// 把所有 Jianpu 测试用例集中在此页面，方便逐一审阅渲染质量。
/// 每条用例都是一张独立的 Card，可点击音符高亮并播放音高。
class JianpuDebugPage extends StatefulWidget {
  const JianpuDebugPage({super.key});

  @override
  State<JianpuDebugPage> createState() => _JianpuDebugPageState();
}

class _JianpuDebugPageState extends State<JianpuDebugPage> {
  late final NotePlayer _player;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _player = NotePlayer();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _playPitches(List<int> midis) {
    if (midis.isEmpty) return;
    if (midis.length == 1) {
      _player.playMidi(midis.single);
    } else {
      _player.playChord(midis);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        itemCount: _cases.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final item = _cases[index];
          return _CaseCard(
            item: item,
            onTap: (id, score) {
              final midis = pitchesForElements(score, {id});
              _playPitches(midis.toList());
            },
          );
        },
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final _JianpuCase item;
  final void Function(String id, Score score) onTap;

  const _CaseCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.category,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (item.notes != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  item.notes!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            item.isMixed
                ? StaffSystemView(
                    system: StaffSystem([
                      item.score,
                      Score.simple(
                        timeSignature: item.score.timeSignature,
                        staffType: StaffType.jianpu,
                        notes: item._extractNotes(),
                        keySignature: item.score.keySignature,
                      ),
                    ]),
                    staffGap: 2,
                    tapToHighlight: true,
                    onElementTap: (id) => onTap(id, item.score),
                  )
                : StaffView(
                    score: item.score,
                    onElementTap: (id) => onTap(id, item.score),
                  ),
          ],
        ),
      ),
    );
  }
}

class _JianpuCase {
  final String category;
  final String title;
  final Score score;
  final String? notes; // 原始 notes 字符串，方便对照
  final bool isMixed; // 是否五线谱+简谱混排展示

  const _JianpuCase({
    required this.category,
    required this.title,
    required this.score,
    this.notes,
    this.isMixed = false,
  });

  /// 从 score 的 measures 中还原 notes 字符串（混排时用）
  String _extractNotes() {
    final buf = StringBuffer();
    for (var m = 0; m < score.measures.length; m++) {
      if (m > 0) buf.write(' | ');
      final measure = score.measures[m];
      for (var i = 0; i < measure.elements.length; i++) {
        final el = measure.elements[i];
        if (el is NoteElement) {
          if (el.pitches.length == 1) {
            buf.write(el.pitches.first.toString());
          } else {
            buf.write(el.pitches.join('+'));
          }
          buf.write(':');
          buf.write(_durLetter(el.duration));
          if (i < measure.elements.length - 1) buf.write(' ');
        } else if (el is RestElement) {
          buf.write('r:');
          buf.write(_durLetter(el.duration));
          if (i < measure.elements.length - 1) buf.write(' ');
        }
      }
    }
    return buf.toString();
  }

  static String _durLetter(NoteDuration d) {
    switch (d.base) {
      case DurationBase.whole:
        return 'w';
      case DurationBase.half:
        return 'h';
      case DurationBase.quarter:
        return 'q';
      case DurationBase.eighth:
        return 'e';
      case DurationBase.sixteenth:
        return 's';
      case DurationBase.thirtySecond:
        return 't';
      case DurationBase.sixtyFourth:
        return 'x';
      case DurationBase.breve:
        return 'b';
      default:
        return '?';
    }
  }
}

// ============================================================================
// 全部简谱测试用例 —— 从 gallery.dart 集中搬运 + 额外补充
// ============================================================================

final List<_JianpuCase> _cases = [
  // ---- 基础：音阶、八度点 ----
  _JianpuCase(
    category: '基础',
    title: 'C 大调音阶 · 八度点分布',
    notes: 'c3:q c4 c5 r:q | c4:q d4 e4 f4 | g4:h a4:h | b4:q c5 d5 e5 | f5:e f5 e5 d5 c5:h | c5:w',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes:
          'c3:q c4 c5 r:q | c4:q d4 e4 f4 | g4:h a4:h | b4:q c5 d5 e5 '
          '| f5:e f5 e5 d5 c5:h | c5:w',
    ),
  ),
  _JianpuCase(
    category: '基础',
    title: '两个八度完整音阶（简谱 ↔ 五线谱对照）',
    notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5 | d5 e5 f5 g5 | a5 b5 c6:h',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5 | d5 e5 f5 g5 | a5 b5 c6:h',
    ),
    isMixed: true,
  ),
  _JianpuCase(
    category: '基础',
    title: '八度点极值（下二点 ↔ 上二点）',
    notes: 'c2:q c3 c4 c5 | c6:q c5 c4 c3 | c2:w c6:w',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c2:q c3 c4 c5 | c6:q c5 c4 c3 | c2:w c6:w',
    ),
  ),

  // ---- 时值：各种音符 + 休止符 ----
  _JianpuCase(
    category: '时值',
    title: '全 / 二分 / 四分 / 附点 / 休止符',
    notes: 'c4:w | c4:h c4:h | c4:q. c4:e r:q r:q | c4:q r:q c4:h',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:w | c4:h c4:h | c4:q. c4:e r:q r:q | c4:q r:q c4:h',
    ),
  ),
  _JianpuCase(
    category: '时值',
    title: '减时线（八分 1 层 · 十六分 2 层 · 三十二分 3 层）',
    notes: 'c4:e c4 c4 c4 c4:s c4 c4 c4 c4:e c4 | c4:t d4 e4 f4 g4:t c4',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:e c4 c4 c4 c4:s c4 c4 c4 c4:e c4 | c4:t d4 e4 f4 g4:t c4',
    ),
  ),
  _JianpuCase(
    category: '时值',
    title: '小节边界（减时线不跨小节，按拍独立分组）',
    notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5 | c4:s d4 e4 f5 | g5:s f5 e5 c5',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:e d4 e4 f4 | g4:e a4 b4 c5 | '
          'c4:s d4 e4 f5 | g5:s f5 e5 c5',
    ),
  ),

  // ---- 八度点 + 减时线组合 ----
  _JianpuCase(
    category: '组合',
    title: '八度点 × 减时线（下方点与下划线不打架）',
    notes: 'c3:e d3 c2:e d2 | c2:s d2 c3:s d3 | c3:q c2:e d2 e3 | c2:s d2 e2 f2',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c3:e d3 c2:e d2 | c2:s d2 c3:s d3 | '
          'c3:q c2:e d2 e3 | c2:s d2 e2 f2',
    ),
  ),
  _JianpuCase(
    category: '组合',
    title: '上方高音点 × 减时线',
    notes: 'c5:e d5 e5 f5 | g5:s a5 b5 c6 | c5:e d5:q c5:h',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c5:e d5 e5 f5 | g5:s a5 b5 c6 | c5:e d5:q c5:h',
    ),
  ),

  // ---- 变音记号 ----
  _JianpuCase(
    category: '变音',
    title: '升降还原（♯ ♭ ♮ ♯♯ ♭♭）',
    notes: 'c4:q c#4 c4 cn4 | dbb4:q c##4 b4 bn4 | f#4:q bb4 e#4 f##4 | cn4:q d4 e4 f4',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4:q c#4 c4 cn4 | dbb4:q c##4 b4 bn4 | '
          'f#4:q bb4 e#4 f##4 | cn4:q d4 e4 f4',
    ),
  ),

  // ---- 调性（key 变调） ----
  _JianpuCase(
    category: '调性',
    title: '不同调号（D / ♭E / A / ♯F）',
    notes: '!key=2 d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | !key=3 a4:q b4 c#4 d4 | !key=6 f#4:q g#4 a#4 b4',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: '!key=2 d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | '
          '!key=3 a4:q b4 c#4 d4 | !key=6 f#4:q g#4 a#4 b4',
    ),
  ),

  // ---- 连音 / 延音 / 反复 ----
  _JianpuCase(
    category: '连音',
    title: '连音线 · 延音 · 反复记号',
    notes: '!repeat c4:q( d4 e4 f4) | g4:h~ g4:q r:q | !endrepeat !volta=1 a4:h g4:h | !volta=2 c5:h. c4:q',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: '!repeat c4:q( d4 e4 f4) | g4:h~ g4:q r:q | '
          '!endrepeat !volta=1 a4:h g4:h | !volta=2 c5:h. c4:q',
    ),
  ),

  // ---- 歌词 ----
  _JianpuCase(
    category: '歌词',
    title: '歌词混排（Twinkle Twinkle）',
    notes: 'd4:q d4 a4 a4 | b4:q b4 a4:h | g4:q g4 f#4 f#4 | e4:q e4 d4:h',
    score: Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'd4:q d4 a4 a4 | b4:q b4 a4:h | '
          'g4:q g4 f#4 f#4 | e4:q e4 d4:h',
      lyrics: 'Twin- kle twin- kle lit- tle star twin- kle twin- kle star',
    ),
  ),

  // ---- 和弦标注 ----
  _JianpuCase(
    category: '标注',
    title: '和弦标注（C Am F G C）',
    notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
      annotations: 'C Am F G7 C',
    ),
  ),

  // ---- 力度 / 渐强渐弱 ----
  _JianpuCase(
    category: '力度',
    title: '力度记号 + 渐强渐弱',
    score: () {
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

  // ---- 和弦（多音叠加） ----
  _JianpuCase(
    category: '和弦',
    title: '大三和弦叠加（下方八度点避让检测）',
    notes: 'c4+e4+g4:h d4+f4+a4:h | e4+g4+b4:h c4:e4:g4:c5:w',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'c4+e4+g4:h d4+f4+a4:h | e4+g4+b4:h c4+e4+g4+c5:w',
    ),
  ),

  // ---- 三连音 ----
  _JianpuCase(
    category: '节奏',
    title: '三连音 / 五连音',
    notes: '3[c4:e d4 e4] 3[c4:e r e4] 5[g4:s a4 b4 c5 d5] e5:q',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: '3[c4:e d4 e4] 3[c4:e r e4] 5[g4:s a4 b4 c5 d5] e5:q',
    ),
  ),

  // ---- 装饰音 ----
  _JianpuCase(
    category: '装饰',
    title: '装饰音（短倚音 + 波音 + 回音 + 颤音）',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: r"c4:q' a3_ g3> c4^ | c4+e4:q' d5>' f4:h@",
    ),
  ),

  // ---- 弹唱谱（五线谱 + 简谱 + 歌词 + 和弦）----
  _JianpuCase(
    category: '混排',
    title: '弹唱谱：小星星（五线谱 + 简谱 + 歌词 + 和弦）',
    notes: 'g4:q g4 a4 a4 | b4:q b4 a4:h',
    score: Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes: 'g4:q g4 a4 a4 | b4:q b4 a4:h | '
          'a4:q a4 g4:q g4 | f#4:q f#4 e4:h | '
          'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w',
      lyrics: 'Twin- kle twin- kle lit- tle star twin- kle twin- kle star how I won- der what you are',
      annotations: 'G * * * C * G G * C * G * D * Em * C * G',
    ),
  ),

  // ---- 小调式 / 带调号简谱 ----
  _JianpuCase(
    category: '调性',
    title: 'G 大调歌词实战（茉莉花开头）',
    notes: 'e4:q e4:e g4:e a4:e c5:e c5:e a4:e | g4:q g4:e a4:e g4:h',
    score: Score.simple(
      timeSignature: TimeSignature.fourFour,
      staffType: StaffType.jianpu,
      notes:
          'e4:q e4:e g4:e a4:e c5:e c5:e a4:e | g4:q g4:e a4:e g4:h',
      lyrics: '好 一 朵 美_ * 丽 的 茉 莉_ * 花_',
    ),
  ),
];
