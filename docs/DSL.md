# Crisp Notation DSL 编写教程

`Score.simple` 是 crisp_notation 内置的文本 DSL（领域特定语言），用一行字符串描述
整份乐谱：音高、时值、和弦、连音、反复、歌词……解析器位于
`packages/crisp_notation_core/lib/src/model/score.dart`，同一份 DSL 既可用于五线谱，
也可用于简谱（切换 `staffType` 即可，音符写法完全一致）。

```dart
final score = Score.simple(
  timeSignature: TimeSignature.fourFour,
  staffType: StaffType.jianpu,   // 省略则为五线谱
  notes: 'c4:q d4 e4 f4 | g4:w',
);
```

---

## 1. 整体结构

```text
notes := 小节 ('|' 小节)*          // 竖线分隔小节
小节  := 记号 (空格 记号)*          // 空格分隔的 token
小节  := 声部1 ';' 声部2 ...       // 分号分隔多声部（最多 4 个）
```

- 小节之间用 `|` 分隔，`|` 前后可以有任意空格。
- 每个小节内是一串**空格分隔的记号（token）**：音符、休止符、和弦、指令等。
- 分号 `;` 把一个小节拆成多个声部，详见 [§12 多声部](#12-多声部)。
- 任何一处写法不合法都会抛出 `FormatException`，并附带出错 token。

```dart
// 三个小节：4/4 音阶片段
notes: 'c4:q d4 e4 f4 | g4:h a4:h | c5:w'
```

## 2. 音高（pitch）

格式：**音名字母 + 变音记号（可选）+ 八度数字（可省略）**

```text
pitch := [a-gA-G] ('#'|'b'|'n'|'##'|'bb')? 八度数字?
```

| 写法 | 含义 |
| --- | --- |
| `c4` | C4，即中央 C（MIDI 60） |
| `f#3` | 升 F3 |
| `bb3` | 降 B3（字母 `b` 紧跟音名表示降号） |
| `cn4` | 还原 C4，`n` 是**强制显示的还原记号**（`showAccidental`） |
| `c##4` / `dbb4` | 重升 / 重降 |
| `c-1` | 八度可为负数 |

- 字母大小写均可（`C4` ≡ `c4`）。
- **八度是黏滞（sticky）的**：省略八度时沿用同一声部上一个音的八度
  （跨小节线有效），初始为 4。所以 `c4 d e f` ≡ `c4 d4 e4 f4`，
  `c4 d e5 g` ≡ `c4 d4 e5 g5`。和弦成员按书写顺序依次继承
  （`c4+e+g` ≡ `c4+e4+g4`）；休止符不占八度、不改变沿用值；每个声部
  各自独立记忆。
- **调号生效**：不带变音记号的音名继承调号对该音级的升降——3 个降号的
  调里 `b4` 就是 B♭4，照常落在 B 线/间上、不画任何变音记号。显式后缀
  （`#` `b` `n` `##` `bb`）始终覆盖调号，如 E♭ 大调中要写 B 自然音用
  `bn4`。中途 `!key=N` 变调后，其后的音符按新调继承。
- 简谱中 `c4` 即首调 do 所在八度的中音组；八度每 ±1 对应简谱上/下一个
  八度点。例如 `c3` 在简谱中渲染为下方带点的 1，`c5` 为上方带点的 1。

## 3. 时值（duration）

时值是音符 token 的一部分，跟在 `:` 后面，语法为：

```text
duration := ('w'|'h'|'q'|'e'|'s'|'t'|'x'|'b') ('.'|'..')?
```

### 时值字母

| 字母 | 时值 | 简谱表现 |
| --- | --- | --- |
| `w` | 全音符 | 数字 + 3 条增时线 |
| `h` | 二分音符 | 数字 + 1 条增时线 |
| `q` | 四分音符（**默认**） | 一个数字 |
| `e` | 八分音符 | 1 条减时线 |
| `s` | 十六分音符 | 2 条减时线 |
| `t` | 三十二分音符 | 3 条减时线 |
| `x` | 六十四分音符 | — |
| `b` | 倍全音符（breve） | — |

### 附点（写在时值字母后，属于时值的一部分）

| 写法 | 名称 | 实际长度 |
| --- | --- | --- |
| `q.` | 附点四分 | 1 + 1/2 = 1.5 拍 |
| `h.` | 附点二分 | 2 + 1 = 3 拍 |
| `e.` | 附点八分 | 3/4 拍 |
| `q..` | 复附点四分 | 1 + 1/2 + 1/4 = 1.75 拍 |
| `h..` | 复附点二分 | 2 + 1 + 1/2 = 3.5 拍 |

- 附点用英文句点 `.`，最多两个（`.` 附点、`..` 复附点），规则是"每加一个
  点，再延长前面已加部分的一半"。
- 附点必须紧跟时值字母：`c4:q.` 合法；`c4:.q` 会抛 `Invalid duration`。
  附点之后再跟演奏记号没有问题（`c4:q.'` = 附点四分 + 断奏）。
- 附点对音符和休止符都有效（`r:q.` 附点四分休止）。
- 附点随时值一起黏滞：`c4:q. d4` 中 `d4` 也是附点四分。
- 简谱中附点渲染为数字右侧的小圆点，复附点为两个并排小点。

**时值是黏滞（sticky）的**：不写 `:时值` 时沿用上一个 token 的时值（含附点），
初始为四分音符。所以音阶可以简写为：

```dart
notes: 'c4:q d4 e4 f4'   // 四个四分音符
notes: 'c4:e d4 e4 f4'   // 四个八分音符
```

## 4. 休止符

`r` 表示休止符，时值规则与音符相同：

```dart
notes: 'c4:q r:q c4:h'        // 四分 + 四分休止 + 二分
```

简谱中按 GB/T 46845—2025 渲染：四分休止为 `0`，长休止自动展开为多个 `0`。
休止符**不能**带延音线、连音线、演奏记号、倚音或指法，否则报错。

## 5. 和弦

用 `+` 连接多个音高，整组共用一个时值：

```dart
notes: 'c4+e4+g4:h'           // C 大三和弦，二分
notes: 'c4+e4+g4+c5:w'        // 四个音叠置
```

## 6. 延音线与连音线

| 后缀 | 含义 | 示例 |
| --- | --- | --- |
| `~` | 延音线（tie），连到下一个音符，可跨小节 | `'g4:h~ g4:q'` |
| `(` | 在本音符开启连音线（slur） | `'c4:q( d4 e4 f4)'` |
| `)` | 在本音符关闭连音线 | 同上 |

- 连音线可跨小节，也**可嵌套**；每个 `)` 与最近一个未配对的 `(` 配对
  （后进先出），所以 `c4:q(( e4) g4)` 得到两条从 c4 出发的连线
  （c4→e4 与 c4→g4）。`(` 必须与 `)` 数量配对，否则抛
  `Unclosed slur "("`。
- 延音线永远连向**下一个音符元素**。

## 7. 倚音（装饰音）

`{音高,音高}` 前缀给音符加短倚音（acciaccatura）：

```dart
notes: '{g4}a4:q'             // 单倚音
notes: '{f4,g4}a4:q'          // 双倚音
```

## 8. 演奏记号（articulation）与装饰记号（ornament）

写在音符 token 的**末尾**，可叠加：

| 记号 | 含义 |
| --- | --- |
| `'` | 断奏 staccato（简谱中为实心倒三角） |
| `_` | 保持音 tenuto |
| `>` | 重音 accent |
| `^` | 强重音 marcato |
| `@` | 延音记号 fermata |

```dart
notes: r"c4:q' a3_ g3> c4^ | c4+e4:q' d5>' f4:h@"
```

装饰记号（ornament，每音一个，画在上方）：

| 记号 | 含义 |
| --- | --- |
| `%` | 颤音 trill |
| `$` | 短颤音（上波音） |
| `&` | 波音 mordent |
| `?` | 回音 turn |

> 提示：Dart 字符串里写 `$` 要用原始字符串 `r'...'` 或转义 `\$`。

民乐技法记号（technique mark，可叠加，仅简谱渲染；层叠次序：装饰滑音最
贴近数字 → 断音/重音等 → 装饰音 → 其余技法记号）：

| 记号 | 含义 | 渲染形 |
| --- | --- | --- |
| `/` | 上滑音 | ↗ 形曲线（SMuFL brassScoop） |
| `\` | 下滑音 | ↘ 形曲线（SMuFL brassFallLipShort） |
| `H` | 回滑音（回滚音） | 上滑+下滑并排居中 |
| `R` | 揉弦 | 波状线（SMuFL wiggleVibratoWide） |
| `P` | 拨弦 | 文字「拨」 |
| `*` | 花舌 | ※ |
| `L` | 厉音 | ⊥ |
| `V` | 换气 | ∨ |
| `T` | 吐音 | T |

```dart
notes: r'c4:q/ d4:q\ e4:qH g4:qR | c5:qP b4:q* a4:qL g4:qV | e4:qT c4:q/T'
```

## 9. 指法

`=数字` 给单音标指法；和弦用逗号分隔：

```dart
notes: 'c4:q=3'               // 3 指
notes: 'c4+e4+g4:h=1,3,5'     // 和弦 1/3/5 指
notes: 'c4:q=2~'              // 可以和其他后缀共存
```

## 10. 连音（tuplet）

`实际数[...]` 把一组音符括成连音，`实际数:正常数[...]` 显式指定比例：

```dart
notes: '3[c4:e d4 e4]'                // 三连音
notes: '5[g4:s a4 b4 c5 d5]'          // 五连音
notes: '3[c4:e r e4]'                 // 连音里可以有休止符
notes: '2:3[c4:q d4]'                 // 二连音（对 3）
```

- 省略正常数时：二连音默认对 3，其余默认取小于实际数的最大 2 的幂
  （3→2，5/6/7→4）。
- 连音**不能跨小节、不能嵌套**；`[` 必须在小节内用 `]` 关闭。
- 连音只属于第 1 声部。

## 11. 小节指令（`!` 开头）

习惯上写在小节开头，作用于**该小节**：

| 指令 | 作用 | 示例 |
| --- | --- | --- |
| `!repeat` | 开始反复 𝄆 | `'!repeat c4:q ...'` |
| `!endrepeat` | 结束反复 𝄇 | `'... !endrepeat'` |
| `!volta=N` | 第 N 房子（N ≥ 1） | `'!volta=1 a4:h g4:h'` |
| `!key=N` | 变调，N 为升降号数（-7..7，正为升号调） | `'!key=2 d4:q ...'` |
| `!time=N/M` | 变拍 | `'!time=3/4 c4:h q'` |
| `!clef=名` | 换谱号（treble/bass/alto/tenor/treble8va/treble8vb/bass8vb） | `'!clef=bass ...'` |
| `!mrest=N` | 多小节休止（N ≥ 2，该小节不能再写音符） | `'!mrest=4'` |
| `!nav=名` | 跳转记号：segno / coda / toCoda / daCapo / daCapoAlFine / daCapoAlCoda / dalSegno / dalSegnoAlFine / dalSegnoAlCoda / fine | `'!nav=fine'` |
| `!barline=样式` | 该小节右小节线：doubleBar / finalBar / heavy / dashed / dotted / tick / short / none | `'!barline=finalBar'` |

完整反复示例：

```dart
notes: '!repeat c4:q( d4 e4 f4) | g4:h~ g4:q r:q | '
       '!endrepeat !volta=1 a4:h g4:h | !volta=2 c5:h. c4:q'
```

> 简谱默认不画行首调号/拍号标签；中途 `!key` / `!time` 变调变拍仍会显示。

## 12. 多声部

小节内用 `;` 分出声部，最多 4 个：

```dart
notes: 'c5:q d5 ; a4:h ; f4:h'
```

- 奇数声部（1、3）符干朝上，偶数声部（2、4）朝下。
- 小节指令和连音只能写在第 1 声部，否则抛 `Directives and tuplets are voice-1 only`。
- 元素 id 跨声部连续编号（见 §15）。

## 13. 歌词（lyrics 参数）

`lyrics` 是独立参数（不在 notes 里），按阅读顺序逐音节对位到**第 1 声部的
音符**（自动跳过休止符）：

```dart
Score.simple(
  notes: 'c4:q d4 e4 r:q | f4:h',
  lyrics: 'Twin- kle * star_',
);
```

- 空格分隔，一个 token 对一个音符。
- `*` 跳过该音符（不填词）。
- 词尾 `-`：与下一音节用连字符连接（一个单词拆多音）。
- 词尾 `_`：画延长线（melisma，一个音节唱多音）。
- token 多于音符会抛 `More lyric tokens than notes`。

## 14. 标注（annotations 参数）

与歌词同样的对位规则，但文字画在**谱表上方**，常用于和弦标记、速度/段落
文字：

```dart
Score.simple(
  notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
  annotations: 'C Am F G7 C',
);
```

## 15. 元素 id 与起始参数

- 每个音符/休止符按阅读顺序自动获得 id `e0, e1, e2 …`，可直接用于
  点击高亮、播放定位、`DynamicMarking('e0', ...)` 等。
- `Score.simple` 的可选起始参数：
  - `clef`（默认 `Clef.treble`，简谱忽略）
  - `staffType`（`StaffType.standard` / `jianpu` / `tablature` / `percussion`）
  - `keySignature`（如 `KeySignature(1)` 表示 G 大调 / 简谱 1=G）
  - `timeSignature`（如 `TimeSignature.fourFour`；省略则不检查小节时值）
- 在已知拍号下，过短的第一小节会被自动识别为**弱起小节**（pickup，
  不计小节号）。

## 16. 常见错误速查

| 报错 | 原因 |
| --- | --- |
| `Invalid pitch: "..."` | 音高写法不符合 `字母+变音(+八度，可省)` |
| `Invalid duration in token` | 时值字母/附点不合法 |
| `Unknown directive` | `!` 指令名写错 |
| `Tuplets cannot nest` / `Unclosed tuplet "["` | 连音嵌套或未闭合 |
| `Slurs cannot nest` / `Unclosed slur "("` / `")" without an open slur` | 连音线配对错误 |
| `A rest cannot be tied` 等 | 休止符带了不允许的记号 |
| `Directives and tuplets are voice-1 only` | 指令/连音写进了其他声部 |
| `!mrest measures cannot hold notes` | 多小节休止小节里写了音符 |
| `At most four voices per measure` | 声部超过 4 个 |
| `More lyric/annotation tokens than notes` | 歌词/标注数量超过音符数 |

## 17. 完整示例

### 小星星（简谱，G 大调，带歌词与和弦标注）

```dart
Score.simple(
  keySignature: const KeySignature(1),
  timeSignature: TimeSignature.fourFour,
  staffType: StaffType.jianpu,
  notes: 'g4:q g4 a4 a4 | b4:q b4 a4:h | '
         'a4:q a4 g4:q g4 | f#4:q f#4 e4:h | '
         'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w',
  lyrics: 'Twin- kle twin- kle lit- tle star '
          'twin- kle twin- kle star how I won- der what you are',
  annotations: 'G * * * C * G G * C * G * D * Em * C * G',
);
```

### 反复 + 房子 + 三连音 + 演奏记号（五线谱）

```dart
Score.simple(
  timeSignature: TimeSignature.fourFour,
  notes: '!repeat c4:q d4( e4 f4) | 3[g4:e a4 g4] f4:q. e4:e | '
         '!endrepeat !volta=1 e4:h d4:h | !volta=2 d4:h c4:w !barline=finalBar',
);
```
