#!/bin/bash
# Builds idevicerestore and the libimobiledevice libraries it needs from source (current git),
# as static libraries in a private prefix, then copies any remaining non-system dylibs next to
# it so it runs on a Mac without Homebrew packages. Result: out/bin/idevicerestore + out/lib/*.dylib
set -euo pipefail
ROOT="$(pwd)"
PREFIX="$ROOT/limd-prefix"
OUT="$ROOT/out"
SRC="$ROOT/limd-src"
mkdir -p "$PREFIX" "$OUT/bin" "$OUT/lib" "$SRC"

brew install autoconf automake libtool pkg-config libzip openssl@3 dylibbundler >/dev/null
OPENSSL="$(brew --prefix openssl@3)"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$OPENSSL/lib/pkgconfig:$(brew --prefix libzip)/lib/pkgconfig"
export CFLAGS="-O2 -mmacosx-version-min=13.0"
export LDFLAGS="-mmacosx-version-min=13.0"

build() {
  local name="$1"; shift
  echo "==> $name"
  git clone -q --depth 1 "https://github.com/libimobiledevice/$name.git" "$SRC/$name"
  cd "$SRC/$name"
  ./autogen.sh --prefix="$PREFIX" --enable-static --disable-shared --without-cython "$@" >/dev/null
  make -j"$(sysctl -n hw.ncpu)" >/dev/null
  make install >/dev/null
  cd "$ROOT"
}

build libplist
build libimobiledevice-glue
build libusbmuxd
build libtatsu
build libimobiledevice --with-ssl=openssl
build libirecovery
build idevicerestore

cp "$PREFIX/bin/idevicerestore" "$OUT/bin/"
# Copy leftover dylibs (libzip, OpenSSL) beside the tool and point it at them.
dylibbundler -od -b -x "$OUT/bin/idevicerestore" -d "$OUT/lib/" -p @executable_path/../lib/ >/dev/null
echo "==> linked libraries"
otool -L "$OUT/bin/idevicerestore"
"$OUT/bin/idevicerestore" --version
"$OUT/bin/idevicerestore" --help | head -5
