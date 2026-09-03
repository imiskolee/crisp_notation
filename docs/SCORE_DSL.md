# 整谱 DSL 设计文档

> 状态：**已确认**。本文档定义"整谱级" DSL —— 用一份文本文件编排
> 多轨乐谱（metadata + 若干谱表轨 + 歌词轨），编译为一个 `StaffSystem`。
> 单轨 `notes` 行的音符语法沿用现有 `Score.simple` DSL（见 [DSL.md](DSL.md)），
> 本文档只定义**新增的外层结构**，不改变既有音符语法。

---

## 1. 目标与非目标

### 目标

- 一份纯文本文件描述整份乐谱：标题、调号、拍号、速度、多条谱表轨、歌词。
- 四种基本场景全部可表达（见 §6）：
  1. 简谱单谱
  2. 简谱 + 歌词
  3. 钢琴独奏（大谱表）
  4. 钢琴伴奏 + 简谱 + 歌词
- 与现有模型一一对应，编译产物是 `StaffSystem`（含每条轨的 `Score`、
  括号分组、小节线分组），不引入新的渲染概念。
- 人写友好：YAML 风格的 metadata + 极简的轨道体，错误信息定位到行。

### 非目标

- 不替代 MusicXML / ABC 等交换格式（定位是**创作与教学场景的录入格式**）。
- 不在 v1 表达：分谱页码、排版微调（systemBreak 等）、跨轨连线。
- 不修改 `notes` 行内语法（音高/时值/和弦/指令保持 DSL.md 的定义）。

---

## 2. 文件整体结构

```text
file      := metadataBlock trackBlock+
metadataBlock := '---score' NL yamlLines '---' NL
trackBlock    := ':' trackName NL trackField+
trackField    := fieldName ':' fieldValue (NL continuationLine)*
```

一份文件 = **一个 metadata 块**（必须，且必须在最前）+ **一个或多个轨道块**。

```text
---score
title: 欢乐颂
timeSignature: 4/4
tempo: 80
tracks:
  - name: 合唱
    type: jianpu
---
:合唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4
lyrics: 欢 乐 女 神 圣 洁 美 丽
```

### 2.1 分隔与空白规则

- `---score` 与 `---` 是**独占一行**的分隔标记，区分大小写、不缩进。
- 轨道头 `:轨道名` 独占一行；`:` 后紧跟名字，名字可含中英文与下划线，
  不可含空白与冒号。
- 轨道体内的字段写作 `字段名: 值`，字段名顶格、冒号后一个空格（可省略）。
- 字段值**可以跨行**：不以 `字段名:` 开头的后续行视为上一字段的续行，
  以换行连接。`notes` 因此可以自由折行排版：

  ```text
  :piano_right
  notes: c4+e4+g4:q c4+e4+g4:q |
         g4+b4+d5:q g4+b4+d5:q |
  ```
- 空行忽略；`#` 开头的行是注释（整行注释，不支持行尾注释——避免与
  变音记号 `#` 冲突）。

### 2.2 字段重复规则

- metadata 块内：标准 YAML，字段不可重复（重复即 `FormatException`）。
- 轨道体内：同一字段**允许重复出现**，语义为追加连接（`notes`/`lyrics`
  多次出现时按顺序拼接，中间视为空格）。这让长旋律可以分段书写：

  ```text
  :合唱
  notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |
  notes: c4:q c4 d4 e4 | e4:q. d4:e d4:h |
  ```

- 重复出现的 `notes:` 字段视为**新乐段**的开始：若上一段末尾缺少 `|`，
  解析器自动补上小节线，避免两段首尾并入同一小节。因此分段书写时
  段末的 `|` 可写可不写；**小节内部**的折行请用续行（缩进、不带
  字段名），续行按原样拼接、不做任何自动补全。
- 配合歌词分段（§4.3），可以写成"一段音符 + 该段各段歌词"交替的
  块结构，长谱按段阅读最清晰：

  ```text
  :独唱
  notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |
  lyrics: 欢 乐 女 神 圣 洁
  lyrics2: 灿 烂 星 光 照 耀
  notes: c4:q c4 d4 e4 | e4:q. d4:e d4:h |
  lyrics: 美 丽 你 的 光 芒
  lyrics2: 大 地 充 满 光 辉
  ```

---

## 3. metadata 块

metadata 是受限的 YAML 子集：只支持 `键: 值` 与 `tracks:` 下的列表项
（`- ` 开头的映射），不支持嵌套映射、多行字符串、锚点。这样可以在不引入
YAML 依赖的前提下手写解析（core 保持零依赖）。

