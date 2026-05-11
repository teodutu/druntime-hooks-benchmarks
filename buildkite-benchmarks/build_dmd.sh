#!/usr/bin/env bash
#
# build_dmd.sh - Standalone DMD build script.
#
# Usage:  ./build_dmd.sh <commit_sha>
#
# Builds DMD from $DMD_REPO_PATH (default ~/dlang/dmd) at the given commit
# and verifies the resulting compiler produces a "hello world" binary.
#
# The DMD repo layout changed over time:
#   - Old (pre-2023): src/posix.mak, druntime/phobos as separate sibling repos.
#   - New (post-2023): compiler/ + druntime/ dirs in-tree, phobos still separate.
#
# In both cases phobos is expected at $PHOBOS_REPO_PATH (default ~/dlang/phobos).

set -euo pipefail

SHA="${1:-}"
if [[ -z "$SHA" ]]; then
    echo "Usage: $0 <commit_sha>" >&2
    exit 2
fi

DMD_REPO_PATH="${DMD_REPO_PATH:-$HOME/dlang/dmd}"
PHOBOS_REPO_PATH="${PHOBOS_REPO_PATH:-$HOME/dlang/phobos}"
DRUNTIME_REPO_PATH="${DRUNTIME_REPO_PATH:-$HOME/dlang/druntime}"
NPROC="${NPROC:-$(($(nproc) / 2))}"
[[ "$NPROC" -lt 1 ]] && NPROC=1

# --- Host D compiler (needed to bootstrap DMD) --------------------------------
HOST_DC="${HOST_DC:-}"
if [[ -z "$HOST_DC" ]]; then
    for c in dmd ldmd2 ldc2; do
        if command -v "$c" >/dev/null 2>&1; then HOST_DC=$(command -v "$c"); break; fi
    done
fi
if [[ -z "$HOST_DC" ]]; then
    for d in "$HOME/dlang"/dmd-*/linux/bin64/dmd "$HOME/dlang"/ldc-*/bin/ldmd2; do
        [[ -x "$d" ]] && { HOST_DC="$d"; break; }
    done
fi
if [[ -z "$HOST_DC" ]]; then
    echo "ERROR: no host D compiler found (set HOST_DC=/path/to/dmd or install one in ~/dlang)" >&2
    exit 1
fi

echo "[dmd-build] DMD repo:   $DMD_REPO_PATH"
echo "[dmd-build] commit:     $SHA"
echo "[dmd-build] host DC:    $HOST_DC"
echo "[dmd-build] parallel:   -j$NPROC"

# --- Checkout -----------------------------------------------------------------
pushd "$DMD_REPO_PATH" >/dev/null

git reset --hard HEAD
git clean -fdx
git checkout -f "$SHA"
git submodule update --init --recursive

# --- Detect repo layout ------------------------------------------------------
# New layout (post-2023): has compiler/ and druntime/ dirs in-tree.
# Old layout (pre-2023): build via src/posix.mak, druntime/phobos are siblings.
if [[ -d compiler && -d druntime ]]; then
    LAYOUT="new"
else
    LAYOUT="old"
fi
echo "[dmd-build] layout:     $LAYOUT"

DMD_BIN="$DMD_REPO_PATH/generated/linux/release/64/dmd"

# --- Build --------------------------------------------------------------------
# Determine the version tag for matching druntime/phobos.
local_version=$(cat VERSION 2>/dev/null || echo "")

if [[ "$LAYOUT" == "new" ]]; then
    # New layout: top-level Makefile builds dmd + druntime.
    make -j"$NPROC" HOST_DMD="$HOST_DC" dmd
    make -j"$NPROC" druntime

    DRUNTIME_IMPORT="$DMD_REPO_PATH/druntime/import"
    DRUNTIME_LIB="$DMD_REPO_PATH/generated/linux/release/64"
else
    # Old layout: build via src/posix.mak.
    make -C src -f posix.mak -j"$NPROC" HOST_DMD="$HOST_DC" dmd

    # druntime is a separate repo.
    if [[ ! -d "$DRUNTIME_REPO_PATH" ]]; then
        echo "ERROR: druntime repo not found at $DRUNTIME_REPO_PATH" >&2
        exit 1
    fi
    # Check out matching druntime version.
    pushd "$DRUNTIME_REPO_PATH" >/dev/null
    git reset --hard HEAD >/dev/null 2>&1
    git clean -fdx >/dev/null 2>&1
    git fetch --quiet --tags origin || true
    if [[ -n "$local_version" ]] && git rev-parse --verify --quiet "$local_version" >/dev/null; then
        git checkout -f "$local_version" >/dev/null 2>&1
    fi
    popd >/dev/null

    # Build druntime with the freshly built dmd.
    make -C "$DRUNTIME_REPO_PATH" -f posix.mak -j"$NPROC" DMD="$DMD_BIN"

    DRUNTIME_IMPORT="$DRUNTIME_REPO_PATH/import"
    DRUNTIME_LIB="$DRUNTIME_REPO_PATH/generated/linux/release/64"
