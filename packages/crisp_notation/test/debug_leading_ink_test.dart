import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  testWidgets('dump leading ink', (tester) async {
    final score =
        Score.simple(notes: 'c4:q d4 e4 f4', staffType: StaffType.jianpu);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            child: ColoredBox(
                color: Colors.white,
                child: StaffView(score: score, staffSpace: 12)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final render =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).last);
    late ui.Image image;
    late ByteData data;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    final base = tester.getTopLeft(find.byType(StaffView)) -
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    bool dark(int x, int y) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
        return false;
      }
      final i = (y * image.width + x) * 4;
      return data.getUint8(i) < 100 &&
          data.getUint8(i + 1) < 100 &&
          data.getUint8(i + 2) < 100;
    }

    for (final ySpaces in [1.3, 2.5, 3.2]) {
      final row = base + render.staffToLocal(math.Point(0.0, ySpaces));
      final darkXs = <int>[];
      for (var x = row.dx.round(); x <= row.dx.round() + 40; x++) {
        if (dark(x, row.dy.round())) darkXs.add(x - row.dx.round());
      }
      debugPrint('y=$ySpaces localRow=${row.dy} darkXOffsets=$darkXs');
    }
    // 纵剖面：x=1px 处所有暗像素的 y。
    final col = base + render.staffToLocal(math.Point(0.08, 0));
    final darkYs = <int>[];
    for (var y = 0; y < image.height; y++) {
      if (dark(col.dx.round(), y)) darkYs.add(y);
    }
    debugPrint('x≈0.08ss darkYs=$darkYs');
  });
}