### 3.1 字段表

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `title` | string | 是 | 曲名，渲染在首页顶部 |
| `description` | string | 否 | 副标题/说明文字 |
| `authors` | string | 否 | 作者；映射到 `ScoreMetadata.composer` |
| `scale` | string | 否（默认 `C`） | 调号，见 §3.2 |
| `timeSignature` | string | 否 | **拍号**，形如 `4/4`、`3/8`，见 §3.3 |
| `tempo` | int | 否 | **速度**，四分音符 = N BPM，映射到 `Tempo` |
| `layout` | string | 否（默认 `page`） | 页面布局：`page` 按可用宽度自动换行为多行谱面；`single` 整曲排成无限长单行（横向滚动）。作用于预览与导出，编译产物经 `ScoreDslResult.layout` 暴露 |
| `tracks` | list | 是 | 轨道声明列表，见 §4 |

### 3.2 `scale`（调号）

表示首调主音（简谱的"1=X"）或五线谱调号：

```text
scale := ('C'|'D'|'E'|'F'|'G'|'A'|'B') ('#'|'b')? ('m')?
```

| 写法 | 含义 | 五线谱调号 | 简谱行首标签 |
| --- | --- | --- | --- |
| `C` | C 大调 | 无升降 | `1=C` |
| `G` | G 大调 | 1# | `1=G` |
| `F` | F 大调 | 1b | `1=F` |
| `Bb` | 降 B 大调 | 2b | `1=♭B` |
| `F#` | 升 F 大调 | 6# | `1=♯F` |

- 大小写不敏感（`bb` ≡ `Bb`）。**单独的 `b` 是非法值**（会与降号后缀
  产生歧义）——降 B 调必须写作 `Bb`。
- 小调用 `scale: Am` 形式（v1 只映射到关系大调的 `KeySignature`，
  简谱标签渲染 `6=A` 风格**暂缓**）。
- 调号对音符生效：不带变音记号的音名按调号升降（`Eb` 调下 `b4` 即
  B♭4，落在 B 间上、不另画记号）；临时改音写显式变音记号（`bn4`
  还原 B、`f#4` 升 F）。
- v1 只支持**整曲一个调**；中途转调用轨道内的 `!key=N` 指令（已有）。

### 3.3 `timeSignature`（拍号）

```text
timeSignature := 数字 '/' 数字   // 如 4/4、3/8、6/8
```

- 省略时渲染为无拍号片段（与 `Score.simple` 不传 `timeSignature` 一致）。
- 所有轨道共用同一拍号；中途变拍用 `!time=N/D` 指令（已有）。

---

## 4. 轨道声明（`tracks:`）

```yaml
tracks:
  - name: piano_right
    type: standard
    clef: treble
  - name: piano_left
    type: standard
    clef: bass
  - name: 独唱
    type: jianpu
  - name:
    type: lyrics
```

### 4.1 轨道字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 谱表轨必填 | 轨道名，同时是轨道块的引用名；渲染为行首乐器名（可开关） |
| `type` | enum | 是 | 见 §4.2，大小写不敏感（`Jianpu` ≡ `jianpu`） |
| `clef` | enum | 否 | 仅 `standard` 轨有效：`treble`（默认）/`bass`/`alto`/`tenor`；简谱轨忽略此字段 |
| `for` | string | 否 | 仅 `lyrics` 轨：指定附着的谱表轨名；缺省附着**前一条谱表轨** |
| `instrument` | string/int | 否 | GM 音色名或 program 号，映射 `ScoreMetadata.midiProgram`（回放用） |
| `group` | string | 否 | 分组名，控制括号与小节线连接，见 §5.2 |

### 4.2 轨道类型 `type`

| type | 模型映射 | 说明 |
| --- | --- | --- |
| `standard` | `Score(staffType: StaffType.standard)` | 五线谱 |
| `jianpu` | `Score(staffType: StaffType.jianpu)` | 简谱（数字谱） |
| `lyrics` | 不产生 `Score` | 独立歌词行，附着到某一谱表轨（§4.3） |
| `tablature` | `Score(staffType: StaffType.tablature)` | 预留，v1 不实现 |
| `percussion` | `Score(staffType: StaffType.percussion)` | 预留，v1 不实现 |

### 4.3 歌词写法

**行内歌词（推荐）**：谱表轨轨道体内直接写 `lyrics:` 字段，逐字对齐到
该轨的音符（`*` 显式跳过一个音符、`-` 分字、`_` 延音）：

```text
:合唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4
lyrics: 欢 乐 女 神 圣 洁 美 丽
```

不占字的音符（歌词 token 自动跳过，无需占位符）：

