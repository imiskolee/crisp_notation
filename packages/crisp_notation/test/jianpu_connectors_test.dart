//
// 简谱连谱符号（GB/T 46845-2025 §5.3）的像素级验证。简谱纵线只收小节
// 末尾：行首不画连谱线，小节线不跨行连接 —— 行间隙在行首与各小节线
// x 处都不允许出现墨迹；连谱号（§5.3.2 花连谱号、§5.3.3 直连谱号）
// 作为分组记号仍然绘制。

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

Score _jp(String notes) =>
    Score.simple(notes: notes, staffType: StaffType.jianpu);

Widget _scene(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            child: ColoredBox(color: Colors.white, child: child),
          ),
        ),
      ),
    );

Future<(ui.Image, ByteData)> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).last,
  );
  late ui.Image image;
  late ByteData data;
  await tester.runAsync(() async {
    image = await boundary.toImage();
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return (image, data);
}

bool _isDark(ui.Image image, ByteData data, int x, int y) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;
  final i = (y * image.width + x) * 4;
  return data.getUint8(i) < 100 &&
      data.getUint8(i + 1) < 100 &&
      data.getUint8(i + 2) < 100;
}

/// Dark-pixel count in the ±[radius] window around (x, y).
int _darkNear(ui.Image image, ByteData data, double x, double y,
    {int radius = 2}) {
  var count = 0;
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      if (_isDark(image, data, x.round() + dx, y.round() + dy)) count++;
    }
  }
  return count;
}

