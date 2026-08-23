# JIANPU — 简谱渲染设计

状态：设计已确认（字段落点 / 调式范围 / 首版范围三项已拍板），待实现。
配套阅读：`docs/CORE_INFRA.md`（渲染管线全貌）、`docs/DESIGN.md`（决策日志惯例）。

## 1. 目标与定位

让同一个 `Score` 文档模型可以按**简谱**（首调数字记谱法）渲染，与现有
五线谱、TAB 谱平行。简谱在这里是一种**记谱法引擎**（notation engine），
不是一种新数据模型——与 `TabLayoutEngine` 的地位完全一致：

```
Score（Pitch/duration/记号，不变）
  → JianpuLayoutEngine（新增，纯 Dart，core 内）
  → ScoreLayout（同一套五类图元）
  → LayoutPainter（零改动）
```

## 2. 已确认的决策

| 决策 | 结论 | 理由 |
|---|---|---|
| StaffType 字段落点 | `Score.staffType`，默认 `standard` | additive 惯例：不传则逐位不变；`Score` 即本库的"单谱表"实体 |
| 调式范围 | v1 只做大调（1=主音） | 小调（6=主音）依赖模型还没有的 mode 概念，v2 随 mode 字段一起做 |
| 首版范围 | 单谱表先行 | 先交付引擎 + 视图路由 + golden；系统混排/换行留 v2，风险可控 |

`StaffType` 一次定义全：

```dart
enum StaffType { standard, jianpu, tablature, percussion }
```

- `tablature`：把现有 Tab 引擎纳入统一路由（调用点从"显式调引擎"变为
  "按 type 路由"）。
- `percussion`：五线谱引擎 + 打击乐谱号 + x 符头的固化入口（零件已存在）。

## 3. 模型层改动

`Score` 增加一个字段（构造函数、copyWith、==、hashCode、toString、
`transposedBy` 透传——有测试强制 copyWith 不漏字段）：

```dart
/// 谱表记谱法类型；默认 standard（五线谱）。
final StaffType staffType;
```

交换格式：MusicXML `<staff-type>`（`staff-details/staff-type`，取值含
`ossia/cue/blank/alternate/tablature` 等）做尽力映射；jianpu 非 MusicXML
标准值，导出时写 `alternate` 并在 `ScoreMetadata.extras` 存
`crisp.staffType=jianpu` 以自描述，导入时优先读 extras。其余格式丢弃
（与"不可表示即丢弃"惯例一致）。

## 4. JianpuLayoutEngine 设计

新文件 `packages/crisp_notation_core/lib/src/layout/jianpu_layout.dart`
（需要时用 `part` 拆 `jianpu_underlines.dart` 等，沿用引擎的拆法惯例）。

### 4.1 坐标约定（沿用 staff space 契约）

- 单位仍是 staff space；数字行的**基线 y = 3.0**，数字视觉中心 ≈ y = 2.5
  （数字 size 2.0）。
- 小节线画 y = 1.0…4.0（一行数字的高度，不画五条谱线）。
- 上方（y < 1.0）：tie/slur、力度、注解、跳音记号。
- 下方（y > 4.0）：歌词、减时线下方的空间。减时线紧贴数字底部
  （y ≈ 3.55 / 3.95 两条位置）。
- 引擎产出正常的 `ScoreLayout`（含 regions/measureRegions/墨迹包围盒），
  `top` 可能为负——渲染层不需要知道这是简谱。

### 4.2 音高 → 数字（大调，v1）

复用 shape-note 已有的 tonic 推导（`_keyTonicStepIndex`，layout_furniture.dart）：

```
tonicStep = stepOfFifth[(fifths % 7 + 7) % 7]        // C=0…B=6
degree    = (pitch.step.index − tonicStep + 7) % 7   // 0…6 → 显示 1…7
alter     = pitch.alter − keySignature.alterFor(pitch.step)
          // 0 无记号；±1 数字前置 #/♭；±2 双升双降（v1 直接写 ##/♭♭ 文本）
```

八度点：以 tonic 所在八度为基准，`n = floor((pitch 的全音阶序号 − tonic
的全音阶序号) / 7)`；n > 0 在数字上方加 n 个高音点，n < 0 在下方加
|n| 个低音点。基准八度 = tonic 在谱面首次出现的八度（参数 `tonicOctave`
可覆盖，默认 4 区映射到科学音高记号的中音区）。

临时记号显示规则沿用规则 9 的小节内状态机（按 (degree, octave) 记忆），
与五线谱行为一致。

休止符 → 数字 `0`（不占八度点、不参与级数换算）。

### 4.3 时值 → 记法

| 时值 | 记法 |
|---|---|
| 四分 | 裸数字 |
| 附点四分及更长 | 数字 + 附点（右侧小圆点） |
| 二分 | 数字 + 1 条增时线（`–`，占一个数字位宽） |
| 全音符 | 数字 + 3 条增时线 |
| 八分 | 数字 + 1 条减时线（下划线） |
| 十六分 | 数字 + 2 条减时线 |
| 三十二分/六十四分 | 3 / 4 条减时线 |

**减时线分组**直接复用 `TimeSignature.beamGroups()` 的拍窗逻辑（与符杠
规则 7 同源）：同一拍窗内的八分及更短音符共享第一条下划线（贯穿组内
所有数字底部），第二条下划线只覆盖十六分音符（类似五线谱的次级符杠
分段）。跨拍不连线。组内第一个四分音符出现时组结束（与符杠组一致）。

