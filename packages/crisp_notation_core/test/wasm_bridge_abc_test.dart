import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../example/wasm/score_bridge_convert.dart';

void main() {
  final metadata = File('../crisp_notation/assets/smufl/bravura_metadata.json').readAsStringSync();

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

  test('Wasm bridge exposes only ABC conversion APIs', () {
    final entrypoint = File('example/wasm/score_bridge.dart').readAsStringSync();
    final conversion =
        File('example/wasm/score_bridge_convert.dart').readAsStringSync();

    expect(entrypoint, isNot(contains('fortState')));
    expect(conversion, isNot(contains('fortState')));
    expect(conversion, isNot(contains('Score.simple')));
    expect(entrypoint, contains('abcToSvg'));
    expect(entrypoint, contains('abcToStudioNotes'));
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
