import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import '../example/wasm/score_bridge_convert.dart';

void main() {
  final metadata = File('../crisp_notation/assets/smufl/bravura_metadata.json')
      .readAsStringSync();

  test('core layout settings still default to optical', () {
    final parsed = SmuflMetadata.fromJson(
        Map<String, Object?>.from(jsonDecode(metadata) as Map));
    expect(
        LayoutSettings(metadata: parsed).spacingPolicy, SpacingPolicy.optical);
  });

  for (final multiVoice in [false, true]) {
    for (final mode in ['singleLine', 'wrapped', 'paged']) {
      test('bridge spacing policy $mode multiVoice=$multiVoice', () {
        final voices = multiVoice
            ? 'V:1 st=tablature\nV:2 st=jianpu\n[V:1] e4 e4|\n[V:2] '
            : '';
        final abc = 'X:1\nM:4/4\nL:1/8\nK:C\n${voices}z2 z z z2 z2|';
        final options = <String, Object>{
          'layout': mode == 'singleLine' ? mode : 'wrapped',
          'maxWidth': 100,
          'showTitle': false,
          'instrumentLabels': 'none',
          if (mode == 'paged') 'pageSize': 'A4',
        };
        String render(Map<String, Object> overrides) => abcToSvg(
            abc,
            metadata,
            multiVoice ? 'standard' : 'jianpu',
            jsonEncode({...options, ...overrides}));
        final optical = render({'spacingPolicy': 'optical'});
        final equalBeat = render({'spacingPolicy': 'equalBeat'});
        expect(optical, isNot(startsWith('error:')));
        expect(equalBeat, isNot(startsWith('error:')));
        expect(render({}), optical);
        expect(render({'spacingPolicy': 'unknown'}), optical);
        expect(equalBeat, isNot(optical));
        final xs = RegExp(r'<text x="([^"]+)"[^>]*>0</text>')
            .allMatches(equalBeat)
            .map((match) => double.parse(match.group(1)!))
            .toList();
        expect(xs, hasLength(5));
        final beatWidth = xs[3] - xs[1];
        for (var i = 0; i < xs.length; i++) {
          expect(
              xs[i], closeTo(xs[0] + [0, 1, 1.5, 2, 3][i] * beatWidth, 0.01));
        }
        final timeline = <String, Object>{
          'timelineBeatWidthPx': 40,
          'timelineLeadingWidthPx': 120,
          'timelineDurationBeats': 12,
        };
        expect(render({...timeline, 'spacingPolicy': 'equalBeat'}),
            render({...timeline, 'spacingPolicy': 'optical'}));
      });
    }
  }

  for (final type in ['standard', 'jianpu', 'tablature']) {
    for (final meter in ['4/4', '6/8']) {
      test('fixed timeline bridge $type $meter uses quarter-note pixels', () {
        final count = meter == '6/8' ? 6 : 8;
        final notes = List.filled(count, 'e').join(' ');
        for (final scale in [5, 10]) {
          for (final density in ['compact', 'spacious']) {
            final svg = abcToSvg(
              'X:1\nM:$meter\nL:1/8\nK:C\n$notes|$notes|',
              metadata,
              type,
              jsonEncode({
                'layout': 'singleLine',
                'staffSpace': scale,
                'density': density,
                'timelineBeatWidthPx': 40,
                'timelineLeadingWidthPx': 120,
                'timelineDurationBeats': 12,
              }),
            );
            expect(svg, isNot(startsWith('error:')));
            final text = RegExp(r'<text x="([^"]+)"[^>]*>([^<]+)</text>');
            final xs = text
                .allMatches(svg)
                .where((match) => type == 'standard'
                    ? match.group(2) == ''
                    : type == 'jianpu'
                        ? match.group(2) == '3'
                        : RegExp(r'^\d+$').hasMatch(match.group(2)!))
                .map((match) => double.parse(match.group(1)!) * scale)
                .toList();
            expect(xs, hasLength(count * 2));
            for (var i = 0; i < xs.length; i++) {
              expect(xs[i], closeTo(120 + i * 20, 0.01),
                  reason: '$density $scale note $i');
            }
            expect(svg, contains('width="600"'));
          }
        }
      });
    }
  }
  test('fixed timeline overrides wrapping but duration never stretches music',
      () {
    const abc = 'X:1\nM:4/4\nL:1/4\nK:C\nC D E F|C D E F|';
    String render(Map<String, Object> options) =>
        abcToSvg(abc, metadata, 'standard', jsonEncode(options));
    final options = <String, Object>{
      'staffSpace': 10,
      'timelineBeatWidthPx': 40,
      'timelineLeadingWidthPx': 120
    };
    final fixed = render(options);
    expect(render({...options, 'layout': 'wrapped', 'maxWidth': 1}), fixed);
    expect(render({...options, 'timelineDurationBeats': 1}), fixed);
    final extended = render({...options, 'timelineDurationBeats': 12});
    expect(extended, contains('width="600"'));
    final heads = RegExp(r'<text x="([^"]+)"[^>]*></text>');
    expect(heads.allMatches(extended).map((m) => m.group(1)),
        heads.allMatches(fixed).map((m) => m.group(1)));
  });

  test('bridge rejects invalid timeline and staff scale inputs', () {
    for (final options in [
      {'timelineBeatWidthPx': 0},
      {'timelineBeatWidthPx': -1},
      {'timelineBeatWidthPx': 40, 'timelineLeadingWidthPx': -1},
      {'timelineBeatWidthPx': 40, 'timelineDurationBeats': -1},
      {'timelineBeatWidthPx': 40, 'staffSpace': 0},
    ]) {
      expect(
          abcToSvg('X:1\nM:4/4\nL:1/4\nK:C\nC D E F|', metadata, 'standard',
              jsonEncode(options)),
          startsWith('error:'));
    }
  });

  test('Wasm bridge keeps equalBeat spacing across multiple measures', () {
    final svg = abcToSvg(
      'X:1\nM:4/4\nL:1/8\nK:C\nz2 z z z2 z2|z2 z z z2 z2|',
      metadata,
      'jianpu',
      jsonEncode({
        'spacingPolicy': 'equalBeat',
        'layout': 'singleLine',
        'showTitle': false,
      }),
    );
    expect(svg, isNot(startsWith('error:')));
    final xs = RegExp(r'<text x="([^"]+)"[^>]*>0</text>')
        .allMatches(svg)
        .map((match) => double.parse(match.group(1)!))
        .toList();
    expect(xs, hasLength(10));
    expect(xs.take(5).toList(), orderedEquals(xs.take(5).toList()..sort()));
    expect(xs.skip(5).toList(), orderedEquals(xs.skip(5).toList()..sort()));
    expect(xs[5] - xs[0], greaterThan(0));
    expect(xs.last, greaterThan(xs[5]));
  });

  for (final mode in ['singleLine', 'wrapped', 'paged']) {
    test('equalBeat mixed sparse TAB rests stay even in $mode', () {
      final abc = 'X:1\nM:4/4\nL:1/8\nK:C\n'
          'V:1 st=jianpu\nV:2 st=tablature\n'
          '[V:1] z8|z8|z8|z8|\n'
          '[V:2] z/2 e6 z3/2|e6 z/4 z/4 z3/2|'
          'z/2 e6 z3/2|e6 z/4 z/4 z3/2|';
      final svg = abcToSvg(
          abc,
          metadata,
          'standard',
          jsonEncode({
            'spacingPolicy': 'equalBeat',
            'layout': mode == 'singleLine' ? mode : 'wrapped',
            'maxWidth': 50,
            'showTitle': false,
            if (mode == 'paged') 'pageSize': 'A4',
          }));
      expect(svg, isNot(startsWith('error:')));
      final xs = RegExp(r'<text x="([^"]+)"[^>]*>0</text>')
          .allMatches(svg)
          .map((match) => double.parse(match.group(1)!))
          .toList();
      expect(xs, hasLength(16));
      for (var measure = 0; measure < 4; measure++) {
        final start = measure * 4;
        final gap = xs[start + 1] - xs[start];
        expect(gap, greaterThan(0));
        expect(xs[start + 2] - xs[start + 1], closeTo(gap, 0.002));
        expect(xs[start + 3] - xs[start + 2], closeTo(gap, 0.002));
      }
    });
  }

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

  for (final type in ['standard', 'jianpu']) {
    test('ABC tempo annotations render only real changes in $type', () {
      final svg = abcToSvg(
        'X:1\nM:4/4\nL:1/4\nQ:1/4=58\nK:C\n'
        'C D E F | [Q:1/4=72] G A B c |',
        metadata,
        type,
      );

      expect(svg, isNot(startsWith('error:')));
      expect(svg, isNot(contains('58')));
      expect(svg, contains('72'));
    });
  }

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