- **休止符**；
- **连音符的后续音**：`~` 延音线（`c4:q~ | c4:q`）的被连音不再演唱，
  不分配歌词；
- **同音高连音线的结束音**：`g4( | g4)` 这类起止音高完全相同的连线
  按简谱惯例读作延音线，结束音不分配歌词（不同音高的连线是圆滑线，
  每个音正常占字）。

```text
:简谱
notes: a4:q g4( | g4:e) a4:q     # g4(…g4) 同音连线，共唱一个字
lyrics: 我 们 的                 # 3 个字对 3 个发声音符
```

**多段歌词**：在同一谱表轨轨道体内用 `lyrics:`（第 1 段）、`lyrics2:`
（第 2 段）、`lyrics3:`（第 3 段）… 多次书写。每段独立解析，对齐同一轨
音符，`verse` 字段递增：

```text
:独唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4
lyrics: 欢 乐 女 神 圣 洁 美 丽
lyrics2: 灿 烂 星 光 照 大 地
```

- `lyricsN:` 中的 N 从 2 开始递增；第 1 段始终用 `lyrics:`（无数字后缀）。
- 段号不要求连续，但渲染按 `verse` 字段值堆叠。
- 若 metadata 的 `tracks:` 中声明了 `type: lyrics` 轨，其 `for:` 指定的
  谱表轨轨道体内可写 `lyrics2:` 等，表示该独立歌词轨对应第 N 段。

---

## 5. 轨道块与模型映射

### 5.1 轨道体字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `notes` | 谱表轨必填 | DSL 音符行（DSL.md 全文法），可折行、可重复追加 |
| `lyrics` | 否 | 第 1 段歌词 |
| `lyricsN` | 否 | 第 N 段歌词（N≥2） |
| `annotations` | 否 | 谱上标注（同 `Score.simple(annotations:)`） |

- 每条谱表轨的 `notes` 用 `Score.simple` 同款解析器解析，传入该轨的
  `clef`/`staffType` 与全局的 `keySignature`/`timeSignature`/`tempo`。
- **小节数一致性**：编译期校验所有谱表轨的小节数相等，不等则报
  `FormatException`，指出最短/最长轨名与行号。
- 元素 id：每轨独立编号 `e0…`（沿用 `Score.simple` 的自动编号）。
  跨轨唯一性由消费者按谱表索引区分；DSL v1 不支持跨轨引用。

### 5.2 分组：括号与小节线连接

所有多轨一律编译为 `StaffSystem` + `StaffBracket` + `BarlineGroup`，
不使用 `GrandStaff` 快路径（`GrandStaff` 仅作为布局引擎内部优化，DSL 层
不感知）。

- 同 `group` 名的相邻 `standard` 轨：花括号（`StaffBracketKind.brace`）
  + 小节线贯通（一个 `BarlineGroup`）。
- 未声明 `group` 的轨：各自独立，不画括号。
- `jianpu` 轨**永远不**与邻轨连接小节线（既有行为：`_autoBreakAtJianpu`
  自动拆分 BarlineGroup，DSL 层无需特殊处理）。
- 钢琴独奏惯例可简写：

  ```yaml
  tracks:
    - {name: right, type: standard, clef: treble, group: piano}
    - {name: left,  type: standard, clef: bass,   group: piano}
  ```

### 5.3 编译产物

```text
ScoreDslDocument
  └─ compile() → ScoreDslResult
       ├─ system (StaffSystem)
       │    ├─ staves       ← 每条谱表轨一个 Score
       │    ├─ brackets     ← group 字段 → StaffBracket
       │    └─ barlineGroups ← group 字段 → BarlineGroup
       └─ meta (ScoreDslMeta)
            ├─ title / description / authors → ScoreMetadata
            └─ tempo → Tempo（回放与导出用）
```

---

## 6. 四个基本场景（验收用例）

### 场景 1：简谱单谱

```text
---score
title: 小星星
scale: C
timeSignature: 4/4
tempo: 96
tracks:
  - name: 旋律
    type: jianpu
---
:旋律
notes: c4:q c4 g4 g4 | a4:q a4 g4:h | f4:q f4 e4 e4 | d4:q d4 c4:h |
```

### 场景 2：简谱 + 歌词

```text
---score
title: 欢乐颂
description: 贝多芬《第九交响曲》- 合唱部分
authors: 贝多芬
scale: Bb
timeSignature: 4/4
tempo: 80
tracks:
  - name: 合唱
    type: jianpu
---
:合唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | e4:q. d4:e d4:h |
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | d4:q. c4:e c4:h |
lyrics: 欢 乐 女 神 圣 洁 美 丽 你 的 光 芒 照 大 地
```

