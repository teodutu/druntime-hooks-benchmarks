#!/usr/bin/env bash
#
# run_buildkite_benchmarks.sh
#
# Benchmarks the dlang-ci Buildkite project list against two commits of LDC
# and two commits of GDC, and emits a Markdown report.
#
# Methodology:
#  - For each (compiler, commit_sha) pair:
#      * Check out commit_sha in the compiler's source repo and build it.
#      * For each project:
#          - Clone the project (cached) and check out its latest tag (or HEAD
#            for repos that don't tag) restricted to commits older than the
#            compiler commit's date.
#          - `dub build --compiler=$DC` once to warm caches / fail early.
#          - Time `dub test --compiler=$DC` NUM_ITERATIONS times.
#  - Aggregate avg / stddev per project and emit a Markdown table.
#
# Errors per project are appended to errors.log with compiler, sha and the
# full error text; the project's row is filled with N/A.

set -uo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NUM_ITERATIONS="${NUM_ITERATIONS:-100}"

LDC_REPO_PATH="${LDC_REPO_PATH:-$HOME/dlang/ldc}"
GDC_REPO_PATH="${GDC_REPO_PATH:-$HOME/dlang/gdc}"
DMD_REPO_PATH="${DMD_REPO_PATH:-$HOME/dlang/dmd}"

# Path to compiler binaries inside their source/build trees.
LDC_COMPILER_PATH="$LDC_REPO_PATH/build/bin/ldc2"
GDC_INSTALL_DIR="$SCRIPT_DIR/gdc-install"
GDC_COMPILER_PATH="$GDC_INSTALL_DIR/bin/gdc"
DMD_COMPILER_PATH="$DMD_REPO_PATH/generated/linux/release/64/dmd"

# Wrapper that strips -Werror/-w from dub's response files so GDC treats
# deprecation warnings as warnings, not errors.
GDC_WRAPPER_PATH="$SCRIPT_DIR/bin/gdc-wrapper"

# rdmd from the host LDC - needed by some dub pre-generate commands.
RDMD_PATH="$SCRIPT_DIR/bin/rdmd"

# NOTE: 38c60e5075f (the originally requested old GDC commit, Dec 2021)
# does not build: its bundled D frontend miscompiles its own libphobos.
# We use the closest preceding libphobos merge commit that builds cleanly.
OLD_GDC_COMMIT="${OLD_GDC_COMMIT:-e19c6389966216af5925d2917a206cedc40540e8}"
NEW_GDC_COMMIT="${NEW_GDC_COMMIT:-2ead01297ced8fd03387021025222a839503eaf6}"

OLD_LDC_COMMIT="${OLD_LDC_COMMIT:-5b0bd6865f2458b2c3fd00f7ef9652086f2d875d}"
NEW_LDC_COMMIT="${NEW_LDC_COMMIT:-4b76bab1456db5e1704a7db088e33bd83e8b1419}"

OLD_DMD_COMMIT="${OLD_DMD_COMMIT:-1ece3ea0c9188fa0a28210dcd15f511129884a9c}"
NEW_DMD_COMMIT="${NEW_DMD_COMMIT:-c2c8189599b894771393100ceae1ca2da30202d0}"

PROJECTS_DIR="$SCRIPT_DIR/projects"
RESULTS_DIR="$SCRIPT_DIR/results"
COMPILER_BUILD_MARKERS_DIR="$SCRIPT_DIR/.compiler-builds"
LOG_DIR="$RESULTS_DIR/logs"
ERROR_LOG="$RESULTS_DIR/errors.log"
REPORT_FILE="${REPORT_FILE:-$RESULTS_DIR/report.md}"
CSV_FILE="$RESULTS_DIR/benchmarks.csv"

