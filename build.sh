#!/bin/bash
# PhoneVault - fallback build without Theos.
#
# Compiles every Swift file under Sources/ with plain swiftc, wraps the result in PhoneVault.app,
# copies it to /Applications (or ~/Applications when that is not writable), signs it ad hoc and opens it.
#
# Needs the Swift compiler: Xcode, or the Command Line Tools ("xcode-select --install").
#
#   ./build.sh              build, install and open
#   ./build.sh --no-open    build and install only
#   ./build.sh --build-only build into ./build and stop

set -euo pipefail

APP_NAME="PhoneVault"
MIN_MACOS="13.0"

OPEN_APP=1
INSTALL_APP=1
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN_APP=0 ;;
        --build-only) OPEN_APP=0; INSTALL_APP=0 ;;
        -h|--help)
            echo "usage: ./build.sh [--no-open] [--build-only]"
            exit 0 ;;
        *)
            echo "unknown option: $arg" >&2
            exit 2 ;;
    esac
done

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: this script only works on macOS." >&2
    exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "error: the Swift compiler was not found. Install the Command Line Tools with: xcode-select --install" >&2
    exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86_64" ]; then
    ARCH="arm64"
fi

# Collect the sources (recursively; names may contain spaces).
SOURCES=()
while IFS= read -r -d '' file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources" -type f -name '*.swift' -print0 | sort -z)

if [ "${#SOURCES[@]}" -eq 0 ]; then
    echo "error: no Swift files found under $ROOT/Sources" >&2
    exit 1
fi

for file in "${SOURCES[@]}"; do
    if [ "$(basename "$file")" = "main.swift" ]; then
        echo "error: $file: a file called main.swift cannot be combined with -parse-as-library / @main." >&2
        exit 1
    fi
done

if [ ! -f "$ROOT/Resources/Info.plist" ]; then
    echo "error: Resources/Info.plist is missing." >&2
    exit 1
fi

echo "==> Compiling ${#SOURCES[@]} Swift files for $ARCH (macOS $MIN_MACOS and newer)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun --sdk macosx swiftc \
    -O \
    -parse-as-library \
    -swift-version 5 \
    -module-name "$APP_NAME" \
    -sdk "$SDK_PATH" \
    -target "$ARCH-apple-macosx$MIN_MACOS" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    "${SOURCES[@]}"

echo "==> Assembling $APP_NAME.app"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Everything else in Resources/ goes to Contents/Resources (icons and so on).
if [ -d "$ROOT/Resources" ]; then
    find "$ROOT/Resources" -mindepth 1 -maxdepth 1 ! -name 'Info.plist' ! -name '.DS_Store' -print0 |
    while IFS= read -r -d '' item; do
        cp -R "$item" "$APP/Contents/Resources/"
    done
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP"

if [ "$INSTALL_APP" -eq 0 ]; then
    echo "==> Built $APP"
    exit 0
fi

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

echo "==> Installing to $DEST/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$DEST/$APP_NAME.app"
ditto "$APP" "$DEST/$APP_NAME.app"
xattr -cr "$DEST/$APP_NAME.app" 2>/dev/null || true
codesign --force --deep --sign - "$DEST/$APP_NAME.app"

echo "==> Installed $DEST/$APP_NAME.app"
if [ "$OPEN_APP" -eq 1 ]; then
    open "$DEST/$APP_NAME.app"
fi