### 场景 3：钢琴独奏（大谱表）

```text
---score
title: 我的祖国（钢琴独奏）
authors: 集体
scale: G
timeSignature: 4/4
tempo: 110
tracks:
  - name: piano_right
    type: standard
    clef: treble
    group: piano
  - name: piano_left
    type: standard
    clef: bass
    group: piano
---
:piano_right
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | e4:q. d4:e d4:h |
:piano_left
notes: c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q |
notes: g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q |
```

### 场景 4：钢琴伴奏 + 简谱 + 歌词

```text
---score
title: 我的祖国
scale: G
timeSignature: 4/4
tempo: 110
tracks:
  - name: 独唱
    type: jianpu
  - name: piano_right
    type: standard
    clef: treble
    group: piano
  - name: piano_left
    type: standard
    clef: bass
    group: piano
---
:独唱
notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 | c4:q c4 d4 e4 | d4:q. c4:e c4:h |
lyrics: 一 条 大 河 波 浪 宽 风 吹 稻 花 香 两 岸
lyrics2: 我 家 就 在 岸 上 住 听 惯 了 艄 公 的 号 子
:piano_right
notes: c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q |
notes: g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q g4+b4+d5:q |
:piano_left
notes: c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q c2+e3+g3:q |
notes: g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q g2+d3+g3:q |
```

渲染顺序 = `tracks` 声明顺序（独唱简谱在上，钢琴大谱表在下，小节线
横向对齐；简谱轨不画贯通小节线）。

---

## 7. 错误处理

所有错误抛 `FormatException`，消息格式：

```text
line N [track: name] description
```

| 错误 | 示例消息 |
| --- | --- |
| metadata 缺失/不在最前 | line 1: file must start with `---score` |
| YAML 子集越界 | line 8: unsupported YAML structure (nested map) |
| 未知 metadata 字段 | line 5: unknown field `spped` (did you mean `tempo`?) |
| `scale` 非法 | line 4: invalid scale `b` (expected `C`/`G`/`Bb`/`F#` etc.) |
| `timeSignature` 非法 | line 5: invalid time signature `4:4` (expected `4/4`) |
| 引用了未声明的轨道块 | track `伴奏` not declared in metadata.tracks |
| 声明了轨道但缺轨道块 | track `piano_left` has no `:piano_left` block |
| 轨道体缺 `notes` | track `piano_left` (type: standard) missing `notes:` |
| 小节数不一致 | measure count mismatch: 独唱 4, piano_right 3 |
| `notes` 内语法错误 | 透传 `Score.simple` 的异常并附加轨道名与行号 |
| 歌词轨 `for` 指向不存在/歌词轨 | `for: xxx` must reference a staff track |

---

## 8. 与现有代码的关系

| DSL 概念 | 现有实现 |
| --- | --- |
| `notes` 行语法 | `Score.simple`（`packages/crisp_notation_core/lib/src/model/score.dart`） |
| `type: jianpu/standard` | `Score.staffType` + `RenderStaffView` 路由 |
| `group: piano` | `StaffBracket` + `BarlineGroup` |
| 简谱轨不贯通小节线 | `_autoBreakAtJianpu`（既有） |
| `title`/`authors`/`instrument` | `ScoreMetadata` |
| `tempo` | `Tempo`（回放） |
| `timeSignature` | `TimeSignature` |
| `scale` | `KeySignature`（新增 scale→fifths 映射） |
| 小节数校验 | 编译期校验（新增） |

**新增模块**：`packages/crisp_notation_core/lib/src/score_dsl/`
（解析器 + `ScoreDslDocument` 模型 + `compile()`），纯 Dart 零依赖；
CLI 增加 `crisp_notation render score.txt` 入口（后续开发任务）。

---

## 9. 决策记录

| # | 决策点 | 结论 |
| --- | --- | --- |
| 1 | 拍号/速度键名 | `timeSignature: 4/4` + `tempo: 80`（BPM） |
| 2 | `scale: b` 语义 | 非法，降 B 调必须写作 `Bb` |
| 3 | 多段歌词写法 | 谱表轨体内 `lyrics:` / `lyrics2:` / `lyrics3:` 递增 |
| 4 | 钢琴组编译 | 统一 `StaffSystem`，不走 `GrandStaff` 快路径 |
| 5 | 元素 id 跨轨唯一 | 每轨独立 `e0…`，跨轨由消费者按谱表索引区分；v1 不支持跨轨引用 |
| 6 | 行首轨道名显示 | v1 不在 DSL 表达，由 UI 层控制 |
| 7 | 简谱轨 `clef` 字段 | 忽略（简谱无谱号概念） |
