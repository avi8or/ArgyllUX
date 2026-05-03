#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify|--build-only|--open-existing|--clean|--xcode-build]

Builds the ArgyllUX macOS app, stops any running copy, and opens the freshly
built app bundle. The short repo wrapper is ./run.
USAGE
}

MODE="${1:-run}"
APP_NAME="ArgyllUX"
BUNDLE_ID="app.argyllux.mac"
MIN_SYSTEM_VERSION="${ARGYLLUX_MIN_SYSTEM_VERSION:-14.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/apple/ArgyllUX.xcodeproj"
SCHEME="ArgyllUX"
DERIVED_DATA="${ARGYLLUX_DERIVED_DATA:-$ROOT_DIR/.build/DerivedData}"
BUILD_DIR="${ARGYLLUX_RUN_BUILD_DIR:-$ROOT_DIR/dist}"
DESTINATION="${ARGYLLUX_DESTINATION:-platform=macOS,arch=arm64}"
CONFIGURATION="${ARGYLLUX_CONFIGURATION:-Debug}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
ACTOOL="$DEVELOPER_DIR/usr/bin/actool"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PKG_INFO="$APP_CONTENTS/PkgInfo"
BRIDGE_DIR="$ROOT_DIR/apple/ArgyllUX/Bridge/Generated"
ASSETS_DIR="$ROOT_DIR/apple/ArgyllUX/Assets.xcassets"

if [[ ! -x "$XCODEBUILD" ]]; then
  echo "xcodebuild not found at $XCODEBUILD" >&2
  echo "Install Xcode or set DEVELOPER_DIR to the full Xcode developer directory." >&2
  exit 1
fi

if [[ ! -x "$SWIFTC" ]]; then
  echo "swiftc not found at $SWIFTC" >&2
  echo "Install Xcode or set DEVELOPER_DIR to the full Xcode developer directory." >&2
  exit 1
fi

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_bridge() {
  echo "Building Rust engine and Swift bridge"
  CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/scripts/build-swift-bridge.sh"
}

compile_assets() {
  if [[ ! -x "$ACTOOL" || ! -d "$ASSETS_DIR" ]]; then
    return 0
  fi

  echo "Compiling asset catalog"
  "$ACTOOL" \
    --compile "$APP_RESOURCES" \
    --platform macosx \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/asset-info.plist" \
    "$ASSETS_DIR" >/dev/null
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

  printf "APPL????" >"$PKG_INFO"
}

build_app_direct() {
  echo "Building $APP_NAME directly with swiftc"
  echo "Bundle: $APP_BUNDLE"

  build_bridge

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"

  compile_assets
  write_info_plist

  local sdk
  sdk="$(xcrun --sdk macosx --show-sdk-path)"

  local sources=()
  while IFS= read -r -d '' source_file; do
    sources+=("$source_file")
  done < <(find "$ROOT_DIR/apple/ArgyllUX/Sources" -name "*.swift" -print0 | sort -z)

  "$SWIFTC" \
    -sdk "$sdk" \
    -target arm64-apple-macosx"$MIN_SYSTEM_VERSION" \
    -parse-as-library \
    -g -Onone \
    -I "$BRIDGE_DIR" \
    -Xcc -fmodule-map-file="$BRIDGE_DIR/argylluxFFI.modulemap" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "$INFO_PLIST" \
    -o "$APP_BINARY" \
    "${sources[@]}" \
    "$BRIDGE_DIR/argyllux.swift" \
    "$BRIDGE_DIR/libargyllux_engine.a" \
    -lsqlite3

  rm -rf "$APP_BINARY.dSYM"
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

xcode_build_app() {
  echo "Building $APP_NAME ($CONFIGURATION) with Xcode"
  echo "Derived data: $DERIVED_DATA"
  "$XCODEBUILD" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk macosx \
    -destination "$DESTINATION" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
}

clean_app() {
  echo "Cleaning $APP_NAME run bundle at $BUILD_DIR"
  rm -rf "$BUILD_DIR"

  echo "Cleaning Xcode derived data at $DERIVED_DATA"
  "$XCODEBUILD" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk macosx \
    -destination "$DESTINATION" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    clean \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
}

open_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Built app bundle not found: $APP_BUNDLE" >&2
    echo "Run ./run first, or override ARGYLLUX_DERIVED_DATA if the app was built elsewhere." >&2
    exit 1
  fi

  echo "Opening $APP_BUNDLE"
  /usr/bin/open -n "$APP_BUNDLE" --args -ApplePersistenceIgnoreState YES
}

case "$MODE" in
  run)
    stop_running_app
    build_app_direct
    open_app
    ;;
  --build-only|build)
    build_app_direct
    ;;
  --xcode-build|xcode)
    xcode_build_app
    ;;
  --open-existing|open)
    stop_running_app
    open_app
    ;;
  --clean|clean)
    clean_app
    ;;
  --debug|debug)
    stop_running_app
    build_app_direct
    if [[ ! -x "$APP_BINARY" ]]; then
      echo "Built app binary not found: $APP_BINARY" >&2
      exit 1
    fi
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_running_app
    build_app_direct
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_running_app
    build_app_direct
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_running_app
    build_app_direct
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
