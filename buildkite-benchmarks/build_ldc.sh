#!/usr/bin/env bash
#
# build_ldc.sh - Standalone LDC build script for debugging.
#
# Usage:  ./build_ldc.sh <commit_sha>
#
# Builds LDC from $LDC_REPO_PATH (default ~/dlang/ldc) at the given commit
# and verifies the resulting compiler produces a "hello world" binary.

set -euo pipefail

SHA="${1:-}"
if [[ -z "$SHA" ]]; then
    echo "Usage: $0 <commit_sha>" >&2
    exit 2
fi

LDC_REPO_PATH="${LDC_REPO_PATH:-$HOME/dlang/ldc}"
NPROC="${NPROC:-$(($(nproc) / 2))}"
[[ "$NPROC" -lt 1 ]] && NPROC=1

# --- Host D compiler (needed to bootstrap LDC) --------------------------------
# Prefer a pre-installed dmd / ldc2 / ldmd2; auto-detect from ~/dlang.
HOST_DC="${HOST_DC:-}"
if [[ -z "$HOST_DC" ]]; then
    for c in dmd ldmd2 ldc2; do
        if command -v "$c" >/dev/null 2>&1; then HOST_DC=$(command -v "$c"); break; fi
    done
fi
if [[ -z "$HOST_DC" ]]; then
    for d in "$HOME/dlang"/dmd-*/linux/bin64/dmd "$HOME/dlang"/ldc-*/bin/ldmd2 "$HOME/dlang"/ldc-*/bin/ldc2; do
        [[ -x "$d" ]] && { HOST_DC="$d"; break; }
    done
fi
if [[ -z "$HOST_DC" ]]; then
    echo "ERROR: no host D compiler found (set HOST_DC=/path/to/dmd or install one in ~/dlang)" >&2
    exit 1
fi

echo "[ldc-build] LDC repo:   $LDC_REPO_PATH"
echo "[ldc-build] commit:     $SHA"
echo "[ldc-build] host DC:    $HOST_DC"
echo "[ldc-build] parallel:   -j$NPROC"

# --- Checkout -----------------------------------------------------------------
pushd "$LDC_REPO_PATH" >/dev/null

# Wipe leftover state (mirrors performance/run_benchmark.sh::sync_repos).
rm -rf build
git submodule deinit -f --all >/dev/null 2>&1 || true
git reset --hard HEAD
git clean -fdx
git checkout -f "$SHA"
git submodule update --init --recursive

# --- Pick an LLVM that matches the LDC commit --------------------------------
# Old LDC commits (pre-2023) need LLVM 11-13; newer commits work with 15+.
# Caller may force one with LLVM_CONFIG=/usr/bin/llvm-config-XX.
LLVM_CONFIG="${LLVM_CONFIG:-}"
if [[ -z "$LLVM_CONFIG" ]]; then
    # Heuristic: pick LLVM based on the commit's year.
    commit_year=$(git -C "$LDC_REPO_PATH" show -s --format=%ci "$SHA" | cut -c1-4)
    case "$commit_year" in
        2019|2020|2021|2022) candidates="13 12 11" ;;
        2023)                candidates="15 14 13" ;;
        *)                   candidates="20 19 18 17 16 15 14 13" ;;
    esac
    for v in $candidates; do
        if [[ -x "/usr/bin/llvm-config-$v" ]]; then
            LLVM_CONFIG="/usr/bin/llvm-config-$v"
            break
        fi
    done
fi
if [[ -z "$LLVM_CONFIG" || ! -x "$LLVM_CONFIG" ]]; then
    echo "ERROR: no suitable llvm-config found (set LLVM_CONFIG=/usr/bin/llvm-config-XX)" >&2
    exit 1
fi
echo "[ldc-build] LLVM:       $LLVM_CONFIG ($("$LLVM_CONFIG" --version))"
if [[ -z "$LLVM_CONFIG" || ! -x "$LLVM_CONFIG" ]]; then
    echo "ERROR: no suitable llvm-config found (set LLVM_CONFIG=/usr/bin/llvm-config-XX)" >&2
    exit 1
fi
echo "[ldc-build] LLVM:       $LLVM_CONFIG ($("$LLVM_CONFIG" --version))"

# --- Configure ----------------------------------------------------------------
mkdir -p build
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DD_COMPILER="$HOST_DC" \
    -DLLVM_CONFIG="$LLVM_CONFIG"

# --- Build --------------------------------------------------------------------
# The performance/run_benchmark.sh script builds:
#   ldc2  (the compiler driver)
#   druntime-ldc, phobos2-ldc, phobos2-ldc-shared
# We additionally build ldmd2 because dub invokes "<compiler>" as if it were
# the dmd-style frontend (ldc2 itself accepts that too, but ldmd2 is the
# canonical wrapper).
cmake --build build -j"$NPROC" --target ldc2
cmake --build build -j"$NPROC" --target ldmd2
cmake --build build -j"$NPROC" --target druntime-ldc phobos2-ldc phobos2-ldc-shared

popd >/dev/null

# --- Verify -------------------------------------------------------------------
LDC_BIN="$LDC_REPO_PATH/build/bin/ldc2"
if [[ ! -x "$LDC_BIN" ]]; then
    echo "ERROR: $LDC_BIN was not produced" >&2
    exit 1
fi

echo "[ldc-build] $LDC_BIN --version:"
"$LDC_BIN" --version | head -3

TMPDIR_TEST=$(mktemp -d)
cat > "$TMPDIR_TEST/hello.d" <<'EOF'
import std.stdio;
void main() { writeln("hello from ldc"); }
EOF
( cd "$TMPDIR_TEST" && "$LDC_BIN" hello.d -of=hello && ./hello )
rm -rf "$TMPDIR_TEST"

echo "[ldc-build] OK"
