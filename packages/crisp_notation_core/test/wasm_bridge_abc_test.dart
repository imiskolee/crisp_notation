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
}