void main() {
  setUpAll(setUpCrispNotationForTests);

  testWidgets('简谱大谱表: 行首无连谱线, 花连谱号保留, 小节线不跨行', (tester) async {
    await tester.pumpWidget(_scene(GrandStaffView(
      grandStaff: GrandStaff(
        upper: _jp('c4:q d4 e4 f4 | g4:h'),
        lower: _jp('e4:q f4 g4 a4 | b4:h'),
      ),
      staffSpace: 12,
    )));
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final layout = render.grandLayout!;
    final (image, data) = await _capture(tester);
    final base = tester.getTopLeft(find.byType(GrandStaffView)) -
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    final scale = render.scale;

    final upperBottom = base.dy + render.upperOrigin.dy + 4 * scale;
    final lowerTop = base.dy + render.lowerOrigin.dy;
    final gapY = (upperBottom + lowerTop) / 2;

    // 行首不画连谱线：间隙中、行首 x ≈ 0 处无墨迹。
    final startPx = base.dx + render.upperOrigin.dx;
    expect(_darkNear(image, data, startPx + 1, gapY), 0,
        reason: '简谱行首不画连谱线（间隙中无墨迹）');

    // 小节线不跨行：间隙中、小节线 x 处不得有墨迹。
    final barX = layout.upper.measureRegions.first.endX;
    final barPx = base.dx + render.upperOrigin.dx + barX * scale;
    expect(_darkNear(image, data, barPx, gapY), 0,
        reason: '简谱小节线不跨行连接（间隙中无墨迹）');

    // §5.3.2: 花连谱号保留 —— 跨距中点（大括号尖角处）向左伸出。
    final midY = (base.dy +
            render.upperOrigin.dy +
            JianpuLayoutEngine.digitTop * scale +
            base.dy +
            render.lowerOrigin.dy +
            JianpuLayoutEngine.digitBaseline * scale) /
        2;
    final staffLeftPx = base.dx + render.upperOrigin.dx;
    final braceLeftPx =
        staffLeftPx - RenderGrandStaffView.braceInset * scale;
    var braceInk = 0;
    for (var y = (midY - 3).round(); y <= midY.round() + 3; y++) {
      for (var x = braceLeftPx.round(); x < staffLeftPx.round() - 2; x++) {
        if (_isDark(image, data, x, y)) braceInk++;
      }
    }
    expect(braceInk, greaterThan(0), reason: '花连谱号应在行首左侧出现');
  });

  testWidgets('混合谱表（五线谱+简谱）不画任何跨行符号', (tester) async {
    await tester.pumpWidget(_scene(GrandStaffView(
      grandStaff: GrandStaff(
        upper: Score.simple(notes: 'g4:w | g4:w'),
        lower: _jp('g3:w | g3:w'),
      ),
      staffSpace: 12,
    )));
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final (image, data) = await _capture(tester);
    final base = tester.getTopLeft(find.byType(GrandStaffView)) -
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    final scale = render.scale;
    final upperBottom = base.dy + render.upperOrigin.dy + 4 * scale;
    final lowerTop = base.dy + render.lowerOrigin.dy;

    // 连接符号若未被跳过，会出现在行首 x = 0 与各小节线 x 处。逐点取样
    // 这些位置上的间隙带，必须全部无墨迹（谱号尾部等字形墨迹不在这些
    // x 上）。
    final layout = render.grandLayout!;
    final probeXs = <double>[
      0.0,
      for (final r in layout.upper.measureRegions) r.endX,
    ];
    final gapMidY = (upperBottom + lowerTop) / 2;
    for (final xSpaces in probeXs) {
      final px = base.dx + render.upperOrigin.dx + xSpaces * scale;
      var ink = 0;
      for (var y = upperBottom.round() + 2; y < lowerTop.round() - 1; y++) {
        if (_isDark(image, data, px.round(), y)) ink++;
      }
      expect(ink, 0,
          reason: '混合谱表在 x=$xSpaces 处的行间不得有连接符号墨迹');
    }
    expect(gapMidY, greaterThan(upperBottom)); // sanity: 间隙确实存在
  });

  testWidgets('直连谱号: 粗纵线 + 斜括短半弧, 行首无连谱线', (tester) async {
    await tester.pumpWidget(_scene(StaffSystemView(
      system: StaffSystem(
        [
          _jp('c4:q d4 e4 f4 | c4:h'),
          _jp('e4:q f4 g4 a4 | e4:h'),
          _jp('g4:q a4 b4 c5 | g4:h'),
        ],
        brackets: const [StaffBracket(0, 2, kind: StaffBracketKind.bracket)],
      ),
      staffSpace: 12,
    )));
    final render =
        tester.renderObject<RenderStaffSystemView>(find.byType(StaffSystemView));
    final (image, data) = await _capture(tester);
    final base = tester.getTopLeft(find.byType(StaffSystemView)) -
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    const scale = 12.0;

    // 行首不画连谱线：第 1、2 行间隙中、行首 x ≈ 0 处无墨迹。
    final gapY = (base.dy +
            render.staffOrigin(0).dy +
            4 * scale +
            base.dy +
            render.staffOrigin(1).dy) /
        2;
    final startPx = base.dx + render.staffOrigin(0).dx + 1;
    expect(_darkNear(image, data, startPx, gapY), 0,
        reason: '简谱组的行首不画连谱线（间隙中无墨迹）');

    // §5.3.3: 直连谱号是一条粗纵线 —— 行首左侧、跨距中点处有墨迹。
    final bx = base.dx + render.staffOrigin(0).dx - 0.5 * scale;
    final top = base.dy +
        render.staffOrigin(0).dy +
        JianpuLayoutEngine.digitTop * scale; // 首行数字墨盒顶
    final bottom = base.dy +
        render.staffOrigin(2).dy +
        JianpuLayoutEngine.digitBaseline * scale;
    final midY = (top + bottom) / 2;
    expect(_darkNear(image, data, bx, midY), greaterThan(0),
        reason: '直连谱号的粗纵线应在行首左侧');

    // 两端斜括向内的短半弧：上端括线尖端（粗线右下方）有墨迹。
    expect(
        _darkNear(image, data, bx + 0.34 * scale, top + 0.14 * scale,
            radius: 3),
        greaterThan(0),
        reason: '直连谱号上端应有斜括短半弧');
    expect(
        _darkNear(image, data, bx + 0.34 * scale, bottom - 0.14 * scale,
            radius: 3),
        greaterThan(0),
        reason: '直连谱号下端应有斜括短半弧');
  });

  testWidgets('单行简谱行首不画纵线', (tester) async {
    await tester.pumpWidget(_scene(StaffView(
      score: _jp('c4:q d4 e4 f4'),
      staffSpace: 12,
      // 测试环境默认 Ahem 字体把每个字符画成 1em 宽方块，数字墨迹会越过
      // 行首扫描带；换 Roboto 让数字按真实宽度渲染。
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
    )));
    final render =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final (image, data) = await _capture(tester);
    final base = tester.getTopLeft(find.byType(StaffView)) -
        tester.getTopLeft(find.byType(RepaintBoundary).last);

    // 行首最左 0.25 ss 的竖带上、数字行高度（含小节线扩展纵程）扫描，无墨迹。
    for (final ySpaces in [1.3, 2.5, 3.2]) {
      final row = base + render.staffToLocal(math.Point(0.0, ySpaces));
      final bandEnd = base + render.staffToLocal(math.Point(0.25, ySpaces));
      var ink = 0;
      for (var x = row.dx.round(); x <= bandEnd.dx.round(); x++) {
        if (_isDark(image, data, x, row.dy.round())) ink++;
      }
      expect(ink, 0, reason: '单行简谱行首（y=$ySpaces）不应有纵线墨迹');
    }
  });
}
