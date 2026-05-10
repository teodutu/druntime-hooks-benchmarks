#!/usr/bin/env bash
#
# build_gdc.sh - Standalone GDC build script for debugging.
#
# Usage:  ./build_gdc.sh <commit_sha>
#
# Builds GDC (the GCC fork with the D frontend) from $GDC_REPO_PATH (default
# ~/dlang/gdc) at the given commit and verifies the resulting `gdc` works.

set -euo pipefail

SHA="${1:-}"
if [[ -z "$SHA" ]]; then
    echo "Usage: $0 <commit_sha>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GDC_REPO_PATH="${GDC_REPO_PATH:-$HOME/dlang/gdc}"
GDC_INSTALL_DIR="${GDC_INSTALL_DIR:-$SCRIPT_DIR/gdc-install}"
GDC_BUILD_DIR="${GDC_BUILD_DIR:-$GDC_REPO_PATH/build}"
NPROC="${NPROC:-$(($(nproc) / 2))}"
[[ "$NPROC" -lt 1 ]] && NPROC=1

echo "[gdc-build] GDC repo:    $GDC_REPO_PATH"
echo "[gdc-build] commit:      $SHA"
echo "[gdc-build] install dir: $GDC_INSTALL_DIR"
echo "[gdc-build] build dir:   $GDC_BUILD_DIR"
echo "[gdc-build] parallel:    -j$NPROC"

# --- Checkout -----------------------------------------------------------------
pushd "$GDC_REPO_PATH" >/dev/null
git reset --hard HEAD
# Don't `git clean -fdx` -- the upstream GCC tree is huge and a clean
# wipes ~/dlang/gdc/build (intermediate ~10GB). We use a separate build
# directory below to keep the source tree pristine.
git checkout -f "$SHA"

# Some GDC commits need contrib/download_prerequisites for in-tree gmp/mpfr/mpc/isl.
# Skip if already present.
if [[ -x ./contrib/download_prerequisites && ! -d gmp ]]; then
    echo "[gdc-build] Downloading GCC prerequisites (gmp/mpfr/mpc/isl)"
    ./contrib/download_prerequisites
fi
popd >/dev/null

# --- Configure ----------------------------------------------------------------
# Use an out-of-tree build directory (recommended by GCC).
rm -rf "$GDC_BUILD_DIR"
mkdir -p "$GDC_BUILD_DIR"

# --- Locate a host GDC (needed to bootstrap libphobos) ------------------------
HOST_GDC="${HOST_GDC:-}"
if [[ -z "$HOST_GDC" ]]; then
    for c in gdc gdc-13 gdc-12 gdc-11 gdc-10; do
        if command -v "$c" >/dev/null 2>&1; then HOST_GDC=$(command -v "$c"); break; fi
    done
fi
if [[ -z "$HOST_GDC" ]]; then
    echo "ERROR: no host gdc found; install gdc-12 (apt) or set HOST_GDC=/path/to/gdc" >&2
    exit 1
fi
echo "[gdc-build] host gdc:    $HOST_GDC ($("$HOST_GDC" --version | head -1))"

# Match the host C/C++ compiler version to the host gdc, otherwise stage1
# can miscompile the in-tree D frontend (observed with old GDC commits + gcc-11).
HOST_GCC="${HOST_GCC:-}"
HOST_GXX="${HOST_GXX:-}"
if [[ -z "$HOST_GCC" || -z "$HOST_GXX" ]]; then
    gdc_major=$("$HOST_GDC" -dumpversion | cut -d. -f1)
    if [[ -x "/usr/bin/gcc-$gdc_major" && -x "/usr/bin/g++-$gdc_major" ]]; then
        HOST_GCC="/usr/bin/gcc-$gdc_major"
        HOST_GXX="/usr/bin/g++-$gdc_major"
    else
        HOST_GCC="$(command -v gcc)"
        HOST_GXX="$(command -v g++)"
    fi
fi
echo "[gdc-build] host gcc:    $HOST_GCC"
echo "[gdc-build] host g++:    $HOST_GXX"

pushd "$GDC_BUILD_DIR" >/dev/null
CC="$HOST_GCC" CXX="$HOST_GXX" GDC="$HOST_GDC" "$GDC_REPO_PATH/configure" \
    --disable-checking --disable-libphobos-checking --disable-libgomp \
    --disable-libmudflap --disable-libquadmath --disable-libssp \
    --disable-nls --enable-lto --enable-languages=d --disable-multilib \
    --disable-bootstrap --prefix="$GDC_INSTALL_DIR"

# --- Build --------------------------------------------------------------------
make -j"$NPROC"

rm -rf "$GDC_INSTALL_DIR"
make install-strip
popd >/dev/null

# --- Verify -------------------------------------------------------------------
GDC_BIN="$GDC_INSTALL_DIR/bin/gdc"
if [[ ! -x "$GDC_BIN" ]]; then
    echo "ERROR: $GDC_BIN was not produced" >&2
    exit 1
fi

echo "[gdc-build] $GDC_BIN --version:"
"$GDC_BIN" --version | head -2

TMPDIR_TEST=$(mktemp -d)
cat > "$TMPDIR_TEST/hello.d" <<'EOF'
import std.stdio;
void main() { writeln("hello from gdc"); }
EOF
( cd "$TMPDIR_TEST" && "$GDC_BIN" hello.d -o hello && ./hello )
rm -rf "$TMPDIR_TEST"

echo "[gdc-build] OK"
