# CORE_INFRA — Crisp Notation 核心渲染架构

本文档整理 Crisp Notation 的完整渲染逻辑：从文档模型到像素的端到端管线、
布局引擎的内部流水线、以及 Flutter 渲染/交互层的工作方式。它是阅读
`docs/DESIGN.md`（设计决策日志，每个非显然选择的"为什么"）的配套读物——
本文讲"是什么/怎么流转"，DESIGN.md 讲"为什么这样做"。

## 1. 仓库分层

pub workspace monorepo，三个包：

| 包 | 职责 | 硬约束 |
|---|---|---|
| `packages/crisp_notation_core` | 乐理模型 + 文档模型 + 确定性布局引擎 | 纯 Dart、零依赖，禁止 Flutter/字体光栅化/`dart:ui` |
| `packages/crisp_notation` | Flutter 渲染（RenderBox + Canvas）、交互、主题、导入导出 | 只做 staff space → px 的缩放与绘制 |
| `packages/crisp_notation_cli` | OMR（图片识谱）、Guitar Pro 解析、命令行 | 复用 core 的纯 Dart token→score 解析 |

渲染主链路：

```
Score（文档模型）
  → LayoutEngine / TabLayoutEngine / …（纯 Dart 布局，staff-space 坐标）
  → ScoreLayout（显示列表：五类图元 + 命中区域 + 墨迹包围盒）
  → RenderStaffView.performLayout（求 scale）
  → LayoutPainter.paintLayout（×scale → Canvas）
  → 屏幕 / PNG / SVG
```

## 2. 坐标系与显示列表（core 与 Flutter 之间的契约）

绑定约定（`packages/crisp_notation_core/lib/src/layout/score_layout.dart`）：

- 单位是 **staff space**（五线谱线间距），原点在顶线左端，y 轴向下。
- staff position `p`（第一线=0，逐线/间递增）→ `y = (8 − p) / 2`。
- SMuFL 约定字号 = 4 × staff space，即 `fontSize = 4 × scale`（px 侧）。
- 渲染层对 layout 的坐标**只乘一个 scale**，不做任何重排。

`LayoutPrimitive`（sealed）五类图元，即全部可绘制内容：

| 图元 | 内容 | 用途 |
|---|---|---|
| `GlyphPrimitive` | SMuFL 名 + 原点 + glyphScale | 符头/符尾/临时记号/谱号/拍号数字等 |
| `LinePrimitive` | 两端点 + 线宽 | 谱线、符干、加线、小节线、八度线 |
| `BeamPrimitive` | 四个角点（平行四边形） | 符杠、渐强/渐弱 hairpin、wedge |
| `CurvePrimitive` | 三次贝塞尔四点 + 线宽 | tie、slur、portamento、laissez vibrer |
| `TextPrimitive` | 中心锚点 + 基线 + size | 歌词、注解、指法、tab 品位数字 |

关键点：core 无法测字宽，文本一律**中心锚定**，宽度按 0.5em/字符估算
（只用于避碰）；渲染端真实文本居中于同一锚点，天然一致。

每个图元可带 `elementId` —— 交互命中、高亮、着色、隐藏（拖拽时）、
逐元素重画的全部挂钩都在它上面。

`ScoreLayout` = `primitives`（即绘制顺序）+ `regions`（元素命中盒）+
`measureRegions`（小节 x 区间，用于点按→小节映射）+ `width / height / top`
（墨迹包围盒；`top` 通常为负，即谱线上方的墨迹高度）。

## 3. 布局引擎：两阶段流水线

入口 `LayoutEngine.layout()` 只是参数包装，真正干活的是私有 `_LayoutBuilder`
（`layout_engine.dart`，用 Dart `part` 拆成 9 个文件：主循环 / beaming /
spans / furniture / annotations / barlines / tuplets / marks / overlays）。

`_LayoutBuilder.build()` 的顺序是**承载性的**（后面的 pass 依赖前面的墨迹，
改动顺序必须跑全 golden 套件）：

**阶段 1 — leading + 逐小节主循环**

