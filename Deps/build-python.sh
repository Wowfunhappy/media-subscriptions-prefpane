#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN="${TOOLCHAIN:-$HOME/Developer/Compilers/toolchains/clang-22/bin}"
JOBS="${JOBS:-8}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/media-subscriptions-python.XXXXXX")"
OPENSSL_PREFIX="$BUILD_DIR/openssl"
SQLITE_PREFIX="$BUILD_DIR/sqlite"
PYTHON_PREFIX="$BUILD_DIR/python"
PACKAGE_DIR="$BUILD_DIR/package"

trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$BUILD_DIR"
curl -kfsSLO https://www.python.org/ftp/python/3.14.7/Python-3.14.7.tar.xz
curl -kfsSLO https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz
curl -kfsSLO https://sqlite.org/2026/sqlite-autoconf-3530400.tar.gz

tar -xf Python-3.14.7.tar.xz
tar -xf openssl-3.5.8.tar.gz
tar -xf sqlite-autoconf-3530400.tar.gz

cd "$BUILD_DIR/openssl-3.5.8"
env CC="$TOOLCHAIN/clang" AR="$TOOLCHAIN/llvm-ar" RANLIB="$TOOLCHAIN/llvm-ranlib" \
    ./Configure darwin64-x86_64-cc no-shared no-tests no-apps no-docs no-module no-legacy no-dso \
    --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX/ssl" -mmacosx-version-min=10.9 -Os
make -j "$JOBS"
make install_sw

cd "$BUILD_DIR/sqlite-autoconf-3530400"
env CC="$TOOLCHAIN/clang" AR="$TOOLCHAIN/llvm-ar" CFLAGS='-Os -mmacosx-version-min=10.9' \
    ./configure --prefix="$SQLITE_PREFIX" --disable-shared --disable-readline --disable-load-extension
make -j "$JOBS"
make install

cd "$BUILD_DIR/Python-3.14.7"
env CC="$TOOLCHAIN/clang" CXX="$TOOLCHAIN/clang++" AR="$TOOLCHAIN/llvm-ar" RANLIB="$TOOLCHAIN/llvm-ranlib" \
    MACOSX_DEPLOYMENT_TARGET=10.9 CFLAGS='-Os -mmacosx-version-min=10.9' \
    CPPFLAGS="-I$OPENSSL_PREFIX/include -I$SQLITE_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib -L$SQLITE_PREFIX/lib" \
    LIBSQLITE3_CFLAGS="-I$SQLITE_PREFIX/include" LIBSQLITE3_LIBS="$SQLITE_PREFIX/lib/libsqlite3.a" \
    ./configure --prefix="$PYTHON_PREFIX" --with-openssl="$OPENSSL_PREFIX" --with-openssl-rpath=no \
    --disable-test-modules --without-static-libpython --without-mimalloc --with-ensurepip=install
make -j "$JOBS"
make install

env CC="$TOOLCHAIN/clang" CXX="$TOOLCHAIN/clang++" AR="$TOOLCHAIN/llvm-ar" RANLIB="$TOOLCHAIN/llvm-ranlib" \
    MACOSX_DEPLOYMENT_TARGET=10.9 CFLAGS='-Os -mmacosx-version-min=10.9' \
    "$PYTHON_PREFIX/bin/python3" -m pip install --no-cache-dir --no-binary=:all: \
    brotli==1.2.0 certifi==2026.7.22 charset-normalizer==3.5.0 idna==3.18 mutagen==1.48.1 \
    pycryptodomex==3.23.0 requests==2.34.2 urllib3==2.7.0 websockets==17.0.1

cp -a "$PYTHON_PREFIX" "$PACKAGE_DIR"
PYTHON_LIB="$PACKAGE_DIR/lib/python3.14"
rm -rf "$PACKAGE_DIR/include" "$PACKAGE_DIR/share" "$PACKAGE_DIR/lib/pkgconfig" \
    "$PYTHON_LIB/idlelib" "$PYTHON_LIB/tkinter" "$PYTHON_LIB/turtledemo" "$PYTHON_LIB/ensurepip" \
    "$PYTHON_LIB/venv" "$PYTHON_LIB/pydoc_data" "$PYTHON_LIB/unittest" "$PYTHON_LIB/__phello__" \
    "$PYTHON_LIB/site-packages/pip" "$PYTHON_LIB/site-packages/pip-26.2.1.dist-info" \
    "$PYTHON_LIB/site-packages/Cryptodome/SelfTest" "$PYTHON_LIB/site-packages/certifi/tests"
find "$PACKAGE_DIR" -type d -name __pycache__ -prune -exec rm -rf '{}' +
find "$PACKAGE_DIR" -type f -name '*.pyi' -delete
find "$PACKAGE_DIR/bin" -type f ! -name python3.14 -delete
find "$PACKAGE_DIR/bin" -type l ! -name python3 -delete
/usr/bin/strip -x "$PACKAGE_DIR/bin/python3.14"
find "$PACKAGE_DIR" -type f -name '*.so' -exec /usr/bin/strip -x '{}' +

cd "$PYTHON_LIB"
zip -9 -q -r ../python314.zip . -x './site-packages/*' './lib-dynload/*'
find "$PYTHON_LIB" -mindepth 1 -maxdepth 1 ! -name site-packages ! -name lib-dynload -exec rm -rf '{}' +

mkdir "$PACKAGE_DIR/LICENSES"
cp "$BUILD_DIR/Python-3.14.7/LICENSE" "$PACKAGE_DIR/LICENSES/CPython.txt"
cp "$BUILD_DIR/openssl-3.5.8/LICENSE.txt" "$PACKAGE_DIR/LICENSES/OpenSSL.txt"

env PYTHONDONTWRITEBYTECODE=1 "$PACKAGE_DIR/bin/python3" -c 'import brotli, certifi, charset_normalizer, Cryptodome, idna, mutagen, requests, sqlite3, ssl, urllib3, websockets'
env PYTHONDONTWRITEBYTECODE=1 "$PACKAGE_DIR/bin/python3" "$PROJECT_DIR/Deps/yt-dlp" --version

rm -rf "$PROJECT_DIR/Deps/python3"
cp -a "$PACKAGE_DIR" "$PROJECT_DIR/Deps/python3"
