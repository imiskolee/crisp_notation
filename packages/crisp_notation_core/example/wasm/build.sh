#!/usr/bin/env bash
# Compiles crisp_notation_core to WebAssembly (dart2wasm / WasmGC).
#
#   ./build.sh          # build all entry points into ./build/
#   node run_node.mjs   # run the smoke as WASM under Node (skip; score_bridge
#                        # needs dart:js_interop and bravura_metadata.json)
#   (serve this dir over http and open index.html or studio bridge demo)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

echo "→ wasm_smoke.dart (asset-free codec smoke)"
dart compile wasm wasm_smoke.dart -o build/wasm_smoke.wasm

echo "→ main.dart (browser js-interop demo)"
dart compile wasm main.dart -o build/main.wasm

echo "→ score_bridge.dart (ABC → crisp_notation SVG bridge)"
dart compile wasm score_bridge.dart -o build/score_bridge.wasm

echo "done → build/  (serve index.html over http for the codec demo; serve the Studio over http for score_bridge)"