**增时线占位**：每条增时线占一个"数字单元"宽度并参与小节总宽，所以
二分/全音符自然更宽——这也是混排时与五线谱列对齐的锚。

### 4.4 间距

复用与五线谱引擎同构的对数间距（保证 v2 混排时列距可推导）：

```
ideal = (spacingBase + spacingPerLog2 × (4 + log2(duration))) × spacingStretch
下限1 = 数字宽度 + minNoteGap
下限2 = 增时线条数 × 数字单元宽（二分/全音符）
下限3 = 歌词宽度（_lyricReserveFor 同款逻辑）
```

`log2` 走查表，遵守 rule 14（无超越函数，逐位确定性）。

### 4.5 引擎流水线（沿用 build() 两阶段结构）

1. leading：调号文本 `1=C`（`TextPrimitive`，由 tonic step + alter 生成，
   如 `1=♭E`）→ 拍号（上下两个数字文本，4/4 样式；common/cut 写 C/¢）；
2. 逐小节：预算减时线分组（拍窗）→ 逐元素放数字（级数、临时记号前缀、
   八度点、附点、增时线）→ 登记 tie/slur 锚点 → 小节末统一画减时线组
   → articulations（简谱惯例支持 staccato/accent/tenuto/fermata，画上方）；
3. post-passes：ties（同音级弧线，上方）→ slurs（上方）→ 力度 → 歌词
   （下方，复用歌词对齐）→ 注解/和弦标记（上方文本）→ 小节线/反复/
   volta/终止线 → 小节号。
4. 避碰复用 `_inkRects` + 天际线思路（简谱元素少，v1 可用简化的固定
   槽位：上方三层、下方两层，不进天际线；v2 混排时再升级）。

### 4.6 与系统层的关系（v2 预埋，v1 不实现）

引擎签名预留 `leadingWidth` / `barlineXs` / `forcedColumns`（列锚 = 数字
中心），与 `TabLayoutEngine.layout` 同款——v2 让 `layoutStaffSystem`
把硬编码的 `LayoutEngine()` 改为按 `score.staffType` 路由后，"上五线谱
下简谱"的合唱伴奏谱即可对齐小节线。换行 `layoutSystems` 同理按 type
切片。v1 只保证这些参数存在且被尊重（传入时生效），系统层路由 v2 做。

## 5. 渲染层改动

- `StaffView` / `RenderStaffView`：布局入口按 `score.staffType` 选择引擎
  （`standard`/`percussion` → LayoutEngine，`jianpu` → JianpuLayoutEngine，
  `tablature` → TabLayoutEngine）。对外 API 不变，app 无感。
- `LayoutPainter` 零改动（简谱 = 文本 + 线 + 曲线）。
- 主题：数字沿用 `noteColor`；`CrispNotationTheme` 暂不加新字段，简谱
  文本用默认文本字体。若后续要数字专用字体（等宽、雕刻风格），加
  `jianpuFontFamily` 一个字段即可（additive）。

## 6. 交互影响

- `elementId` 挂在数字图元上：高亮、点击、`elementColors`、`suppressIds`
  全部零成本可用。
- `quantizeStaffPosition` 对简谱降级为"只做时间轴（x→onset）定位"，y 不
  映射音高；编辑落点（级数选择器）属于 app 层，不进本库。
- PNG / SVG 导出复用现有路径，自动支持简谱。

## 7. v1 验收范围

支持：级数 1–7、临时记号 #/♭（含小节内记忆）、高/低音点、休止符 0、
增时线、附点、减时线按拍分组（含次级分段）、`1=X` 调号、分数拍号、
小节线/反复/volta/终止线、tie、slur、力度、歌词、注解、跳音类记号、
多小节结构、与五线谱一致的间距/确定性约束。

明确不支持（v2+）：小调 6=主音、系统混排对齐、换行、多声部叠写、
和弦（v1 取最高音，记为已知降级）、简谱 DSL 输入、SMuFL 简谱字形
（v1 数字用文本字体）。

## 8. 测试策略

- core golden：新场景文件进 `crisp_notation_core/test/goldens/`
  （`jianpu/…`），覆盖：C/F/G/D/♭B 各调的级数与临时记号、八度点
  （跨三个八度）、全部时值记法、减时线分组（含 4/4、3/4、6/8、加性
  拍号）、tie/slur/歌词/力度叠加、反复与 volta。
- 像素测试：复用 `layout_pixel_test.dart` 的栅格光栅化断言（数字用文本
  字体，pixel 测试用其字体无关的断言模式）。
- 确定性：同一 Score 布局两次逐位相等（引擎无 DateTime/随机/浮点平台
  差异，rule 14）。
- `StaffType` 进模型后的既有测试：默认 `standard` 保证全部既有 golden
  不变（additive 纪律的直接验证）。

## 9. 实现触点清单（供任务拆分）

core：
- `lib/src/model/score.dart` — `staffType` 字段（构造/copyWith/==/hashCode/
  transposedBy）
- `lib/src/layout/jianpu_layout.dart`（新增引擎；必要时 part 拆分）
- `lib/src/layout/layout_settings.dart` — 简谱间距/字号旋钮（additive 默认）
- `lib/crisp_notation_core.dart` — 导出 `StaffType`、`JianpuLayoutEngine`
- `lib/src/interchange/musicxml*.dart` — extras 自描述往返（可后置 v1.1）

flutter：
- `lib/src/rendering/staff_view.dart` — 引擎路由
- `test/goldens`/`test/pixel` — 简谱场景

cli：无需改动（OMR/GP 导入产出 Score，自然可简谱渲染）。
