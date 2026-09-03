import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseScoreDsl', () {
    test('parses metadata fields', () {
      const source = '---score\n'
          'title: 测试\n'
          'description: 描述\n'
          'authors: 作者\n'
          'scale: G\n'
          'timeSignature: 4/4\n'
          'tempo: 120\n'
          'tracks:\n'
          '  - name: 旋律\n'
          '    type: jianpu\n'
          '---\n'
          ':旋律\n'
          'notes: c4:q d4 e4 f4 |';
      final doc = parseScoreDsl(source);
      expect(doc.meta.title, '测试');
      expect(doc.meta.description, '描述');
      expect(doc.meta.authors, '作者');
      expect(doc.meta.scale, 'G');
      expect(doc.meta.timeSignature, '4/4');
      expect(doc.meta.tempo, 120);
      expect(doc.meta.trackDecls.length, 1);
      expect(doc.meta.trackDecls[0].name, '旋律');
      expect(doc.meta.trackDecls[0].type, 'jianpu');
      expect(doc.bodies.length, 1);
      expect(doc.bodies[0].name, '旋律');
      expect(doc.bodies[0].notes.length, 1);
    });

    test('parses flow-style track declarations', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n'
          '  - {name: right, type: standard, clef: treble, group: piano}\n'
          '  - {name: left,  type: standard, clef: bass,   group: piano}\n'
          '---\n'
          ':right\nnotes: c4:q |\n'
          ':left\nnotes: c2:q |';
      final doc = parseScoreDsl(source);
      expect(doc.meta.trackDecls.length, 2);
      expect(doc.meta.trackDecls[0].name, 'right');
      expect(doc.meta.trackDecls[0].clef, 'treble');
      expect(doc.meta.trackDecls[0].group, 'piano');
      expect(doc.meta.trackDecls[1].name, 'left');
      expect(doc.meta.trackDecls[1].clef, 'bass');
    });

    test('parses multi-line notes with continuation', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4 |\n'
          '       e4 f4 |\n'
          'notes: g4:q |';
      final doc = parseScoreDsl(source);
      expect(doc.bodies[0].notes, ['c4:q d4 |', 'e4 f4 |', 'g4:q |']);
    });

    test('parses multi-verse lyrics', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4 |\n'
          'lyrics: 欢 乐\n'
          'lyrics2: 星 光\n'
          'lyrics3: 月 光';
      final doc = parseScoreDsl(source);
      expect(doc.bodies[0].lyrics[1], '欢 乐');
      expect(doc.bodies[0].lyrics[2], '星 光');
      expect(doc.bodies[0].lyrics[3], '月 光');
    });

    test('skips comments and blank lines', () {
      const source = '# comment\n\n'
          '---score\n'
          'title: T\n'
          '# comment in meta\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          '# comment in body\n'
          ':a\n'
          'notes: c4:q |';
      final doc = parseScoreDsl(source);
      expect(doc.meta.title, 'T');
      expect(doc.bodies[0].notes, ['c4:q |']);
    });

    test('throws if file does not start with ---score', () {
      expect(
        () => parseScoreDsl('title: nope'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing closing ---', () {
      expect(
        () => parseScoreDsl('---score\ntitle: T\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown metadata fields are silently ignored', () {
      final r = loadScoreDsl('---score\ntitle: T\nunknwon: x\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |');
      expect(r.system.staves.length, 1);
      expect(r.metadata.title, 'T');
    });

    test('parses renderer-level hints: highlight, practice, instrument', () {
      final r = loadScoreDsl('---score\ntitle: T\n'
          'highlight: 0 2 4\n'
          'practice: true\n'
          'instrument: 木吉他\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q d4 e4 f4 |');
      expect(r.highlightIndices, [0, 2, 4]);
      expect(r.practice, isTrue);
      expect(r.instrument, '木吉他');
    });
  });

  group('_parseScale', () {
    test('major keys', () {
      final src = '---score\ntitle: T\nscale: C\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      final r = loadScoreDsl(src);
      expect(r.keySignature.fifths, 0);

      final rG = loadScoreDsl(src.replaceAll('scale: C', 'scale: G'));
      expect(rG.keySignature.fifths, 1);

      final rBb = loadScoreDsl(src.replaceAll('scale: C', 'scale: Bb'));
      expect(rBb.keySignature.fifths, -2);
    });

    test('case-insensitive normalization', () {
      final src = '---score\ntitle: T\nscale: bb\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      final r = loadScoreDsl(src);
      expect(r.keySignature.fifths, -2);

      final rFs = loadScoreDsl(src.replaceAll('scale: bb', 'scale: f#'));
      expect(rFs.keySignature.fifths, 6);
    });

    test('minor keys map to relative major', () {
      final src = '---score\ntitle: T\nscale: Am\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      final r = loadScoreDsl(src);
      expect(r.keySignature.fifths, 0);

      final rEm = loadScoreDsl(src.replaceAll('scale: Am', 'scale: Em'));
      expect(rEm.keySignature.fifths, 1);
    });

    test('rejects standalone lowercase b', () {
      final src = '---score\ntitle: T\nscale: b\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      expect(() => loadScoreDsl(src), throwsA(isA<FormatException>()));
    });
  });

  group('compileScoreDsl — scenario 1 (jianpu solo)', () {
    test('builds one jianpu Score', () {
      const source = '---score\n'
          'title: 小星星\n'
          'scale: C\n'
          'timeSignature: 4/4\n'
          'tempo: 96\n'
          'tracks:\n  - name: 旋律\n    type: jianpu\n'
          '---\n'
          ':旋律\n'
          'notes: c4:q c4 g4 g4 | a4:q a4 g4:h';
      final r = loadScoreDsl(source);
      expect(r.system.staves.length, 1);
      expect(r.system.staves[0].staffType, StaffType.jianpu);
      expect(r.system.staves[0].measures.length, 2);
      expect(r.metadata.title, '小星星');
      expect(r.tempo!.bpm, 96);
    });
  });

  group('compileScoreDsl — scenario 2 (jianpu + lyrics)', () {
    test('builds jianpu Score with one verse', () {
      const source = '---score\n'
          'title: 欢乐颂\n'
          'authors: 贝多芬\n'
          'scale: Bb\n'
          'timeSignature: 4/4\n'
          'tempo: 80\n'
          'tracks:\n  - name: 合唱\n    type: jianpu\n'
          '---\n'
          ':合唱\n'
          'notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |\n'
          'lyrics: 欢 乐 女 神';
      final r = loadScoreDsl(source);
      expect(r.system.staves.length, 1);
      expect(r.system.staves[0].staffType, StaffType.jianpu);
      expect(r.keySignature.fifths, -2);
      expect(r.metadata.composer, '贝多芬');
      final verse1 = r.system.staves[0].lyrics.where((l) => l.verse == 1);
      expect(verse1.length, 4);
    });

    test('builds jianpu Score with two verses', () {
      const source = '---score\n'
          'title: 欢乐颂\n'
          'scale: Bb\n'
          'timeSignature: 4/4\n'
          'tempo: 80\n'
          'tracks:\n  - name: 合唱\n    type: jianpu\n'
          '---\n'
          ':合唱\n'
          'notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |\n'
          'lyrics: 欢 乐 女 神\n'
          'lyrics2: 灿 烂 星 光';
      final r = loadScoreDsl(source);
      final verse1 = r.system.staves[0].lyrics.where((l) => l.verse == 1);
      final verse2 = r.system.staves[0].lyrics.where((l) => l.verse == 2);
      expect(verse1.length, 4);
      expect(verse2.length, 4);
    });
  });

  group('compileScoreDsl — scenario 3 (piano solo)', () {
    test('builds two-staff StaffSystem with brace and barline group', () {
      const source = '---score\n'
          'title: 钢琴独奏\n'
          'authors: 集体\n'
          'scale: G\n'
          'timeSignature: 4/4\n'
          'tempo: 110\n'
          'tracks:\n'
          '  - name: right\n'
          '    type: standard\n'
          '    clef: treble\n'
          '    group: piano\n'
          '  - name: left\n'
          '    type: standard\n'
          '    clef: bass\n'
          '    group: piano\n'
          '---\n'
          ':right\nnotes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |\n'
          ':left\nnotes: c2:q c2:q c2:q c2:q | c2:q c2:q c2:q c2:q |';
      final r = loadScoreDsl(source);
      expect(r.system.staves.length, 2);
      expect(r.system.staves[0].clef, Clef.treble);
      expect(r.system.staves[1].clef, Clef.bass);
      expect(r.system.brackets.length, 1);
      expect(r.system.brackets[0].first, 0);
      expect(r.system.brackets[0].last, 1);
      expect(r.system.brackets[0].kind, StaffBracketKind.brace);
      expect(r.system.barlineGroups.length, 1);
      expect(r.system.barlineGroups[0].first, 0);
      expect(r.system.barlineGroups[0].last, 1);
    });
  });

  group('compileScoreDsl — scenario 4 (piano + jianpu + lyrics)', () {
    test('builds three-staff system: jianpu + grand staff', () {
      const source = '---score\n'
          'title: 我的祖国\n'
          'scale: G\n'
          'timeSignature: 4/4\n'
          'tempo: 110\n'
          'tracks:\n'
          '  - name: 独唱\n'
          '    type: jianpu\n'
          '  - name: right\n'
          '    type: standard\n'
          '    clef: treble\n'
          '    group: piano\n'
          '  - name: left\n'
          '    type: standard\n'
          '    clef: bass\n'
          '    group: piano\n'
          '---\n'
          ':独唱\n'
          'notes: e4:q e4 f4 g4 | g4:q f4 e4 d4 |\n'
          'lyrics: 一 条 大 河\n'
          'lyrics2: 我 家 就 在\n'
          ':right\n'
          'notes: c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q | c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q c4+e4+g4:q |\n'
          ':left\n'
          'notes: c2:q c2:q c2:q c2:q | c2:q c2:q c2:q c2:q |';
      final r = loadScoreDsl(source);
      expect(r.system.staves.length, 3);
      expect(r.system.staves[0].staffType, StaffType.jianpu);
      expect(r.system.staves[1].staffType, StaffType.standard);
      expect(r.system.staves[2].staffType, StaffType.standard);
      expect(r.system.staves[1].clef, Clef.treble);
      expect(r.system.staves[2].clef, Clef.bass);

      // Brace only over the piano group (staves 1-2).
      expect(r.system.brackets.length, 1);
      expect(r.system.brackets[0].first, 1);
      expect(r.system.brackets[0].last, 2);

      // Barline group only over the piano group (staves 1-2).
      expect(r.system.barlineGroups.length, 1);
      expect(r.system.barlineGroups[0].first, 1);
      expect(r.system.barlineGroups[0].last, 2);

      // Multi-verse lyrics on the jianpu staff.
      final v1 = r.system.staves[0].lyrics.where((l) => l.verse == 1);
      final v2 = r.system.staves[0].lyrics.where((l) => l.verse == 2);
      expect(v1.length, 4);
      expect(v2.length, 4);
    });
  });

  group('compileScoreDsl — error cases', () {
    test('throws on missing track body', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n  - name: b\n    type: jianpu\n'
          '---\n'
          ':a\nnotes: c4:q |';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });

    test('throws on missing notes field', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\nlyrics: 欢 乐';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });

    test('throws on measure count mismatch', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n'
          '  - name: a\n    type: jianpu\n'
          '  - name: b\n    type: jianpu\n'
          '---\n'
          ':a\nnotes: c4:q d4 | e4:q f4 |\n'
          ':b\nnotes: c4:q d4 |';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });

    test('throws on unknown track type', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: nonsense\n'
          '---\n:a\nnotes: c4:q |';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });

    test('throws on invalid timeSignature', () {
      const source = '---score\n'
          'title: T\ntimeSignature: 4:4\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });

    test('throws on tablature (not yet implemented)', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: tablature\n'
          '---\n:a\nnotes: c4:q |';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });
  });

  group('layout attribute', () {
    test('defaults to page', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      final r = loadScoreDsl(source);
      expect(r.layout, 'page');
      expect(r.system.staves.length, 1);
    });

    test('parses layout: single', () {
      const source = '---score\n'
          'title: T\n'
          'layout: single\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      final doc = parseScoreDsl(source);
      expect(doc.meta.layout, 'single');
      expect(loadScoreDsl(source).layout, 'single');
    });

    test('parses layout: page explicitly', () {
      const source = '---score\n'
          'title: T\n'
          'layout: page\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      expect(parseScoreDsl(source).meta.layout, 'page');
    });

    test('throws on invalid layout', () {
      const source = '---score\n'
          'title: T\n'
          'layout: grid\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n:a\nnotes: c4:q |';
      expect(() => parseScoreDsl(source), throwsA(isA<FormatException>()));
    });
  });

  group('lyrics skip tied notes', () {
    test('tie continuation consumes no token (cross-measure)', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4~ | d4:q e4 |\n'
          'lyrics: 一 二 三';
      final r = loadScoreDsl(source);
      final lyrics = r.system.staves[0].lyrics;
      // d4~ is e1, its tied continuation d4 is e2 (skipped), e4 is e3.
      expect(lyrics.map((l) => l.text), ['一', '二', '三']);
      expect(lyrics.map((l) => l.elementId), ['e0', 'e1', 'e3']);
    });

    test('same-pitch slur end consumes no token', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4( | d4:q) e4 |\n'
          'lyrics: 一 二 三';
      final r = loadScoreDsl(source);
      final lyrics = r.system.staves[0].lyrics;
      expect(lyrics.map((l) => l.text), ['一', '二', '三']);
      expect(lyrics.map((l) => l.elementId), ['e0', 'e1', 'e3']);
    });

    test('different-pitch slur keeps every note', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4( e4) f4 |\n'
          'lyrics: 一 二 三 四';
      final r = loadScoreDsl(source);
      final lyrics = r.system.staves[0].lyrics;
      expect(lyrics.map((l) => l.elementId), ['e0', 'e1', 'e2', 'e3']);
    });

    test('rests still consume no token', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q r d4 e4 |\n'
          'lyrics: 一 二 三';
      final r = loadScoreDsl(source);
      expect(r.system.staves[0].lyrics.map((l) => l.elementId),
          ['e0', 'e2', 'e3']);
    });

    test('excess tokens still throw after skipping', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4~ | d4:q |\n'
          'lyrics: 一 二 三';
      expect(() => loadScoreDsl(source), throwsA(isA<FormatException>()));
    });
  });

  group('multi-line and interleaved fields', () {
    test('lyrics continuation lines merge', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4 |\n'
          '       e4 f4 |\n'
          'lyrics: 一 二\n'
          '        三 四';
      final r = loadScoreDsl(source);
      expect(r.system.staves[0].measures.length, 2);
      final v1 = r.system.staves[0].lyrics;
      expect(v1.map((l) => l.text), ['一', '二', '三', '四']);
      expect(v1.map((l) => l.elementId), ['e0', 'e1', 'e2', 'e3']);
    });

    test('interleaved notes/lyrics segments align in order', () {
      const source = '---score\n'
          'title: T\n'
          'tracks:\n  - name: a\n    type: jianpu\n'
          '---\n'
          ':a\n'
          'notes: c4:q d4 |\n'
          'lyrics: 一 二\n'
          'lyrics2: 甲 乙\n'
          'notes: e4:q f4 |\n'
          'lyrics: 三 四\n'
          'lyrics2: 丙 丁';
      final r = loadScoreDsl(source);
      final staff = r.system.staves[0];
      expect(staff.measures.length, 2);
      final v1 = staff.lyrics.where((l) => l.verse == 1).toList();
      final v2 = staff.lyrics.where((l) => l.verse == 2).toList();
      expect(v1.map((l) => l.text), ['一', '二', '三', '四']);
      expect(v1.map((l) => l.elementId), ['e0', 'e1', 'e2', 'e3']);
      expect(v2.map((l) => l.text), ['甲', '乙', '丙', '丁']);
      expect(v2.map((l) => l.elementId), ['e0', 'e1', 'e2', 'e3']);
    });

    test('full scenario: repeated melody, two verses, same-pitch ties', () {
      const seg = 'r:q r r e4:e g4 | a4:q. r:e c5:e b4 a4 g4( | '
          'g4:e) a4:s g4 e4:q. r:e e4 g4 | a4:q. r:e g4 a4 c5 d5 | e5:w';
      const source = '---score\n'
          'title: 简谱符号渲染测试用例\n'
          'tempo: 120\n'
          'timeSignature: 4/4\n'
          'tracks:\n  - name: 简谱\n    type: jianpu\n'
          '---\n'
          ':简谱\n'
          'notes: $seg\n'
          'lyrics: 如 果 说 这 是 我 们 的 秘 密 那 么 我 不 会 保 护 它\n'
          'lyrics2: 如 果 说 这 是 我 们 的 秘 密 那 么 我 不 会 忘 记 它\n'
          'notes: $seg\n'
          'lyrics: 如 果 说 这 是 我 们 的 秘 密 那 么 我 不 会 原 谅 它\n'
          'lyrics2: 如 果 说 这 是 我 们 的 秘 密 那 么 我 不 会 失 去 它\n';
      final r = loadScoreDsl(source);
      final staff = r.system.staves[0];
      expect(staff.measures.length, 10);
      final v1 = staff.lyrics.where((l) => l.verse == 1).toList();
      final v2 = staff.lyrics.where((l) => l.verse == 2).toList();
      // 19 note elements per segment, minus the tied g4 continuation = 18.
      expect(v1.length, 36);
      expect(v2.length, 36);
      // The tied-to g4 of each segment (e11, e36) carries no syllable.
      expect(staff.lyrics.any((l) => l.elementId == 'e11'), isFalse);
      expect(staff.lyrics.any((l) => l.elementId == 'e36'), isFalse);
      // Segment 2's first syllable lands on its first note (e28).
      expect(v1[18].text, '如');
      expect(v1[18].elementId, 'e28');
    });
  });
}
