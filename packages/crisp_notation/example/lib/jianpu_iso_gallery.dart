import 'package:flutter/material.dart';
import 'package:crisp_notation/crisp_notation.dart';

/// GB/T 46845—2025《音乐曲谱出版 简谱 通用规范》示例画廊。
///
/// 按规范目录逐条组织示例：第 5 章谱表体式符号、第 6 章基本符号、
/// 第 7 章辅助符号。每条示例标注规范条款号；当前引擎尚未支持的条款
/// 以灰底占位说明。顶部提供全局字号（staff space）设置，作用于所有示例。
class JianpuIsoGalleryPage extends StatefulWidget {
  const JianpuIsoGalleryPage({super.key});

  @override
  State<JianpuIsoGalleryPage> createState() => _JianpuIsoGalleryPageState();
}

class _JianpuIsoGalleryPageState extends State<JianpuIsoGalleryPage> {
  static const double _minSpace = 8;
  static const double _maxSpace = 24;

  double _staffSpace = 13;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FontSizeControl(
          staffSpace: _staffSpace,
          min: _minSpace,
          max: _maxSpace,
          onChanged: (v) => setState(() => _staffSpace = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: _isoChapters.length,
            itemBuilder: (context, i) => _ChapterTile(
              chapter: _isoChapters[i],
              staffSpace: _staffSpace,
              initiallyExpanded: i == 1, // 默认展开第 6 章（基本符号）
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 字号控制条
// ============================================================================

class _FontSizeControl extends StatelessWidget {
  final double staffSpace;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _FontSizeControl({
    required this.staffSpace,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Text('全局字号', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            for (final preset in const [('小', 10.0), ('标准', 13.0), ('大', 18.0)])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(preset.$1),
                  selected: (staffSpace - preset.$2).abs() < 0.01,
                  onSelected: (_) => onChanged(preset.$2),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            Expanded(
              child: Slider(
                value: staffSpace,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                staffSpace.toStringAsFixed(1),
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 章 / 节 / 示例卡片
// ============================================================================

class _ChapterTile extends StatelessWidget {
  final _IsoChapter chapter;
  final double staffSpace;
  final bool initiallyExpanded;

  const _ChapterTile({
    required this.chapter,
    required this.staffSpace,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final total = chapter.sections
        .fold<int>(0, (sum, s) => sum + s.examples.length);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text('${chapter.number}　${chapter.title}'),
        subtitle: Text('${chapter.sections.length} 节 · $total 条示例'),
        children: [
          for (final section in chapter.sections)
            _SectionView(section: section, staffSpace: staffSpace),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  final _IsoSection section;
  final double staffSpace;

  const _SectionView({required this.section, required this.staffSpace});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '${section.number}　${section.title}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (final example in section.examples) ...[
                _ExampleCard(example: example, staffSpace: staffSpace),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExampleCard extends StatelessWidget {
  final _IsoExample example;
  final double staffSpace;

  const _ExampleCard({required this.example, required this.staffSpace});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final implemented = example.score != null || example.builder != null;
    return Container(
      decoration: BoxDecoration(
        color: implemented ? Colors.white : Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: implemented
                      ? theme.colorScheme.primaryContainer
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '§${example.clause}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: implemented
                        ? theme.colorScheme.onPrimaryContainer
                        : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(example.title,
                    style: theme.textTheme.titleSmall),
              ),
              if (!implemented)
                Text('未实现',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: Colors.grey.shade500)),
            ],
          ),
          if (example.note != null) ...[
            const SizedBox(height: 6),
            Text(
              example.note!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 8),
          if (implemented)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: example.builder != null
                  ? example.builder!(staffSpace)
                  : StaffView(
                      score: example.score!,
                      staffSpace: staffSpace,
                      showJianpuHeader: example.header,
                    ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                example.placeholder ?? '规范有此条款，当前简谱引擎尚未支持。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade500),
              ),
            ),
          if (example.source != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              example.source!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 数据模型
// ============================================================================

class _IsoChapter {
  final String number;
  final String title;
  final List<_IsoSection> sections;
  const _IsoChapter(this.number, this.title, this.sections);
}

class _IsoSection {
  final String number;
  final String title;
  final List<_IsoExample> examples;
  const _IsoSection(this.number, this.title, this.examples);
}

class _IsoExample {
  /// 规范条款号，如 "5.8.2.2b"。
  final String clause;
  final String title;

  /// 规范要点说明。
  final String? note;

  /// 示例曲谱；为 null 表示当前引擎未实现，显示占位。
  final Score? score;

  /// 自定义渲染（多行谱表等单行 StaffView 表达不了的示例），优先于
  /// [score]；参数为全局字号（staff space）。
  final Widget Function(double staffSpace)? builder;

  /// DSL 源字符串，便于对照调试。
  final String? source;

  /// 未实现条款的占位说明。
  final String? placeholder;

  /// 画行首 "1=X 4/4" 标头（调号 + 拍号示例专用；默认不画）。
  final bool header;

  const _IsoExample({
    required this.clause,
    required this.title,
    this.note,
    this.score,
    this.builder,
    this.source,
    this.placeholder,
    this.header = false,
  });
}

// ============================================================================
// 示例构建辅助
// ============================================================================

Score _j(String notes,
        {KeySignature keySignature = const KeySignature(0),
        TimeSignature? timeSignature = TimeSignature.commonTime,
        String? lyrics,
        String? annotations}) =>
    Score.simple(
      notes: notes,
      keySignature: keySignature,
      timeSignature: timeSignature,
      staffType: StaffType.jianpu,
      lyrics: lyrics,
      annotations: annotations,
    );

Score _withDynamics(Score base, List<DynamicMarking> dynamics) => Score(
      clef: base.clef,
      staffType: base.staffType,
      timeSignature: base.timeSignature,
      measures: base.measures,
      lyrics: base.lyrics,
      annotations: base.annotations,
      dynamics: dynamics,
    );

// ============================================================================
// 规范目录数据 —— GB/T 46845—2025
// ============================================================================

final List<_IsoChapter> _isoChapters = [
  // ==========================================================================
  // 第 5 章　谱表体式符号
  // ==========================================================================
  _IsoChapter('第 5 章', '谱表体式符号', [
    _IsoSection('5.2', '小节线与小节', [
      _IsoExample(
        clause: '5.2.1',
        title: '小节线划分节拍律动循环单元',
        note: '垂直短纵线；小节空间与字符量相适应（5.2.4a/b）。',
        score: _j('c4:q d4 e4 f4 | g4:h a4:h | c5:w'),
        source: "c4:q d4 e4 f4 | g4:h a4:h | c5:w",
      ),
      _IsoExample(
        clause: '5.2.4d',
        title: '每行第一小节的左小节线略去不记',
        note: '行首不画小节线，直接以调号、拍号或前反复号开始。',
        score: _j('c4:q d4 e4 f4 | g4:q a4 b4 c5'),
        source: "c4:q d4 e4 f4 | g4:q a4 b4 c5",
      ),
      _IsoExample(
        clause: '5.2.2',
        title: '虚小节线（混合节拍 / 散板细分）',
        note: '垂直细虚线，纵程与小节线相同（y = 1…4）。',
        score: _j('c4:q d4 !barline=dashed e4:q f4 | g4:h'),
        source: "c4:q d4 !barline=dashed e4:q f4 | g4:h",
      ),
    ]),
    _IsoSection('5.3', '连谱号', [
      _IsoExample(
        clause: '5.3.1',
        title: '连谱线：行首细纵线',
        note: '位于一行或一组曲谱左端，粗细如小节线，是一切连谱号的基础构件。'
            '每行简谱行首都带一条（本画廊所有示例行首可见），多行时跨行续接。',
        score: _j('c4:q d4 e4 f4 | g4:h'),
        source: "c4:q d4 e4 f4 | g4:h",
      ),
      _IsoExample(
        clause: '5.3.2',
        title: '花连谱号：联括一人演奏的两行曲谱',
        note: '连谱线左侧的大括号，中间尖角向左，两端弧尖朝向连谱线；'
            '连谱线跨行续接，小节线不跨行。',
        builder: (space) => GrandStaffView(
          grandStaff: GrandStaff(
            upper: _j('c4:q d4 e4 f4 | g4:h'),
            lower: _j('e4:q f4 g4 a4 | b4:h'),
          ),
          staffSpace: space,
        ),
        source: "GrandStaff(upper: 'c4:q d4 e4 f4 | g4:h', "
            "lower: 'e4:q f4 g4 a4 | b4:h')",
      ),
      _IsoExample(
        clause: '5.3.3',
        title: '直连谱号：联括二人以上同时唱奏的两行以上曲谱',
        note: '连谱线左侧的一条粗纵线，两端各有一斜括向连谱线的短半弧括线。',
        builder: (space) => StaffSystemView(
          system: StaffSystem(
            [
              _j('c4:q d4 e4 f4 | c4:h'),
              _j('e4:q f4 g4 a4 | e4:h'),
              _j('g4:q a4 b4 c5 | g4:h'),
            ],
            brackets: const [StaffBracket(0, 2, kind: StaffBracketKind.bracket)],
          ),
          staffSpace: space,
        ),
        source: "StaffSystem([c 行, e 行, g 行], "
            "brackets: [StaffBracket(0, 2, kind: bracket)])",
      ),
      const _IsoExample(
        clause: '5.3.4',
        title: '辅助连谱号',
        note: '联括分组声部的次要连谱号（如合唱中女声组与男声组的分组括线）。',
        placeholder: '辅助连谱号（分组二级括线）尚未在简谱引擎实现。',
      ),
    ]),
    _IsoSection('5.4', '谱表种类', [
      _IsoExample(
        clause: '5.4.1',
        title: '单行谱表（基础谱表）',
        note: '简谱的基础谱表形式，本画廊全部示例均为单行谱表。',
        score: _j('c4:q d4 e4 f4 | g4:h'),
        source: "c4:q d4 e4 f4 | g4:h",
      ),
      _IsoExample(
        clause: '5.4.2',
        title: '大谱表：花连谱号联结的两行谱表',
        note: '由一人演奏的两行曲谱（如钢琴谱），连谱号构件见 §5.3.2。',
        builder: (space) => GrandStaffView(
          grandStaff: GrandStaff(
            upper: _j('c4:e d4 e4 f4 | g4:q a4 b4 c5'),
            lower: _j('c3:q g3 c4 g3 | c4:h'),
          ),
          staffSpace: space,
        ),
        source: "GrandStaff(upper: 'c4:e d4 e4 f4 | g4:q a4 b4 c5', "
            "lower: 'c3:q g3 c4 g3 | c4:h')",
      ),
      _IsoExample(
        clause: '5.4.3',
        title: '直连谱表：直连谱号联结的两行以上谱表',
        note: '二人以上同时唱奏的总谱（如合唱、重奏），连谱号构件见 §5.3.3。',
        builder: (space) => StaffSystemView(
          system: StaffSystem(
            [
              _j('c4:q e4 g4 c5 | g4:h'),
              _j('a3:q c4 e4 a4 | e4:h'),
              _j('e3:q g3 c4 e4 | c4:h'),
            ],
            brackets: const [StaffBracket(0, 2, kind: StaffBracketKind.bracket)],
          ),
          staffSpace: space,
        ),
        source: "StaffSystem([旋律, 中声, 低声], "
            "brackets: [StaffBracket(0, 2, kind: bracket)])",
      ),
      const _IsoExample(
        clause: '5.4.4',
        title: '独唱独奏与伴奏谱表',
        placeholder: '独唱独奏与伴奏谱表（小字号伴奏谱表组）尚未实现。',
      ),
    ]),
    _IsoSection('5.5', '终止线与段落线', [
      _IsoExample(
        clause: '5.5.1',
        title: '终止线：细线 + 粗线',
        note: '用于乐曲结束处；以单行谱表为单位逐一施画（5.5.3）。',
        score: _j('c4:q d4 e4 f4 | g4:w'),
        source: "c4:q d4 e4 f4 | g4:w",
      ),
      _IsoExample(
        clause: '5.5.2',
        title: '段落线：两条并列细纵线（双细线）',
        note: '用于非最后终止的段落终止处。',
        score: _j('c4:q d4 !barline=doubleBar e4:q f4 | g4:w'),
        source: "c4:q d4 !barline=doubleBar e4:q f4 | g4:w",
      ),
    ]),
    _IsoSection('5.6', '声部引导线', [
      _IsoExample(
        clause: '5.6.1',
        title: '大谱表声部移行的斜直细线 / 虚线',
        placeholder: '声部引导线依赖大谱表，尚未实现。',
      ),
    ]),
    _IsoSection('5.7', '划分符号', [
      _IsoExample(
        clause: '5.7.1–5.7.2',
        title: '声部划分号 / 唱词划分号（大括号）',
        placeholder: '声部与唱词的划分大括号尚未实现。',
      ),
    ]),
    _IsoSection('5.8', '反复号', [
      _IsoExample(
        clause: '5.8.2.1',
        title: '段落反复号：前后成对，范围内重复一次',
        note: '粗纵线 + 细纵线 + 两个反复点；记在小节线位置时兼有小节线功能（5.8.2.2d）。',
        score: _j('c4:q d4 e4 f4 | !repeat g4:q a4 b4 c5 !endrepeat | d5:h c5:h'),
        source: "c4:q d4 e4 f4 | !repeat g4:q a4 b4 c5 !endrepeat | d5:h c5:h",
      ),
      _IsoExample(
        clause: '5.8.2.2b',
        title: '作品开端的前段落反复号省略',
        note: '曲首不画前反复号，只在段落结束处画后反复号。',
        score: _j('!repeat c4:q d4 e4 f4 !endrepeat | g4:w'),
        source: "!repeat c4:q d4 e4 f4 !endrepeat | g4:w",
      ),
      _IsoExample(
        clause: '5.8.2.2c',
        title: '紧邻反复段落：前后反复号合并，粗纵线合用一条',
        note: '左点 + 细线 + 共用粗线 + 细线 + 右点。',
        score: _j('c4:q d4 !endrepeat | !repeat e4:q f4 !endrepeat | g4:w'),
        source: "c4:q d4 !endrepeat | !repeat e4:q f4 !endrepeat | g4:w",
      ),
      _IsoExample(
        clause: '5.8.2.3',
        title: '段落反复跳越号（跳房子）+ 段次序号',
        note: '横线两端下垂短纵线（5.11.4）；段次序号斜体阿拉伯数字加下角点，标注在跳越号内左上角。',
        score: _j('!repeat c4:q d4 e4 f4 | !endrepeat !volta=1 g4:q a4 b4 c5 | !volta=2 d5:h c5:h'),
        source: "!repeat c4:q d4 e4 f4 | !endrepeat !volta=1 g4:q a4 b4 c5 | !volta=2 d5:h c5:h",
      ),
      _IsoExample(
        clause: '5.8.3',
        title: '一小节 / 两小节反复号（斜线加两点）',
        placeholder: '记在空白小节中央的小节反复号尚未实现（正式出版物多用于乐队分谱）。',
      ),
      _IsoExample(
        clause: '5.8.5',
        title: '无定次反复号',
        placeholder: '横线两端下垂纵线对准起止位置的无定次反复尚未实现。',
      ),
      _IsoExample(
        clause: '5.8.6',
        title: '术语反复号：D.C. / D.S. / 𝄋 / 𝄌 / Fine',
        placeholder: '导航标记（!nav=segno、daCapo、fine 等）尚未在简谱引擎渲染。',
      ),
    ]),
    _IsoSection('5.9', '序次符号', [
      _IsoExample(
        clause: '5.9.1–5.9.5',
        title: '小节序号（每 5/10 小节或行首）与段落序号（排练号）',
        placeholder: '小节序号与段落序号标注尚未在简谱引擎实现。',
      ),
    ]),
    _IsoSection('5.10', '单行谱表多声部记法', [
      _IsoExample(
        clause: '5.10.1–5.10.2',
        title: '并列声部记法（扁体音符）/ 主从声部记法（小字号从属声部）',
        placeholder: '单行谱表多声部记法尚未实现（规划见实现计划阶段 D）。',
      ),
    ]),
    _IsoSection('5.11', '曲谱的行款列式', [
      _IsoExample(
        clause: '5.11.2a',
        title: '按时值占位：时值长的占宽大',
        note: '横列式按音符时值比率铺排空间（不疏不密型为出版推荐）。',
        score: _j('c4:s d4 e4 f4 g4:e a4:q | b4:h c5:h'),
        source: "c4:s d4 e4 f4 g4:e a4:q | b4:h c5:h",
      ),
      _IsoExample(
        clause: '5.11.2c',
        title: '小节内只有一个音符时位于第一拍位置',
        note: '不置于小节正中。',
        score: _j('c4:w | g4:w'),
        source: "c4:w | g4:w",
      ),
      _IsoExample(
        clause: '5.11.2b / 6.3.13',
        title: '单位拍分明：两个单位拍之间的减时线不可连写',
        note: '4/4 拍四个八分音符分为两组，拍间断开。',
        score: _j('c4:e d4 e4 f4 | g4:e a4 b4 c5'),
        source: "c4:e d4 e4 f4 | g4:e a4 b4 c5",
      ),
      _IsoExample(
        clause: '5.11.3',
        title: '纵列式：连谱线相连各声部按时值对位',
        placeholder: '纵列式对位依赖多行谱表；混排对齐见“简谱调试”页的 StaffSystem 示例。',
      ),
    ]),
  ]),

  // ==========================================================================
  // 第 6 章　基本符号
  // ==========================================================================
  _IsoChapter('第 6 章', '基本符号', [
    _IsoSection('6.2', '音高符号', [
      _IsoExample(
        clause: '6.2.1',
        title: '基本音符 1–7（do re mi fa sol la si）',
        score: _j('c4:q d4 e4 f4 | g4:q a4 b4 c5'),
        source: "c4:q d4 e4 f4 | g4:q a4 b4 c5",
      ),
      _IsoExample(
        clause: '6.2.4',
        title: '高音点 / 低音点：每点升 / 降八度，可复加',
        note: '上加点为高八度（两个点高两个八度），下加点为低八度。',
        score: _j('c2:q c3 c4 c5 | c6:q c5 c4 c3'),
        source: "c2:q c3 c4 c5 | c6:q c5 c4 c3",
      ),
      _IsoExample(
        clause: '6.2.4 / 6.3.5.4',
        title: '低音点与减时线并用时，低音点在减时线下方',
        score: _j('c3:e d3 c2:e d2 | c2:s d2 c3:s d3'),
        source: "c3:e d3 c2:e d2 | c2:s d2 c3:s d3",
      ),
      _IsoExample(
        clause: '6.2.5',
        title: '变音号：♯ ♭ 𝄪 𝄫 ♮，紧置音符左侧偏上',
        note: '左侧多符号并存时变音号最靠近音符（5.11.2d）。',
        score: _j('c4:q c#4 cb4 cn4 | c##4:q cbb4 cn4 c4'),
        source: "c4:q c#4 cb4 cn4 | c##4:q cbb4 cn4 c4",
      ),
      _IsoExample(
        clause: '6.2.5',
        title: '变音号效力：对本小节内后面的同度音有效',
        note: '小节后两个 ♯1 不再重记升号；跨小节同名音须重记。',
        score: _j('c#4:q c4 c4 c4 | c#4:q c4 c4 c4'),
        source: "c#4:q c4 c4 c4 | c#4:q c4 c4 c4",
      ),
      _IsoExample(
        clause: '6.2.5',
        title: '辅助变音号（保险变音号，括号括住）',
        placeholder: '带括号的辅助变音号尚未实现。',
      ),
      _IsoExample(
        clause: '6.2.6',
        title: '八度号：8va（高）/ 8vb（低）及八度重复号',
        placeholder: '八度号（ottava）尚未在简谱引擎实现。',
      ),
      _IsoExample(
        clause: '6.2.9a',
        title: '调号 1=X：曲首标记在曲谱左端',
        note: '“1”与曲谱开始处第一个音符上下对齐。图示 1=D、1=♭E、1=A。',
        score: _j('d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | !key=3 a4:q b4 c#4 d4',
            keySignature: const KeySignature(2)),
        header: true,
        source: "keySignature: D 大调; d4:q e4 f#4 g4 | !key=-3 eb4:q f4 g4 ab4 | !key=3 a4:q b4 c#4 d4",
      ),
      _IsoExample(
        clause: '6.2.9b',
        title: '曲中转调：新调号标记在新调开始处',
        note: '“1”与新调第一个音符垂直对齐。转调附加标记（前 X = 后 Y）暂未实现。',
        score: _j('c4:q d4 e4 f4 | !key=1 g4:q a4 b4 c5'),
        source: "c4:q d4 e4 f4 | !key=1 g4:q a4 b4 c5",
      ),
    ]),
    _IsoSection('6.3', '时值符号', [
      _IsoExample(
        clause: '6.3.4',
        title: '单纯时值符号：基本时值 = 四分符号',
        note: '单纯音符 1–7、单纯休止符 0。',
        score: _j('c4:q d4 e4 r:q | f4:q g4 a4 b4'),
        source: "c4:q d4 e4 r:q | f4:q g4 a4 b4",
      ),
      _IsoExample(
        clause: '6.3.5.1',
        title: '增时线：音符右侧短横线，每条 = 一个四分音符时值',
        score: _j('c4:h d4:h | e4:w'),
        source: "c4:h d4:h | e4:w",
      ),
      _IsoExample(
        clause: '6.3.5.3',
        title: '减时线：下方细横线，每条缩短 1/2，复加记在下方',
        note: '八分 1 层、十六分 2 层、三十二分 3 层。',
        score: _j('c4:e c4 c4 c4 c4:s c4 c4 c4 | c4:e c4 c4 c4 c4:t d4 e4 f4'),
        source: "c4:e c4 c4 c4 c4:s c4 c4 c4 | c4:t d4 e4 f4",
      ),
      _IsoExample(
        clause: '6.3.5.3 / 6.3.13',
        title: '3/8 拍连续八分减时线连写',
        note: '以八分音符为一拍的三拍子，三拍减时线连写为一组。',
        score: _j('c4:e d4 e4 | f4:e g4 a4', timeSignature: const TimeSignature(3, 8)),
        source: "timeSignature: 3/8; c4:e d4 e4 | f4:e g4 a4",
      ),
      _IsoExample(
        clause: '6.3.5.3 / 6.3.13',
        title: '6/8 拍按两个复合拍分组（3+3）',
        score: _j('c4:e d4 e4 f4 g4 a4 | b4:q. c5:q.',
            timeSignature: TimeSignature.sixEight),
        source: "timeSignature: 6/8; c4:e d4 e4 f4 g4 a4 | b4:q. c5:q.",
      ),
      _IsoExample(
        clause: '6.3.6',
        title: '噪音符 X（无确定音高）',
        placeholder: '噪音符 X 尚未在简谱引擎实现。',
      ),
      _IsoExample(
        clause: '6.3.7.1',
        title: '休止符 0：四分及更短用减时线（与音符相似）',
        score: _j('r:q r:e r:e r:q | r:s r:s r:e c4:q'),
        source: "r:q r:e r:e r:q | r:s r:s r:e c4:q",
      ),
      _IsoExample(
        clause: '6.3.7.2',
        title: '二分 / 全休止符：增加四分休止符个数，不用增时线',
        note: '二分 = 0 0，全休止 = 0 0 0 0。',
        score: _j('r:h r:h | r:w'),
        source: "r:h r:h | r:w",
      ),
      _IsoExample(
        clause: '6.3.7.3',
        title: '小节休止符：数字居中置于小节中，表示休止小节数',
        placeholder: '多小节休止（!mrest=4）尚未在简谱引擎渲染。',
      ),
      _IsoExample(
        clause: '6.3.8.1',
        title: '附点：单附点 +1/2、复附点 +3/4',
        note: '附点紧置时值符号之后但不接触；复附点水平并列。',
        score: _j('c4:q. c4:e c4:h | c4:q.. c4:s c4:h'),
        source: "c4:q. c4:e c4:h | c4:q.. c4:s c4:h",
      ),
      _IsoExample(
        clause: '6.3.8.6',
        title: '附点二分 / 全音符不用附点，用增时线',
        note: '附点二分音符 = 二分音符 + 一条增时线（记作数字 + 两条增时线）。',
        score: _j('c4:h. c4:q | d4:w.'),
        source: "c4:h. c4:q | d4:w.",
      ),
      _IsoExample(
        clause: '6.3.8.6',
        title: '附点二分 / 全休止符：增加 0 的个数，不用附点',
        score: _j('r:h. r:q | r:w. r:h'),
        source: "r:h. r:q | r:w. r:h",
      ),
      _IsoExample(
        clause: '6.3.9',
        title: '延音线：同音高音符上的连线，时值一并计算',
        note: '水平记在音符上方，两端对准音符；每条只连接两个音符。',
        score: _j('c4:q~ c4:q~ c4:h | g4:h~ g4:h'),
        source: "c4:q~ c4:q~ c4:h | g4:h~ g4:h",
      ),
      _IsoExample(
        clause: '6.3.10',
        title: '延长号：半圆弧线 + 弧心小圆点，记在时值符号正上方',
        score: _j("c4:q@ d4 e4 f4 | g4:h@ r:h"),
        source: "c4:q@ d4 e4 f4 | g4:h@ r:h",
      ),
      _IsoExample(
        clause: '6.3.11',
        title: '拍号：分数形态；4/4 亦可作 C，2/2 亦可作 ¢',
        note: '器乐曲谱拍号记在第一行谱表左端；中间变换记在该小节开端。',
        score: _j('c4:q d4 e4 | !time=2/4 f4:q g4 | !time=4/4 a4:q b4 c5 d5',
            timeSignature: const TimeSignature(3, 4)),
        header: true,
        source: "timeSignature: 3/4; c4:q d4 e4 | !time=2/4 f4:q g4 | !time=4/4 a4:q b4 c5 d5",
      ),
      _IsoExample(
        clause: '6.3.12',
        title: '连音符：三连音 / 五连音',
        note: '连音号（弧形括线 + 斜体数字）尚未渲染；时值与分组已正确。',
        score: _j('3[c4:e d4 e4] 3[f4:e g4 a4] c4:h | 5[g4:s a4 b4 c5 d5] e5:q. f5:e'),
        source: "3[c4:e d4 e4] 3[f4:e g4 a4] c4:h | 5[g4:s a4 b4 c5 d5] e5:q. f5:e",
      ),
      _IsoExample(
        clause: '6.3.13',
        title: '时值组合法：单拍子单位拍分开成组',
        note: '组间留字空、减时线不连写；附点四分可不受单位拍分开限制。',
        score: _j('c4:e d4 e4 f4 | g4:q. a4:e b4:q'),
        source: "c4:e d4 e4 f4 | g4:q. a4:e b4:q",
      ),
      _IsoExample(
        clause: '6.3.14',
        title: '不完全小节（弱起）：与段落末小节时值互补',
        note: '首小节 1 拍 + 末小节 3 拍 = 完整 4/4。曲谱开始的不完全小节不计小节序号（5.9.3）。',
        score: _j('c4:q | d4:q e4 f4 g4 | a4:h b4:h | c5:q. d5:e c5:q'),
        source: "c4:q | d4:q e4 f4 g4 | a4:h b4:h | c5:q. d5:e c5:q",
      ),
    ]),
  ]),

  // ==========================================================================
  // 第 7 章　辅助符号
  // ==========================================================================
  _IsoChapter('第 7 章', '辅助符号', [
    _IsoSection('7.2', '速度符号', [
      _IsoExample(
        clause: '7.2.2',
        title: '基本速度符号：谱表上方，首字符与生效处垂直对齐',
        note: '西文粗正体首字母大写 / 中文黑体（ Allegro 快板、Moderato 中板等）。',
        score: _j('c4:q d4 e4 f4 | g4:h a4:h | b4:q a4 g4 f4 | e4:w',
            annotations: 'Allegro * * * * * * * * * *'),
        source: "annotations: 'Allegro * ...'",
      ),
      _IsoExample(
        clause: '7.2.3',
        title: '变化速度符号：rit.、accel.、a tempo 等',
        note: '西文斜体首字母小写 / 中文宋体。',
        score: _j('c4:q d4 e4 f4 | g4:q. f4:e e4:h | d4:w',
            annotations: '* * * * rit. * * *'),
        source: "annotations: '* * * * rit. * * *'",
      ),
      _IsoExample(
        clause: '7.2.5',
        title: '节拍器速度符号：♩= 120',
        placeholder: '节拍器速度符号（Tempo 对象）尚未在简谱引擎渲染；可用文字标注代替。',
      ),
    ]),
    _IsoSection('7.3', '力度符号', [
      _IsoExample(
        clause: '7.3.8a',
        title: '器乐曲谱：力度符号记在谱表下方',
        note: '段落力度 pp/p/mp/mf/f/ff，粗斜体小写，效力至新力度符号出现。',
        score: _withDynamics(
          _j('c4:q d4 e4 f4 | g4:h a4:h | b4:q a4 g4 f4 | e4:w'),
          const [
            DynamicMarking('e0', DynamicLevel.p),
            DynamicMarking('e4', DynamicLevel.mf),
            DynamicMarking('e8', DynamicLevel.ff),
          ],
        ),
        source: "dynamics: p@e0, mf@e4, ff@e8",
      ),
      _IsoExample(
        clause: '7.3.8a',
        title: '声乐曲谱：力度符号记在谱表上方',
        note: '有歌词时力度自动置于谱表上方，避免与唱词冲突。',
        score: _withDynamics(
          _j('c4:q d4 e4 f4 | g4:h a4:h', lyrics: 'do re mi fa sol la'),
          const [
            DynamicMarking('e0', DynamicLevel.mp),
            DynamicMarking('e4', DynamicLevel.f),
          ],
        ),
        source: "lyrics: 'do re mi fa sol la'; dynamics: mp@e0, f@e4",
      ),
      _IsoExample(
        clause: '7.3.5',
        title: '突变力度符号：sf / sfz / fp 等',
        placeholder: '突变力度（sfz/fp 等）尚未加入简谱力度渲染。',
      ),
      _IsoExample(
        clause: '7.3.6',
        title: '图形力度符号：渐强号 / 渐弱号（夹角 ≤ 10°）',
        placeholder: '渐强渐弱号（hairpin）尚未在简谱引擎渲染。',
      ),
      _IsoExample(
        clause: '7.3.2',
        title: '渐变力度文字：cresc. / dim.',
        score: _j('c4:q d4 e4 f4 | g4:h f4:h | e4:w',
            annotations: 'cresc. * * * * dim. *'),
        source: "annotations: 'cresc. * * * * dim. *'",
      ),
    ]),
    _IsoSection('7.4', '表情符号', [
      _IsoExample(
        clause: '7.4.1',
        title: '表情术语：作品 / 段落开始处（粗正体首字母大写 / 中文黑体）',
        score: _j('e4:q e4:e g4:e a4:e c5:e c5:e a4:e | g4:q g4:e a4:e g4:h',
            annotations: 'cantabile如歌地 * * * * * * * * * *'),
        source: "annotations: 'cantabile如歌地 * ...'",
      ),
    ]),
    _IsoSection('7.5', '装饰音', [
      _IsoExample(
        clause: '7.5.2',
        title: '倚音（十六分小音符 + 肘状弯线）',
        placeholder: '前 / 后倚音尚未在简谱引擎实现。',
      ),
      _IsoExample(
        clause: '7.5.3',
        title: '颤音 tr（长时值音符后附波状线）',
        placeholder: '颤音 tr 及波状线尚未在简谱引擎渲染。',
      ),
      _IsoExample(
        clause: '7.5.4–7.5.5',
        title: '波音（单 / 复 / 上 / 下）与回音（顺 / 逆）',
        placeholder: '波音、回音记号尚未在简谱引擎渲染。',
      ),
    ]),
    _IsoSection('7.6', '滑音', [
      _IsoExample(
        clause: '7.6.1–7.6.3',
        title: '大滑音 / 主从滑音（上滑↗ 下滑↘）/ 并重滑音',
        placeholder: '滑音符号尚未在简谱引擎实现。',
      ),
    ]),
    _IsoSection('7.7', '琶音', [
      _IsoExample(
        clause: '7.7.1',
        title: '顺琶音（波状纵线）/ 逆琶音（带朝下箭头），记在音符左侧',
        placeholder: '琶音符号尚未在简谱引擎实现。',
      ),
    ]),
    _IsoSection('7.8', '震音', [
      _IsoExample(
        clause: '7.8.1–7.8.2',
        title: '同音高震音（右下三条斜短线）/ 不同音高震音',
        placeholder: '震音符号尚未在简谱引擎实现。',
      ),
    ]),
    _IsoSection('7.9', '通用发音符号', [
      _IsoExample(
        clause: '7.9.1',
        title: '断音：顶尖向下的实心三角形 ▼，音符正上方',
        score: _j("c4:q' d4' e4' f4' | g4:h'"),
        source: "c4:q' d4' e4' f4' | g4:h'",
      ),
      _IsoExample(
        clause: '7.9.1',
        title: '微断音 = 断音三角上方加连线',
        placeholder: '微断音（▼ 上加连线）尚未实现。',
      ),
      _IsoExample(
        clause: '7.9.2',
        title: '重音 > 与倍重音 ∧，记在音符正上方',
        score: _j('c4:q> d4> e4> f4> | g4:q^ a4^ b4^ c5^'),
        source: "c4:q> d4> e4> f4> | g4:q^ a4^ b4^ c5^",
      ),
      _IsoExample(
        clause: '7.9.3',
        title: '保持音：短横线 -，记在音符正上方',
        score: _j('c4:q_ d4_ e4_ f4_ | g4:h_'),
        source: "c4:q_ d4_ e4_ f4_ | g4:h_",
      ),
    ]),
    _IsoSection('7.10', '连线', [
      _IsoExample(
        clause: '7.10.1',
        title: '连音线（圆滑线）：不同音高音符上的弧线',
        note: '水平记在音符上方，两端对准起止音符（7.10.6）。',
        score: _j('c4:q( d4 e4 f4) | g4:h( a4:h)'),
        source: "c4:q( d4 e4 f4) | g4:h( a4:h)",
      ),
      _IsoExample(
        clause: '7.10.2',
        title: '双连线：延音线在下、连音线覆盖其上',
        score: _j('c4:q( d4 e4~ e4) | f4:h g4:h'),
        source: "c4:q( d4 e4~ e4) | f4:h g4:h",
      ),
      _IsoExample(
        clause: '7.10.1',
        title: '音节线（声乐一字多音）：唱词以延线示意',
        score: _j('c4:e d4 e4 f4 g4:q a4:q | g4:h',
            lyrics: '啊_ * * * 映 山 红'),
        source: "lyrics: '啊_ * * * 映 山 红'",
      ),
    ]),
    _IsoSection('7.11', '表演技术符号', [
      _IsoExample(
        clause: '7.11.2',
        title: '表演人数符号：solo / tutti / div. / unis.（谱表上方）',
        score: _j('c4:q d4 e4 f4 | g4:h a4:h | b4:q a4 g4 f4 | e4:w',
            annotations: 'solo * * * * * tutti * * * *'),
        source: "annotations: 'solo * * * * * tutti * ...'",
      ),
      _IsoExample(
        clause: '7.11.5',
        title: '指法符号（键盘 1–5、弦乐 1–4、空弦 0）',
        placeholder: '指法数字尚未在简谱引擎渲染。',
      ),
      _IsoExample(
        clause: '7.11.6',
        title: '换气符号（两音符之间的上方）',
        placeholder: '换气符号尚未在简谱引擎渲染。',
      ),
    ]),
  ]),
];
