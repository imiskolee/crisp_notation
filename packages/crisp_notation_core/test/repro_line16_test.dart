import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  test('repro: user verbatim text', () {
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
    final r = loadScoreDsl(source);
    expect(r.system.staves.length, 2);
    expect(r.system.staves[0].measures.length, 5);
    expect(r.system.staves[1].measures.length, 5);
  });
}
