#!/bin/bash
set -e
SRC=/tmp/openssl-openssl-922a20d
PREFIX="$HOME/mingw-openssl"
mkdir -p "$PREFIX"
cd "$SRC"
./Configure mingw64 no-asm no-shared no-tests --prefix="$PREFIX" --cross-compile-prefix="" CC="zig cc -target x86_64-windows-gnu" AR="zig ar" RANLIB="zig ranlib"
make -j$(nproc)
make install_sw
echo "DONE: OpenSSL for MinGW installed to $PREFIX"