1. 谱号（含 C 谱号、打击乐谱号、八度移位谱号，占位列 `x = 0.5` 起）；
2. 调号（按升/降号 SMuFL 位置表逐列放置）；
3. 拍号（SMuFL 数字上下对齐；common/cut 用专用 glyph）；
4. 逐小节 `_layoutMeasure`：
   - 先 `_computeBeamGroups`（按拍窗分组，规则 7；加性拍号/复拍子由
     `TimeSignature.beamGroups()` 驱动；处理跨小节符杠、feathered beam、
     强制斜率）；
   - 逐元素 `_layoutNote`：grace notes → 临时记号（规则 9：按
     `(step, octave)` 的小节内状态机决定是否显示；v0.6.1 起按 zigzag
     列堆叠避让）→ 符头（规则 11：二度音程翻转到符干另一侧）→
     登记 `_TieInfo`（后续所有 span pass 的查找表，v0.6.5 起有 O(1)
     索引）→ 加线 → 符干（**被成杠的音符延迟画干**，只存 `_BeamedNote`
     桩）→ 符尾/震音/附点（复附点间距按拍宽缩放，规则 14）；
   - `_advance` 推进光标（见 §4 间距公式）；
   - 小节末尾统一画延迟的符杠组（斜率 clamp ±1 staff space、最短干长、
     不跨中线），再画 articulations / fingerings / arpeggios / tuplets；
   - 小节线 / 反复 / 结尾括号 / 多小节休止。

**阶段 2 — 全谱 post-passes**（顺序固定）：跨小节符杠 → ties →
laissez vibrer → 力度记号 → slurs → glissando → portamento → ottava →
trill 延线 → 踏板 → 歌词 → 数字低音 → 音名标注 → 导航记号（D.S./coda）→
注解/和弦标记 → jazz 记号 → palm-mute/barre/vibrato → 换气记号 →
和弦图 → 拍号数字覆盖 → 小节号 → 终止线。

谱线（staff lines）最后生成但 `insertAll(0, …)`，保证最先绘制、被一切覆盖。

## 4. 光学间距公式

`_advance`（layout_engine.dart，`spacingBase / spacingPerLog2 /
spacingStretch` 三个旋钮）：

```
ideal = (spacingBase + spacingPerLog2 × (4 + log2(duration))) × spacingStretch
实际推进 = max(ideal, inkRight + minNoteGap − x, lyricReserve − x)
```

- 时值越短间距越小但非线性压缩（对数律），与雕刻惯例一致；
- `inkRight` 是该元素真实墨迹右缘（含临时记号列、附点），保证永不重叠；
- 歌词宽度通过 `_lyricReserveFor` 成为下限，保证音节不挤。

**确定性（rule 14）**：除 tuplet 的 `log2(actual/normal)` 外禁止任何
超越函数/平台相关调用——`log2` 用查表，附点系数用常量表。同一 Score
在任何平台、任何年份产出逐位相同的布局（golden 测试的前提）。

## 5. 天际线避碰（v0.6.8）

每个字形/图元放置时把墨迹矩形记入 `_inkRects`；`_skylineTop / _skylineBottom`
对任意 x 区间做逐列天际线查询。浮动记号（力度、注解、歌词、ottava…）只需
避开**自己水平跨度内**的真实墨迹，而不是全谱行极值。刻意用线性扫描而非
平衡树，换取逐位确定性。slur 另沿 64 个采样点做 `_slurClearanceOffset`
间隙修正（v0.6.7）。

## 6. 多声部

单小节内超过一个声部时走独立代码路径 `_layoutMultiVoiceMeasure`：
合并各声部 onset 为列，列内二度碰撞右移，临时记号状态跨声部共享。
设计决策（见 DESIGN.md §2.7）：**不与单声部路径合并**——合并会让两个
正确实现对齐，但会扰动既有 golden 基线。

## 7. 跨谱表对齐（§2.9 gridding）

`alignedColumns`（`grand_staff.dart`）：

1. 各谱表先自然布局一次；
2. 量出每个元素的"符头左/右墨迹"，取跨谱表逐 onset 的最大值，生成共享
   onset→x 列表——**列锚在符头而非墨迹左缘**，临时记号从列向左伸出
   （v0.6.6，修正了早期锚在墨迹左缘导致的不均匀间距）；
3. 以 `forcedColumns` 喂回每个谱表的 `LayoutEngine.layout` 重排。

结果：同时发声的音符跨谱表垂直对齐（钢琴大谱表、总谱的正确形态）。

## 8. 换行、系统与分页

- `layoutSystems`（`multi_system.dart`）：**切片式**换行——每个 system 是
  带着运行中 clef/key/time 的子 Score 重新布局；贪心装箱 + Illinois 变体
  regula falsi 搜索 `spacingStretch` 做两端对齐（`_stretchToFit`，把 24 次
  全量布局降到 ~3–5 次；这是实测的最大热点）。跨系统的 slur/力度跨度
  **丢弃不拆分**（v0.6 再 polish）。
- `StaffSystem` / `layoutStaffSystem`（`staff_system.dart`）：N 谱表系统，
  bracket/brace 分组、barline group（自定义跨表小节线）、`hideEmptyStaves`；
  先自然布局取 leading/小节宽列最大值，再统一重排使小节线对齐。
