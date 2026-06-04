#!/bin/sh
# Build the Playground web app (Elixir) to WebAssembly via Elixism + Hoot.
# SPDX-License-Identifier: Apache-2.0
#
# Pipeline:
#   1. Elixism's bundle.scm (handler mode) flattens the runtime and AOT-compiles
#      ../playground_app.ex into one Hoot program whose final value is the
#      request handler  (method path body) -> json string.
#   2. Hoot compiles that to program.wasm (guild compile-wasm; `hoot compile`
#      when available).
#   3. Hoot's JS runtime (reflect.js + reflect.wasm + wtf8.wasm) is copied in.
#
# Then:  node server.js   (an http server that calls into the Wasm per request)
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ELIXISM=${ELIXISM:-"$HERE/../../../elixism"}
HOOT_DIR=${HOOT_DIR:-"$ELIXISM/../hoot"}
APP="$HERE/../playground_app.ex"

if [ ! -x "$HOOT_DIR/pre-inst-env" ]; then
  echo "Hoot toolchain not found at $HOOT_DIR (set HOOT_DIR)." >&2
  exit 1
fi

echo "==> Bundling Playground app -> program.scm (handler mode)"
( cd "$ELIXISM" && guile -L module --no-auto-compile wasm-node/bundle.scm "$APP" handler ) > "$HERE/program.scm"

echo "==> Compiling program.scm -> program.wasm (Hoot)"
if "$HOOT_DIR/pre-inst-env" hoot compile -o "$HERE/program.wasm" "$HERE/program.scm" 2>/dev/null; then
  echo "    (via: hoot compile)"
else
  "$HOOT_DIR/pre-inst-env" guild compile-wasm -o "$HERE/program.wasm" "$HERE/program.scm"
  echo "    (via: guild compile-wasm)"
fi

echo "==> Copying Hoot JS runtime"
cp "$HOOT_DIR/reflect-js/reflect.js"      "$HERE/"
cp "$HOOT_DIR/reflect-wasm/reflect.wasm"  "$HERE/"
cp "$HOOT_DIR/reflect-wasm/wtf8.wasm"     "$HERE/"

echo "==> Done.  Run:  node $HERE/server.js"
