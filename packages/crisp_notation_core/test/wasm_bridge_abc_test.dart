import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../example/wasm/score_bridge_convert.dart';

void main() {
  final metadata = File('../crisp_notation/assets/smufl/bravura_metadata.json')
      .readAsStringSync();

  test('renders ABC decorations through the bridge', () {
    final svg = abcToSvg(
      'X:1\nT:Techniques\nM:4/4\nL:1/4\nK:C\n!accent!C !trill!D .E F|',
      metadata,
      'standard',
    );

    expect(svg, startsWith('<?xml'));
    expect(svg, contains(''));
    expect(svg, contains(''));
    expect(svg.trimRight(), endsWith('</svg>'));
  });

  test('parses ABC into the Studio interchange payload', () {
    final payload = jsonDecode(abcToStudioNotes(
      'X:1\nT:Round trip\nM:4/4\nL:1/4\nQ:1/4=120\nK:C\nC D E F|',
    )) as Map<String, dynamic>;

    expect(payload['title'], 'Round trip');
    expect(payload['timeSignature'], '4/4');
    expect((payload['notes'] as List), hasLength(4));
  });

  test('preserves all MIDI pitches for an ABC chord', () {
    final payload = jsonDecode(abcToStudioNotes(
      'X:1\nT:Chord\nM:4/4\nL:1/4\nK:C\n[CEG]|',
    )) as Map<String, dynamic>;

    final notes = payload['notes'] as List<dynamic>;
    expect(notes, hasLength(1));
    expect(notes.single['pitches'], [60, 64, 67]);
  });

  test('paged first-label lines give later unlabelled lines the full width',
      () {
    final svg = abcToSvg(
      'X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1 nm=Vocal\nV:2 name=Guitar\n'
          '[V:1] C D E F|G A B c|d e f g|a b c d|e f g a|b c d e|f g a b|c d e f|\n'
          '[V:2] C, D, E, F,|G, A, B, C|D E F G|A B c d|e f g a|b c d e|f g a b|c d e f|\n',
      metadata,
      'standard',
      jsonEncode({
        'pageSize': 'A4',
        'pageWidthPx': 420,
        'pageHeightPx': 900,
        'paddingPx': 20,
        'instrumentLabels': 'first',
      }),
    );

    final staffLines = RegExp(r'<line x1="0" y1="([^"]+)" x2="([^"]+)"')
        .allMatches(svg)
        .map((match) => double.parse(match.group(2)!))
        .where((x) => x > 0)
        .toList();
    expect(svg, isNot(startsWith('error:')));
    expect(svg, contains('>Vocal<'));
    expect(svg, contains('>Guitar<'));
    expect(staffLines, hasLength(greaterThanOrEqualTo(20)));
    expect(staffLines.take(10), everyElement(closeTo(40.667, 0.05)));
    expect(staffLines.skip(10).take(10), everyElement(closeTo(50.667, 0.05)));
  });

  for (final paged in [false, true]) {
    test('bridge justifies non-final systems with paged=$paged', () {
      final svg = abcToSvg(
        'X:1\nM:4/4\nL:1/4\nK:C\n'
            'V:1 nm=Upper\nV:2 nm=Lower clef=bass\n'
            '[V:1] C D E F|G A B c|C4|\n'
            '[V:2] C, D, E, F,|G, A, B, C|C,4|\n',
        metadata,
        'standard',
        jsonEncode({
          'maxWidth': 40,
          'staffSpace': 10,
          if (paged) 'pageSize': 'A4',
          if (paged) 'pageWidthPx': 540,
          if (paged) 'pageHeightPx': 900,
          if (paged) 'paddingPx': 20,
        }),
      );
      expect(svg, isNot(startsWith('error:')));
      final staffLines = RegExp(r'<line x1="0" y1="([^"]+)" x2="([^"]+)"')
          .allMatches(svg)
          .map((match) => double.parse(match.group(2)!))
          .where((width) => width > 0)
          .toList();
      expect(staffLines.length, greaterThanOrEqualTo(20));
      for (final width in staffLines.take(staffLines.length - 10)) {
        expect(width, closeTo(40, 0.05));
      }
      for (final width in staffLines.skip(staffLines.length - 10)) {
        expect(width, lessThan(40));
      }
    });
  }

  test('Wasm bridge exposes only ABC conversion APIs', () {
    final entrypoint =
        File('example/wasm/score_bridge.dart').readAsStringSync();
    final conversion =
        File('example/wasm/score_bridge_convert.dart').readAsStringSync();

    expect(entrypoint, isNot(contains('fortState')));
    expect(conversion, isNot(contains('fortState')));
    expect(conversion, isNot(contains('Score.simple')));
    expect(entrypoint, contains('abcToSvg'));
    expect(entrypoint, contains('abcToStudioNotes'));
  });

  test('Wasm bridge has no separate single-score layout path', () {
    final conversion =
        File('example/wasm/score_bridge_convert.dart').readAsStringSync();

    expect(conversion, isNot(contains('_renderScoreToSvg')));
    expect(conversion, isNot(contains('_layoutScoreWithEngine')));
    expect(conversion, isNot(contains('layoutSystems(')));
  });

  test('single-voice wrapped ABC uses the staff-system renderer', () {
    final svg = abcToSvg(
      'X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1 nm="Guitar"\n'
          '[V:1] C D E F|G A B c|',
      metadata,
      'standard',
      jsonEncode({
        'layout': 'wrapped',
        'maxWidth': 40,
      }),
    );

    expect(svg, isNot(startsWith('error:')));
    expect(svg, contains('>Guitar<'));
    expect(svg.trimRight(), endsWith('</svg>'));
  });

  test('multi-voice ABC renders every voice as a labelled staff', () {
    final svg = abcToSvg(
      'X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1 nm="Vocal"\nV:2 name=Guitar clef=bass\n'
          '[V:1] C D E F\n[V:2] C, D, E, F,\n',
      metadata,
      'standard',
    );

    expect(svg, isNot(startsWith('error:')));
    expect(svg, contains('>Vocal<'));
    expect(svg, contains('>Guitar<'));
    expect(svg.trimRight(), endsWith('</svg>'));
  });
}
