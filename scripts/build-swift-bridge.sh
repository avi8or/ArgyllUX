#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/apple/ArgyllUX/Bridge/Generated"
CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.cargo-home}"
export CARGO_HOME
PROFILE_FLAG=""
PROFILE_DIR="debug"

if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
  PROFILE_FLAG="--release"
  PROFILE_DIR="release"
fi

mkdir -p "$OUT_DIR"
mkdir -p "$CARGO_HOME"

pushd "$ROOT_DIR" >/dev/null

cargo build -p argyllux_engine $PROFILE_FLAG

ENGINE_DYLIB="$ROOT_DIR/target/$PROFILE_DIR/libargyllux_engine.dylib"
ENGINE_STATICLIB="$ROOT_DIR/target/$PROFILE_DIR/libargyllux_engine.a"

cargo run -p uniffi-bindgen -- generate --library "$ENGINE_DYLIB" --language swift --out-dir "$OUT_DIR"
cp "$ENGINE_STATICLIB" "$OUT_DIR/libargyllux_engine.a"

popd >/dev/null