mkdir -p "$PROJECTS_DIR" "$RESULTS_DIR" "$LOG_DIR" "$COMPILER_BUILD_MARKERS_DIR"
: > "$ERROR_LOG"
rm -f "$LOG_DIR"/*.log  # clear stale per-project logs from previous runs

# Use half the number of cores so the system doesn't freeze.
NPROC="$(($(nproc) / 2))"

#-------------------------------------------------------------------------------
# Project list (mirrors uncommented entries in dlang-ci/buildkite.sh)
#-------------------------------------------------------------------------------
PROJECTS=(
    "vibe-d/vibe.d+examples"
    "vibe-d/vibe.d+tests"
    "ldc-developers/ldc"
    "vibe-d/vibe.d+base"
    "dlang/phobos"
    "dlang/phobos+no-autodecode"
    "sociomantic-tsunami/ocean"
    "sociomantic-tsunami/swarm"
    "sociomantic-tsunami/turtle"
    "dlang/dub"
    "vibe-d/vibe-core+epoll"
    "vibe-d/vibe-core+select"
    "higgsjs/Higgs"
    "rejectedsoftware/ddox"
    "BlackEdder/ggplotd"
    "dlang-community/D-Scanner"
    "dlang-tour/core"
    "d-widget-toolkit/dwt"
    "rejectedsoftware/diet-ng"
    "mbierlee/poodinis"
    "dlang/tools"
    "atilaneves/unit-threaded"
    "gecko0307/dagon"
    "dlang-community/DCD"
    "CyberShadow/ae"
    "jmdavis/dxml"
    "jacob-carlborg/dstep"
    "libmir/mir-algorithm"
    "dlang-community/D-YAML"
    "libmir/mir-random"
    "dlang-community/libdparse"
    "aliak00/optional"
    "dlang-community/dfmt"
    "Abscissa/libInputVisitor"
    "atilaneves/automem"
    "AuburnSounds/intel-intrinsics"
    "DerelictOrg/DerelictFT"
    "DerelictOrg/DerelictGL3"
    "DerelictOrg/DerelictGLFW3"
    "DerelictOrg/DerelictSDL2"
    "dlang-community/containers"
    "dlang/undeaD"
    "DlangScience/scid"
    "ikod/dlang-requests"
    "symmetryinvestments/autowrap"
    "symmetryinvestments/concurrency"
    "symmetryinvestments/excel-d"
    "symmetryinvestments/ldapauth"
    "kaleidicassociates/lubeck"
    "symmetryinvestments/xlsxreader"
    "lgvz/imageformats"
    "libmir/mir"
    "libmir/mir-core"
    "libmir/mir-cpuid"
    "libmir/mir-optim"
    "msoucy/dproto"
    "Netflix/vectorflow"
    "nomad-software/dunit"
    "pbackus/sumtype"
    "PhilippeSigaud/Pegged"
    "repeatedly/mustache-d"
    "s-ludwig/std_data_json"
    "s-ludwig/taggedalgebraic"
    "snazzy-d/sdc"
    "funkwerk-mobility/serialized"
    "funkwerk-mobility/mocked"
    "andrey-zherikov/argparse"
)

#-------------------------------------------------------------------------------
# Result storage
#
# Indexed by "${compiler}|${sha}|${project}" (project = full "owner/name+variant" string).
# Values: avg<TAB>stddev   (or "N/A<TAB>N/A" on error)
#-------------------------------------------------------------------------------
declare -A RESULTS

#-------------------------------------------------------------------------------
# Helpers
#-------------------------------------------------------------------------------
log()  { printf '\033[1;34m[bench]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[bench]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[bench]\033[0m %s\n' "$*" >&2; }

# Strip "+variant" suffix to get the actual GitHub repo full name.
project_repo_name() {
    echo "${1%%+*}"
}

# Local directory for cloning a project (variants share the same clone).
project_dir() {
    local repo
    repo="$(project_repo_name "$1")"
    echo "$PROJECTS_DIR/$(basename "$repo")"
}

# Reference (tag/branch) to check out for a given project.
# Mirrors the case statement in dlang-ci/buildkite/build_project.sh.
project_ref_for() {
    local project="$1"
    local repo
    repo="$(project_repo_name "$project")"
    case "$repo" in
        sociomantic-tsunami/ocean)  echo "v6.x.x" ;;
        sociomantic-tsunami/swarm)  echo "v7.x.x" ;;
        sociomantic-tsunami/turtle) echo "v11.x.x" ;;
        dlang/undeaD)               echo "master" ;;
        vibe-d/vibe.d)              echo "master" ;;
        vibe-d/vibe-core)           echo "master" ;;
        # core repos: just use master
        dlang/dmd|dlang/druntime|dlang/phobos|dlang/dub|dlang/tools|ldc-developers/ldc)
            echo "master" ;;
        *)
            echo "" # signal: discover latest tag dynamically
            ;;
    esac
}

# Discover latest semver-ish tag from a remote URL; fall back to "master".
# Optionally constrain to tags created before $compiler_date (so projects that
# require a newer compiler frontend than $compiler aren't picked).
discover_latest_tag() {
    local url="$1"
    local compiler_date="${2:-}"
    local tags
    tags=$(git ls-remote --tags "$url" 2>/dev/null \
        | sed -n 's|.*refs/tags/\(v\?[0-9]*\.[0-9]*\.[0-9]*$\)|\1|p' \
        | sort --version-sort)
    if [[ -z "$tags" ]]; then
        echo "master"
        return
    fi
    if [[ -z "$compiler_date" ]]; then
        echo "$tags" | tail -n 1
        return
    fi
    # Filter: keep only tags whose underlying commit is <= $compiler_date.
    local repo_dir best=""
    repo_dir=$(pwd)
    local tag tag_date
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tag_date=$(git -C "$repo_dir" log -1 --format=%ci "refs/tags/$tag" 2>/dev/null) || continue
        # Compare YYYY-MM-DD strings.
        if [[ "${tag_date:0:10}" < "${compiler_date:0:10}" || "${tag_date:0:10}" == "${compiler_date:0:10}" ]]; then
            best="$tag"
        fi
    done <<<"$tags"
    if [[ -z "$best" ]]; then
        # Nothing pre-dates the compiler; fall back to oldest tag, then master.
        best=$(echo "$tags" | head -n 1)
    fi
    echo "${best:-master}"
}

# Ensure project clone exists; doesn't switch refs.
ensure_project_cloned() {
    local project="$1"
    local repo
    repo="$(project_repo_name "$project")"
    local dir
    dir="$(project_dir "$project")"
    if [[ -d "$dir/.git" ]]; then
        return 0
    fi
    log "Cloning $repo -> $dir"
    git clone --quiet "https://github.com/$repo" "$dir"
}

# Reset a project clone to a clean state and switch to the requested ref,
# constrained to commits no later than $compiler_date when possible.
prepare_project_ref() {
    local project="$1"
    local compiler_date="$2"
    local dir
    dir="$(project_dir "$project")"

    pushd "$dir" >/dev/null

    # Clean any state left over from a previous run.
    git reset --hard HEAD >/dev/null 2>&1 || true
    git clean -fdx >/dev/null 2>&1 || true

    # Make sure all refs are present (we did a full clone, so this is cheap).
    git fetch --quiet --tags origin || true

    local ref
    ref="$(project_ref_for "$project")"
    if [[ -z "$ref" ]]; then
        # Date-aware tag discovery uses the local clone (already in $dir).
        ref="$(discover_latest_tag "https://github.com/$(project_repo_name "$project")" "$compiler_date")"
    fi

    # If ref is a branch, try to find the latest commit on it before $compiler_date.
    local target_commit=""
    if git rev-parse --verify --quiet "refs/tags/$ref" >/dev/null; then
        target_commit="$ref"
    else
        # treat as branch
        local remote_ref="origin/$ref"
        if git rev-parse --verify --quiet "$remote_ref" >/dev/null; then
            target_commit=$(git rev-list -n 1 --before="$compiler_date" "$remote_ref" 2>/dev/null || true)
            [[ -z "$target_commit" ]] && target_commit="$remote_ref"
        else
            target_commit="$ref"
        fi
    fi

    git checkout -f "$target_commit" >/dev/null 2>&1
    git submodule update --init --recursive --quiet || true

    popd >/dev/null
}

# Run a custom test command for projects that require it; returns the
# command via stdout. Empty output means "use the default `dub test`".
project_test_command() {
    local project="$1"
    local DC="$2"
    case "$project" in
        "AuburnSounds/intel-intrinsics")
            echo "dub test --compiler=$DC && dub test -b unittest-release --compiler=$DC"
            ;;
        "dlang-community/D-YAML")
            echo "dub build --compiler=$DC && dub test --compiler=$DC"
            ;;
        "atilaneves/unit-threaded"|"libmir/mir-algorithm"|"libmir/mir"|"pbackus/sumtype"|"aliak00/optional")
            echo "dub test --compiler=$DC"
            ;;
        "snazzy-d/sdc")
            echo "dub build :sdfmt --compiler=$DC"
            ;;
        "ikod/dlang-requests")
            echo "dub build -c std --compiler=$DC"
            ;;
        # --- Bespoke builds (projects that don't use plain dub test) ---
        "higgsjs/Higgs")
            echo "make -C source test DC=$DC"
            ;;
        "vibe-d/vibe.d+base")
            echo "VIBED_DRIVER=vibe-core PARTS=builds,unittests ./run-ci.sh"
            ;;
        "vibe-d/vibe.d+tests")
            echo "VIBED_DRIVER=vibe-core PARTS=tests ./run-ci.sh"
            ;;
        "vibe-d/vibe.d+examples")
            echo "VIBED_DRIVER=vibe-core PARTS=examples ./run-ci.sh"
            ;;
        "vibe-d/vibe-core+epoll")
            echo "CONFIG=epoll ./run-ci.sh"
            ;;
        "vibe-d/vibe-core+select")
            echo "CONFIG=select ./run-ci.sh"
            ;;
        "dlang/tools")
            # tools Makefile uses DMD-style flags; only works with ldmd2.
            local dmd_compat
            dmd_compat="$(dirname "$(realpath "$DC")")/ldmd2"
            if [[ -x "$dmd_compat" ]]; then
                echo "make -f posix.mak all DMD='$dmd_compat' DFLAGS= -j$NPROC"
            else
                # GDC has no DMD-compatible wrapper; fall back to dub build.
                echo "dub build --compiler=$DC"
            fi
            ;;
        "d-widget-toolkit/dwt")
            # dwt tests require running tools/test_snippets.d; just build.
            echo "dub build --compiler=$DC"
            ;;
        "rejectedsoftware/ddox")
            # ddox tests start a vibe-d HTTP server that never exits; just build.
            echo "dub build --compiler=$DC"
            ;;
        "symmetryinvestments/autowrap")
            echo "dub test --compiler=$DC"
            ;;
        *)
            # Default: plain `dub test`.
            echo "dub test --compiler=$DC"
            ;;
    esac
}

# Apply project-specific patches/setup that build_project.sh does pre-test.
project_pre_test_setup() {
    local project="$1"
    local dir
    dir="$(project_dir "$project")"
    pushd "$dir" >/dev/null
    case "$project" in
        "BlackEdder/ggplotd")
            sed -i 's|auto seed = unpredictableSeed|auto seed = 54321|' source/ggplotd/example.d 2>/dev/null || true
            ;;
        "CyberShadow/ae")
            perl -0777 -pi -e "s/unittest[^{]*{[^{}]*xAttrs[^{}]*}//" sys/file.d 2>/dev/null || true
            ;;
        "dlang-tour/core")
            if [[ ! -d public/content/en ]]; then
                (cd public/content && git clone --depth 15 https://github.com/dlang-tour/english en) 2>/dev/null || true
                (cd ../.. && git submodule update) 2>/dev/null || true
            fi
            ;;
        "vibe-d/vibe.d+tests")
            # Remove spurious tests that fail outside full CI
            rm -f tests/tls-with-pkcs11/*.d 2>/dev/null || true
            ;;
        "vibe-d/vibe-core+epoll"|"vibe-d/vibe-core+select")
            # Remove spurious tests that fail outside full CI
            rm -f tests/tls-with-pkcs11/*.d 2>/dev/null || true
            ;;
        "symmetryinvestments/autowrap")
            # autowrap needs pyd fetched and setup
            dub fetch --cache=local pyd 2>/dev/null || true
            if command -v python3 >/dev/null; then
                dub run pyd:setup 2>/dev/null || true
                [[ -f pyd_set_env_vars.sh ]] && source pyd_set_env_vars.sh python3 2>/dev/null || true
                export PYTHON_LIB_DIR="/usr/lib"
            fi
            ;;
        "dlang-community/libdparse")
            git submodule update --init --recursive 2>/dev/null || true
            ;;
    esac
    popd >/dev/null
}

# Skip projects that are too involved or impossible to benchmark.
should_skip_project() {
    case "$1" in
        # Full bootstrap build - not a meaningful benchmark target.
        "ldc-developers/ldc")
            return 0 ;;
        # Requires dmd/druntime checkout & full Make-based build.
        "dlang/phobos"|"dlang/phobos+no-autodecode")
            return 0 ;;
        # Dead / archived repos with custom Make + old toolchain.
        "sociomantic-tsunami/ocean"|"sociomantic-tsunami/swarm"|"sociomantic-tsunami/turtle")
            return 0 ;;
        # stdx-allocator dependency has a static assert incompatible with all
        # our compiler versions; run-ci.sh also needs a full CI environment.
        "vibe-d/vibe.d+base"|"vibe-d/vibe.d+tests"|"vibe-d/vibe.d+examples"|\
        "vibe-d/vibe-core+epoll"|"vibe-d/vibe-core+select"|\
        "rejectedsoftware/ddox")
            return 0 ;;
        # Makefile uses DMD-specific flags (-debug, -dip25); not LDC/GDC compatible.
        "higgsjs/Higgs")
            return 0 ;;
        # Needs rdmd + Python bindings (pyd) setup not available in our env.
        "symmetryinvestments/autowrap")
            return 0 ;;
    esac
    return 1
}

# Computes mean and population stddev over space-separated samples on stdin/args.
# Echoes "<mean> <stddev>".
mean_stddev() {
    local -a samples=("$@")
    local n="${#samples[@]}"
    if (( n == 0 )); then
        echo "N/A N/A"
        return
    fi
    local mean stddev
    mean=$(awk -v n="$n" 'BEGIN{s=0} {s+=$1} END{printf "%.4f", s/n}' < <(printf '%s\n' "${samples[@]}"))
    if (( n < 2 )); then
        stddev="0.0000"
    else
        stddev=$(awk -v n="$n" -v m="$mean" \
            'BEGIN{s=0} {d=$1-m; s+=d*d} END{printf "%.4f", sqrt(s/n)}' \
            < <(printf '%s\n' "${samples[@]}"))
    fi
    echo "$mean $stddev"
}

#-------------------------------------------------------------------------------
# Compiler builds
#-------------------------------------------------------------------------------

# Returns 0 if a build for the given compiler+sha already exists.
compiler_build_cached() {
    local compiler="$1" sha="$2"
    local marker="$COMPILER_BUILD_MARKERS_DIR/${compiler}-${sha}.ok"
    [[ -f "$marker" ]]
}

mark_compiler_built() {
    local compiler="$1" sha="$2"
    touch "$COMPILER_BUILD_MARKERS_DIR/${compiler}-${sha}.ok"
}

build_ldc() {
    local sha="$1"
    log "Building LDC @ $sha (via build_ldc.sh)"
    LDC_REPO_PATH="$LDC_REPO_PATH" NPROC="$NPROC" \
        "$SCRIPT_DIR/build_ldc.sh" "$sha"
    if [[ ! -x "$LDC_COMPILER_PATH" ]]; then
        err "LDC build did not produce $LDC_COMPILER_PATH"
        return 1
    fi
    mark_compiler_built ldc "$sha"
}

build_gdc() {
    local sha="$1"
    log "Building GDC @ $sha (via build_gdc.sh)"
    GDC_REPO_PATH="$GDC_REPO_PATH" GDC_INSTALL_DIR="$GDC_INSTALL_DIR" \
        NPROC="$NPROC" \
        "$SCRIPT_DIR/build_gdc.sh" "$sha"
    if [[ ! -x "$GDC_COMPILER_PATH" ]]; then
        err "GDC build did not produce $GDC_COMPILER_PATH"
        return 1
    fi
    mark_compiler_built gdc "$sha"
}

build_dmd() {
    local sha="$1"
    log "Building DMD @ $sha (via build_dmd.sh)"
    DMD_REPO_PATH="$DMD_REPO_PATH" NPROC="$NPROC" \
        "$SCRIPT_DIR/build_dmd.sh" "$sha"
    if [[ ! -x "$DMD_COMPILER_PATH" ]]; then
        err "DMD build did not produce $DMD_COMPILER_PATH"
        return 1
    fi
    mark_compiler_built dmd "$sha"
}

# Check out a compiler commit, build (if not cached), and echo the commit date.
prepare_compiler() {
    local compiler="$1" sha="$2"
    local repo_path
    case "$compiler" in
        ldc) repo_path="$LDC_REPO_PATH" ;;
        gdc) repo_path="$GDC_REPO_PATH" ;;
        dmd) repo_path="$DMD_REPO_PATH" ;;
        *)   err "Unknown compiler $compiler"; return 1 ;;
    esac

    # Always make sure the requested commit is in the repo so we can read its date.
    pushd "$repo_path" >/dev/null
    git fetch --quiet --all --tags || true
    local commit_date
    commit_date=$(git show -s --format=%ci "$sha")
    popd >/dev/null

    if compiler_build_cached "$compiler" "$sha"; then
        log "Reusing cached $compiler build for $sha"
    else
        case "$compiler" in
            ldc) build_ldc "$sha" ;;
            gdc) build_gdc "$sha" ;;
            dmd) build_dmd "$sha" ;;
        esac
    fi

    echo "$commit_date"
}

#-------------------------------------------------------------------------------
# Per-project benchmarking
#-------------------------------------------------------------------------------

bench_project() {
    local compiler="$1" sha="$2" compiler_date="$3" DC="$4" project="$5"
    local key="${compiler}|${sha}|${project}"
    local plog="$LOG_DIR/${compiler}-${sha:0:10}-${project//\//_}.log"

    if should_skip_project "$project"; then
        log "Skipping $project (not benchmarked via dub test)"
        RESULTS["$key"]="N/A"$'\t'"N/A"
        echo "[SKIP] $compiler $sha $project: project uses bespoke build" >> "$ERROR_LOG"
        return 0
    fi

    log "[$compiler $sha] $project"

    if ! ensure_project_cloned "$project" >>"$plog" 2>&1; then
        warn "Clone failed for $project"
        RESULTS["$key"]="N/A"$'\t'"N/A"
        {
            echo "===== CLONE FAILURE ====="
            echo "compiler: $compiler  sha: $sha  project: $project"
            cat "$plog"
            echo
        } >> "$ERROR_LOG"
        return 0
    fi

    if ! prepare_project_ref "$project" "$compiler_date" >>"$plog" 2>&1; then
        warn "Checkout failed for $project"
        RESULTS["$key"]="N/A"$'\t'"N/A"
        {
            echo "===== CHECKOUT FAILURE ====="
            echo "compiler: $compiler  sha: $sha  project: $project"
            tail -n 200 "$plog"
            echo
        } >> "$ERROR_LOG"
        return 0
    fi

    project_pre_test_setup "$project" >>"$plog" 2>&1 || true

    local dir
    dir="$(project_dir "$project")"
    pushd "$dir" >/dev/null

    # Make sure sub-processes (dub itself, unit-threaded test runners, ddox,
    # etc.) can find the freshly built `ldc2` / `ldmd2` on PATH. The directory
    # containing $DC takes priority so we don't accidentally pick a system one.
    local dc_dir
    dc_dir="$(dirname "$(realpath "$DC")")"
    local saved_path="$PATH"
    # Add compiler bin dir + our bin/ (rdmd) to PATH.
    export PATH="$dc_dir:$SCRIPT_DIR/bin:$PATH"

    # Export DC so dub can resolve $DC references in dub.json/sdl.
    local saved_dc="${DC_ENV_SAVED:-}"
    export DC
    DC_ENV_SAVED="$DC"

    # Set DFLAGS to tolerate deprecations.
    # For LDC:  -d allows deprecated constructs (implicit string concat etc.).
    #           Setting DFLAGS causes dub to use the "$DFLAGS" build type;
    #           dub test still generates a test runner and adds -unittest.
    # For GDC:  the gdc-wrapper script strips -w/-Werror from response files
    #           so we don't need DFLAGS overrides at all.  dub test naturally
    #           adds -funittest via its "unittest" build type.
    local saved_dflags="${DFLAGS:-}"
    case "$compiler" in
        gdc)  unset DFLAGS ;;
        ldc)  export DFLAGS="-d" ;;
        dmd)  export DFLAGS="-d" ;;
    esac

    local test_cmd
    test_cmd=$(project_test_command "$project" "$DC")

    # Warm-up: run the test command once and discard its timing. This makes
    # sure dependencies are fetched, the project actually builds, and dub's
    # build cache is populated before the timed runs.
    if ! eval "$test_cmd" >>"$plog" 2>&1; then
        warn "Warm-up build/test failed for $project"
        export PATH="$saved_path"
        if [[ -n "$saved_dflags" ]]; then export DFLAGS="$saved_dflags"; else unset DFLAGS; fi
        popd >/dev/null
        RESULTS["$key"]="N/A"$'\t'"N/A"
        {
            echo "===== BUILD FAILURE ====="
            echo "compiler: $compiler  sha: $sha  project: $project"
            tail -n 200 "$plog"
            echo
        } >> "$ERROR_LOG"
        return 0
    fi

    local samples=()
    local failed=0
    for ((i=1; i<=NUM_ITERATIONS; i++)); do
        local t0 t1 dt
        t0=$(date +%s.%N)
        if ! eval "$test_cmd" >>"$plog" 2>&1; then
            failed=1
            break
        fi
        t1=$(date +%s.%N)
        dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.4f", b-a}')
        samples+=("$dt")
        echo "[iter $i] $dt s" >>"$plog"
    done

    export PATH="$saved_path"
    if [[ -n "$saved_dflags" ]]; then export DFLAGS="$saved_dflags"; else unset DFLAGS; fi
    popd >/dev/null

    if (( failed )); then
        warn "Test failed for $project"
        RESULTS["$key"]="N/A"$'\t'"N/A"
        {
            echo "===== TEST FAILURE ====="
            echo "compiler: $compiler  sha: $sha  project: $project"
            tail -n 200 "$plog"
            echo
        } >> "$ERROR_LOG"
        return 0
    fi

    read -r mean stddev <<<"$(mean_stddev "${samples[@]}")"
    RESULTS["$key"]="${mean}"$'\t'"${stddev}"
    log "  -> mean=${mean}s stddev=${stddev}s"
}

run_buildkite_with_compiler_date() {
    local compiler="$1" sha="$2" compiler_date="$3" DC="$4"
    for project in "${PROJECTS[@]}"; do
        bench_project "$compiler" "$sha" "$compiler_date" "$DC" "$project"
    done
}

run_buildkite_with_compiler_repo() {
    local compiler="$1" old_sha="$2" new_sha="$3" DC="$4"
    local old_date
    old_date=$(prepare_compiler "$compiler" "$old_sha")
    run_buildkite_with_compiler_date "$compiler" "$old_sha" "$old_date" "$DC"

    # Use old_date for the new compiler too, so both runs benchmark
    # the same project versions (old package sha + new compiler sha).
    prepare_compiler "$compiler" "$new_sha" >/dev/null
    run_buildkite_with_compiler_date "$compiler" "$new_sha" "$old_date" "$DC"
}

#-------------------------------------------------------------------------------
# Report generation
#-------------------------------------------------------------------------------

emit_table_section() {
    local title="$1" compiler="$2" old_sha="$3" new_sha="$4"
    {
        echo "## $title"
        echo
        echo "- Non-template $compiler commit: $old_sha"
        echo "- Template $compiler commit: $new_sha"
        echo
        echo "| Project | Non-template avg time (s) | Non-template std dev | Template avg time (s) | Template std dev | Time difference % |"
        echo "|:--------|:----------------:|:-----------:|:----------------:|:-----------:|:-----------------:|"
        for project in "${PROJECTS[@]}"; do
            local old_v new_v
            old_v="${RESULTS[${compiler}|${old_sha}|${project}]:-N/A	N/A}"
            new_v="${RESULTS[${compiler}|${new_sha}|${project}]:-N/A	N/A}"
            local old_avg old_sd new_avg new_sd
            IFS=$'\t' read -r old_avg old_sd <<<"$old_v"
            IFS=$'\t' read -r new_avg new_sd <<<"$new_v"

            local diff="N/A"
            if [[ "$old_avg" != "N/A" && "$new_avg" != "N/A" ]]; then
                diff=$(awk -v o="$old_avg" -v n="$new_avg" \
                    'BEGIN{ if (o==0) {print "N/A"} else {printf "%+.2f", (n-o)/o*100} }')
                [[ "$diff" != "N/A" ]] && diff="${diff}%"
            fi
            echo "| $project | $old_avg | $old_sd | $new_avg | $new_sd | $diff |"
        done
        echo
    }
}

emit_report() {
    {
        echo "# Buildkite Project Performance Report"
        echo
        echo "_Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')_"
        echo "_Iterations per project: ${NUM_ITERATIONS}_"
        echo
        emit_table_section "DMD Benchmarks" dmd "$OLD_DMD_COMMIT" "$NEW_DMD_COMMIT"
        emit_table_section "LDC Benchmarks" ldc "$OLD_LDC_COMMIT" "$NEW_LDC_COMMIT"
        emit_table_section "GDC Benchmarks" gdc "$OLD_GDC_COMMIT" "$NEW_GDC_COMMIT"
        echo "Errors logged to: $ERROR_LOG"
    } > "$REPORT_FILE"
    log "Report written to $REPORT_FILE"
}

# Write a CSV consumed by plot_results.py.
# Format: compiler,project,old_avg,old_sd,new_avg,new_sd,diff_pct
emit_csv() {
    local compiler="$1" old_sha="$2" new_sha="$3"
    for project in "${PROJECTS[@]}"; do
        local old_v new_v
        old_v="${RESULTS[${compiler}|${old_sha}|${project}]:-N/A\tN/A}"
        new_v="${RESULTS[${compiler}|${new_sha}|${project}]:-N/A\tN/A}"
        local old_avg old_sd new_avg new_sd
        IFS=$'\t' read -r old_avg old_sd <<<"$old_v"
        IFS=$'\t' read -r new_avg new_sd <<<"$new_v"

        local diff="N/A"
        if [[ "$old_avg" != "N/A" && "$new_avg" != "N/A" ]]; then
            diff=$(awk -v o="$old_avg" -v n="$new_avg" \
                'BEGIN{ if (o==0) {print "N/A"} else {printf "%.2f", (n-o)/o*100} }')
        fi
        echo "$compiler,$project,$old_avg,$old_sd,$new_avg,$new_sd,$diff"
    done
}

emit_csv_file() {
    {
        emit_csv dmd "$OLD_DMD_COMMIT" "$NEW_DMD_COMMIT"
        emit_csv ldc "$OLD_LDC_COMMIT" "$NEW_LDC_COMMIT"
        emit_csv gdc "$OLD_GDC_COMMIT" "$NEW_GDC_COMMIT"
    } > "$CSV_FILE"
    log "CSV written to $CSV_FILE"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    log "NUM_ITERATIONS=$NUM_ITERATIONS"
    log "DMD repo: $DMD_REPO_PATH  (binary: $DMD_COMPILER_PATH)"
    log "LDC repo: $LDC_REPO_PATH  (binary: $LDC_COMPILER_PATH)"
    log "GDC repo: $GDC_REPO_PATH  (binary: $GDC_COMPILER_PATH)"
    log "Projects dir: $PROJECTS_DIR"
    log "Results dir : $RESULTS_DIR"

    if [[ ! -d "$DMD_REPO_PATH/.git" ]]; then
        err "DMD repo missing at $DMD_REPO_PATH; run setup_environment.sh first"
        exit 1
    fi
    if [[ ! -d "$LDC_REPO_PATH/.git" ]]; then
        err "LDC repo missing at $LDC_REPO_PATH; run setup_environment.sh first"
        exit 1
    fi
    if [[ ! -d "$GDC_REPO_PATH/.git" ]]; then
        err "GDC repo missing at $GDC_REPO_PATH; run setup_environment.sh first"
        exit 1
    fi

    run_buildkite_with_compiler_repo dmd "$OLD_DMD_COMMIT" "$NEW_DMD_COMMIT" "$DMD_COMPILER_PATH"

    run_buildkite_with_compiler_repo ldc "$OLD_LDC_COMMIT" "$NEW_LDC_COMMIT" "$LDC_COMPILER_PATH"

    export GDC_REAL_PATH="$GDC_COMPILER_PATH"
    run_buildkite_with_compiler_repo gdc "$OLD_GDC_COMMIT" "$NEW_GDC_COMMIT" "$GDC_WRAPPER_PATH"

    emit_report
    emit_csv_file

    # Generate lollipop charts if matplotlib is available.
    if python3 -c 'import matplotlib' 2>/dev/null; then
        python3 "$SCRIPT_DIR/plot_results.py" "$CSV_FILE" --outdir "$RESULTS_DIR"
    else
        warn "matplotlib not installed - skipping chart generation"
    fi
}

main "$@"