fi

# Build phobos (always a separate repo).
if [[ ! -d "$PHOBOS_REPO_PATH" ]]; then
    echo "ERROR: phobos repo not found at $PHOBOS_REPO_PATH" >&2
    exit 1
fi
# Check out matching phobos version: use PHOBOS_COMMIT if set, then try the
# version tag, then fall back to the latest master commit before the DMD
# commit's parent (to avoid phobos commits that depend on future DMD changes).
DMD_PARENT_DATE=$(git -C "$DMD_REPO_PATH" show -s --format=%ci "${SHA}^" 2>/dev/null || \
                  git -C "$DMD_REPO_PATH" show -s --format=%ci "$SHA")
# Subtract 7 days to avoid phobos commits that depend on future DMD changes
# (phobos sometimes merges support for new hooks before DMD merges them).
DMD_SAFE_DATE=$(date -d "$DMD_PARENT_DATE - 7 days" '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || \
               echo "$DMD_PARENT_DATE")
pushd "$PHOBOS_REPO_PATH" >/dev/null
git reset --hard HEAD >/dev/null 2>&1
git clean -fdx >/dev/null 2>&1
git fetch --quiet --tags origin || true
if [[ -n "${PHOBOS_COMMIT:-}" ]]; then
    git checkout -f "$PHOBOS_COMMIT" >/dev/null 2>&1
elif [[ -n "${local_version:-}" ]] && git rev-parse --verify --quiet "$local_version" >/dev/null; then
    git checkout -f "$local_version" >/dev/null 2>&1
else
    # Use safe date to avoid picking phobos commits that land between
    # matching phobos/dmd PRs (phobos sometimes merges before DMD).
    phobos_commit=$(git rev-list -n 1 --before="$DMD_SAFE_DATE" origin/master 2>/dev/null || true)
    if [[ -n "$phobos_commit" ]]; then
        git checkout -f "$phobos_commit" >/dev/null 2>&1
    fi
fi
echo "[dmd-build] phobos at: $(git log --oneline -1 HEAD)"
popd >/dev/null

if [[ "$LAYOUT" == "new" ]]; then
    # New phobos Makefile expects DMD_DIR=../dmd (sibling of phobos).
    make -C "$PHOBOS_REPO_PATH" -j"$NPROC"
else
    make -C "$PHOBOS_REPO_PATH" -f posix.mak -j"$NPROC" DMD="$DMD_BIN"
fi
PHOBOS_SRC="$PHOBOS_REPO_PATH"
PHOBOS_LIB="$PHOBOS_REPO_PATH/generated/linux/release/64"

popd >/dev/null

# --- Generate dmd.conf --------------------------------------------------------
# Place a dmd.conf next to the binary so dub can find druntime + phobos.
DMD_BIN_DIR="$(dirname "$DMD_BIN")"
cat > "$DMD_BIN_DIR/dmd.conf" <<CONF
[Environment64]
DFLAGS=-I$DRUNTIME_IMPORT -I$PHOBOS_SRC -L-L$DRUNTIME_LIB -L-L$PHOBOS_LIB -L--export-dynamic -fPIC
CONF
echo "[dmd-build] wrote $DMD_BIN_DIR/dmd.conf"

# --- Verify -------------------------------------------------------------------
if [[ ! -x "$DMD_BIN" ]]; then
    echo "ERROR: $DMD_BIN was not produced" >&2
    exit 1
fi

echo "[dmd-build] $DMD_BIN --version:"
"$DMD_BIN" --version | head -3

TMPDIR_TEST=$(mktemp -d)
cat > "$TMPDIR_TEST/hello.d" <<'EOF'
import std.stdio;
void main() { writeln("hello from dmd"); }
EOF
( cd "$TMPDIR_TEST" && "$DMD_BIN" hello.d -of=hello && ./hello )
rm -rf "$TMPDIR_TEST"

echo "[dmd-build] OK"
