import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

const source = '---score\n'
    'title: 简谱符号渲染测试用例\n'
    'description:\n'
    'authors: 系统\n'
    'tempo: 120\n'
    'timeSignature: 4/4\n'
    'tracks:\n'
    '  - name: 钢琴\n'
    '    type: standard\n'
    '    clef: treble\n'
    '  - name: 简谱\n'
    '    type: jianpu\n'
    '---\n'
    '\n'
    ':钢琴\n'
    'notes: c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q |  c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q |  c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q |   c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q c4+g4+c5:q | e5:w\n'
    '\n'
    ':简谱\n'
    'notes: r:q r r e4:e g4 | a4:q. r:e c5:e b4 a4 g4( | g4:e) a4:s g4 e4:q. r:e e4 g4 | a4:q. r:e g4 a4 c5 d5 | e5:w\n'
    'lyrics:  如 果 说 这 是 我 们  的 秘 密 那 么 我 不 会 保 护 它\n'
    'lyrics2: 如 果 说 这 是 我 们 的 秘 密 那 么 我 不 会 忘 记 它\n';

void main() {
  final r = loadScoreDsl(source);
  final metaJson = File('../crisp_notation/assets/smufl/bravura_metadata.json')
      .readAsStringSync();
  final settings = LayoutSettings(
      metadata:
          SmuflMetadata.fromJson(jsonDecode(metaJson) as Map<String, Object?>));
  for (final maxWidth in [140.0, 80.0, 50.0]) {
    print('##### maxWidth=$maxWidth');
    final wrapped = layoutStaffSystemSystems(
      r.system,
      settings,
      maxWidth: maxWidth,
      staffGap: 6,
    );
    var aligned = true;
    for (var si = 0; si < wrapped.systems.length; si++) {
      final sys = wrapped.systems[si];
      print('=== system $si: measures ${sys.firstMeasure}..${sys.lastMeasure} '
          'width=${sys.layout.width.toStringAsFixed(2)}');
      List<String>? ref;
      for (var st = 0; st < sys.layout.staves.length; st++) {
        final staff = sys.layout.staves[st];
        final type = sys.layout.source.staves[st].staffType;
        final regions = [
          for (final mr in staff.measureRegions)
            '[${mr.startX.toStringAsFixed(2)}..${mr.endX.toStringAsFixed(2)}]'
        ];
        print('  staff $st ($type): ${regions.join(' ')}');
        if (ref == null) {
          ref = regions;
        } else if (!_sameRegions(ref, regions)) {
          aligned = false;
          print('  !! MISALIGNED');
        }
      }
    }
    print(aligned ? 'ALIGNED ✓' : 'MISALIGNED ✗');
  }
}

bool _sameRegions(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
