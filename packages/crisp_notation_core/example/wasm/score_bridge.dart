library;

import 'dart:js_interop';

import 'score_bridge_convert.dart' show abcToStudioNotes, abcToSvg;

@JS('globalThis.abcToSvg')
external set _abcToSvg(JSFunction fn);

@JS('globalThis.abcToStudioNotes')
external set _abcToStudioNotes(JSFunction fn);

void main() {
  // 4-arg form: (abc, metadata, staffType, optionsJson) — optionsJson optional.
  _abcToSvg = (
    JSString abcText,
    JSString bravuraMetaJson,
    JSString staffType, [
    JSString? optionsJson,
  ]) {
    return abcToSvg(
      abcText.toDart,
      bravuraMetaJson.toDart,
      staffType.toDart,
      optionsJson?.toDart ?? '{}',
    ).toJS;
  }.toJS;

  _abcToStudioNotes = ((JSString abcText) =>
          abcToStudioNotes(abcText.toDart).toJS)
      .toJS;
}