- `MultiPartScore` / `layoutMultiPartPages`（`multi_part.dart`）：文档层——
  N 个 part（相同小节数与拍号）→ `toStaffSystem()` → 换行 → 贪心垂直装页，
  非末页可做垂直两端对齐。
- `TabLayoutEngine`（`tab_layout.dart` + `tab_techniques.dart`）：**并行
  记谱法引擎**的范本——读同一个 `Score`，把音高分配到 (string, fret)，
  产出同样的 `ScoreLayout` 图元（品位数字用 `TextPrimitive`，符干/符杠在
  谱表下方）。支持 `barlineXs` 参数与五线谱逐小节线对齐
  （`layoutNotationTab`）。

## 9. Flutter 渲染层

`StaffView` 是 `LeafRenderObjectWidget`；`RenderStaffView` 是唯一几何权威：

- **布局时机**：`performLayout` 中若 SMuFL 元数据未就绪，异步
  `MusicFonts.load` 后自我 relayout（首帧空白是刻意的温和降级）。就绪后
  调 `LayoutEngine.layout`；`staffSpace` 显式给定则 scale 固定，否则
  `scale = maxWidth / layout.width`（fit-to-width）。
- **增量更新纪律**：score/主题结构变化 → `markNeedsLayout`；高亮、
  元素颜色、ghost note → 仅 `markNeedsPaint`。`lineBoost` 会进
  LayoutSettings 所以触发 relayout；纯换色只 repaint。
- **绘制**：`LayoutPainter.paintLayout` 遍历图元——glyph 用 `TextPainter`
  （`computeDistanceToActualBaseline` 定位原点），按 `(glyph, color, scale)`
  缓存；线 / beam（Path 平行四边形）/ curve（cubicTo）/ text 分别走 Canvas
  对应 API。
- **着色优先级**：运行时 `highlightedElementId` > 运行时 `elementColors` >
  `theme.elementColors` > `noteColor`。`suppressIds` 整体跳过某元素——
  拖拽时配合 `paintElement` 半透明重画，实现"真字形跟随指针"。
- 主题 `CrispNotationTheme`：staffColor / noteColor / highlightColor /
  elementColors / musicFont（默认 Bravura）。

视图家族全部复用同一 painter：`GrandStaffView`（brace 缩放字形）、
`MultiSystemView`、`StaffSystemView`、`MultiPartView`、`ScorePageView`、
`TabStaffView` / `NotationTabView`、以及非谱面的 `PianoKeyboardView` /
`FretboardView`。

## 10. 离屏与交换格式

- **PNG**：`renderLayoutToPng`（`png_export.dart`）用 `PictureRecorder` +
  同一个 `LayoutPainter` 光栅化——屏幕内外像素一致。
- **SVG**：core 内纯 Dart `scoreToSvg`（无 `dart:ui`），同一 `ScoreLayout`
  的另一种序列化；可离线跑（CLI、服务端）。
- **导入**：MusicXML / MEI / LilyPond / ABC / Humdrum kern / Guitar Pro /
  MIDI / MuseScore → 统一 `Score` 模型 → 同一条渲染管线；MusicXML 导出
  保证 `scoreFromMusicXml(scoreToMusicXml(s)) == s` 往返。

## 11. 交互层（渲染逻辑的延伸）

- `RenderStaffView` 同时是几何服务：`localToStaff / staffToLocal`、
  `elementIdAt`（hitSlop 膨胀后**最小区域优先**）、`quantizeStaffPosition`
  （吸附到 −6..14 的合法音位）。
- `InteractiveStaff` 只是手势胶水：拖拽 = ghost note 预览 + 松手量化落点。
- `ScoreEditorController`（ChangeNotifier）驱动 errorOverlay / loopRange 等
  **仅重绘**的编辑器覆盖层；滚动由 app 持有的 `ScrollController` 反向注入。
- 设计立场：**crisp_notation 渲染，app 驱动**——编辑器、游戏、教学工具在
  外面用同一套几何服务各自实现。

## 12. 测试基线

- `crisp_notation_core/test/layout_golden_test.dart` + `goldens/`：120+ 场景的
  `ScoreLayout` 逐位快照（`update_goldens` 重生成）。
- `crisp_notation/test/pixel_goldens/`：像素级 golden。
- `layout_pixel_test.dart`：把图元光栅化成栅格做像素断言（不依赖字体文件）。
- 任何影响布局的改动必须三件套全绿；改顺序/间距即破坏 golden，需先确认
  意图再 `update_goldens`。
