#!/usr/bin/env bash
#
# setup_environment.sh
#
# Prepares the host system to run run_buildkite_benchmarks.sh.
# Installs the system packages from buildkite-benchmarks/dlang-ci/buildkite/Dockerfile
# (i.e. the same set the dlang-ci Buildkite agents use), then ensures that the
# LDC and GDC source repositories are cloned at ~/dlang/ldc and ~/dlang/gdc.
#
# This script is intended to be run once before invoking run_buildkite_benchmarks.sh.
# It can be re-run safely; it will only install missing pieces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LDC_REPO_PATH="${LDC_REPO_PATH:-$HOME/dlang/ldc}"
GDC_REPO_PATH="${GDC_REPO_PATH:-$HOME/dlang/gdc}"

LDC_REPO_URL="https://github.com/ldc-developers/ldc.git"
GDC_REPO_URL="https://github.com/D-Programming-GDC/gcc.git"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; }

#-------------------------------------------------------------------------------
# 1. System packages (mirroring dlang-ci/buildkite/Dockerfile)
#-------------------------------------------------------------------------------
install_system_packages() {
    if ! command -v sudo >/dev/null 2>&1; then
        SUDO=""
    else
        SUDO="sudo"
    fi

    log "Updating apt package index"
    $SUDO apt-get update -y

    log "Installing base packages from dlang-ci Dockerfile"
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends \
        build-essential clang cmake curl gdb git jq sqlite3 libblas-dev \
        libbz2-dev libcairo2-dev libclang-dev libcurl4-gnutls-dev libevent-dev \
        libgcrypt20-dev libgpg-error-dev libgtk-3-0 liblapack-dev libldap2-dev \
        liblzo2-dev libopenblas-dev libreadline-dev libssl-dev libxml2-dev \
        libxslt1-dev libzmq3-dev llvm-dev moreutils net-tools ninja-build \
        pkg-config python3-dev python3-yaml python3-nose redis-server \
        rsync ruby ruby-dev sudo time unzip wget gnupg lsb-release \
        apt-utils software-properties-common bc dub

    # Extra packages required to build GCC/GDC from source.
    log "Installing GCC build prerequisites"
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends \
        flex bison gawk texinfo libgmp-dev libmpfr-dev libmpc-dev libisl-dev \
        zlib1g-dev autoconf automake libtool \
        gcc-10 g++-10 gcc-12 g++-12 gdc-12

    # Multiple LLVM dev packages so build_ldc.sh can pick a version that matches
    # the requested LDC commit (older LDC commits need llvm-13, newer ones llvm-15+).
    log "Installing LLVM dev packages"
    for v in 13 14 15; do
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends \
            "llvm-$v-dev" || warn "llvm-$v-dev unavailable"
    done

    # Make sure a host D compiler is available for bootstrapping LDC.
    if ! command -v dmd >/dev/null 2>&1 && ! command -v ldc2 >/dev/null 2>&1; then
        warn "No host D compiler (dmd/ldc2) detected on PATH."
        warn "Install one via your distro or https://dlang.org/install.html before benchmarking."
    fi
}

#-------------------------------------------------------------------------------
# 2. Clone LDC and GDC source repositories (idempotent)
#-------------------------------------------------------------------------------
clone_repo() {
    local url="$1"
    local dest="$2"
    local name="$3"

    if [[ -d "$dest/.git" ]]; then
        log "$name already cloned at $dest"
        return
    fi
    if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
        err "$dest exists but is not a git checkout; refusing to overwrite"
        exit 1
    fi
    log "Cloning $name from $url to $dest"
    mkdir -p "$(dirname "$dest")"
    git clone "$url" "$dest"
}

clone_compilers() {
    clone_repo "$LDC_REPO_URL" "$LDC_REPO_PATH" "LDC"
    log "Initialising LDC submodules"
    git -C "$LDC_REPO_PATH" submodule update --init --recursive || true

    clone_repo "$GDC_REPO_URL" "$GDC_REPO_PATH" "GDC"
}

main() {
    if [[ "${1:-}" == "--no-apt" ]]; then
        log "Skipping system package installation (--no-apt)"
    else
        install_system_packages
    fi
    clone_compilers
    log "Environment setup complete."
    log "Next: bash $SCRIPT_DIR/run_buildkite_benchmarks.sh"
}

main "$@"
