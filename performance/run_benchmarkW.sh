#!/bin/bash

# Ditto for Windows

# Check for correct number of arguments
if [ $# -ne 2 ] && [ $# -ne 3 ]; then
    echo "Use DMD to compile a benchmark to compare the performance of a hook."
    echo "Compare the performance of a given branch against master in case the branch hasn't been merged yet."
    echo -e "Alternatively, compare the performance of a given hook before and after its translation PR was merged.\n"
    echo "Usage: $0 <runtime_hook> <output_file> [branch_name]"
    exit 1
fi

HOOK=$1
FILE=$2

if [ $# -eq 3 ]; then
    HOOK_BRANCH=$3
fi

# === Paths ===
DMD_PATH="/mnt/e/GSOC/source/dmd"
PHOBOS_PATH=$DMD_PATH/../phobos
CRT_PATH=$(pwd)

# Set host compiler (adjust this path according to your installation)
DMD_EXE="/mnt/e/GSOC/D/dmd2/windows/bin/dmd.exe"

# Function to sync repositories
function sync_repos() {
    commit_sha=$1

    cd "$DMD_PATH" || exit 1
    git checkout "$commit_sha" || exit 1

    echo "Cleaning DMD..."
    cd compiler/src || exit 1
    "$DMD_EXE" -run build.d clean || { echo "Failed to clean DMD"; exit 1; }

    echo "Building DMD..."
    "$DMD_EXE" -run build.d BUILD=release MODEL=64 || { echo "Failed to build DMD (64-bit)"; exit 1; }

    echo "DMD build done."

	# After building the new DMD, check if it exists and point HOST_DMD to it
	NEW_DMD_PATH="E:/GSOC/source/dmd/generated/windows/release/64/dmd.exe"

    echo "Cleaning and Building Phobos + Druntime..."
    cd "$PHOBOS_PATH" || exit 1

    make -f Makefile clean HOST_DMD="$NEW_DMD_PATH" || { echo "Failed to clean Phobos"; exit 1; }
    make -f Makefile BUILD=release OS=windows MODEL=64 HOST_DMD="$NEW_DMD_PATH" || { echo "Failed to build Phobos (64-bit)"; exit 1; }
}

# Function to test a commit
function test_commit() {
    sync_repos $1

    cd $CRT_PATH || exit 1
    CFLAGS="-release -O -boundscheck=off -version=$HOOK -I$HOOK/"

    # Compiler to use
    CC="$DMD_EXE"

    echo "Compiling benchmark..."
    $CC $CFLAGS array_benchmark.d || { echo "Compilation failed"; exit 1; }

    echo "Running benchmark..."
    ./array_benchmark.exe >> $FILE
}

# Function to test a hook
function test_hook() {
    baseline_commit=$1
    hook_commit=$2

    for i in {1..5}; do
        echo -e "\n============================================================" >> $FILE
        echo "Testing non-template hook (baseline)" >> $FILE
        test_commit $baseline_commit

        echo -e "\n============================================================" >> $FILE
        echo "Testing template hook (hook commit)" >> $FILE
        test_commit $hook_commit
    done
}

# === Hook Commit Setup ===

declare -A HOOKS_TEMPLATE_COMMITS
declare -A HOOKS_NON_TEMPLATE_COMMITS

# Provide known commits
HOOKS_TEMPLATE_COMMITS["_d_arrayappendcTX"]="d916b5396ee6b192ef311932de9bd9ecbe5857d1"  # Template commit (from PR)
HOOKS_NON_TEMPLATE_COMMITS["_d_arrayappendcTX"]="0b9850f366c47c8cadd01b173d54d84c3d28b208"  # Baseline (master)

# === Run ===

if [ -n "$HOOK_BRANCH" ]; then
    echo "Branch provided: $HOOK_BRANCH"
    echo "Comparing master vs branch..."

    cd $DMD_PATH || exit 1
    git fetch origin || exit 1
    git checkout master || exit 1

    baseline_commit=${HOOKS_NON_TEMPLATE_COMMITS[$HOOK]}
    hook_commit="origin/$HOOK_BRANCH"

    test_hook $baseline_commit $hook_commit
else
    echo "No branch provided, using specific commits"
    cd $DMD_PATH || exit 1
    git checkout master || exit 1

    baseline_commit=${HOOKS_NON_TEMPLATE_COMMITS[$HOOK]}
    hook_commit=${HOOKS_TEMPLATE_COMMITS[$HOOK]}

    if [ -z "$hook_commit" ] || [ -z "$baseline_commit" ]; then
        echo "Error: Missing commit hashes for hook $HOOK"
        exit 1
    fi

    test_hook $baseline_commit $hook_commit
fi

# === Cleanup ===
cd $CRT_PATH
make clean
