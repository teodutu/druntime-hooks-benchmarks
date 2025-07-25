#! /bin/bash

if [ $# -ne 3 ] && [ $# -ne 2 ]; then
	echo "Use DMD to compile a benchmark to compare the performance of a hook."
	echo "Compare the performance of a given branch against master in case the branch hasn't been merged yet."
	echo -e "Alternatively, compare the performance of a given hook before and after its translation PR was merged.\n"
	echo "Usage: $0 <runtime_hook> <output_file> [branch_name]"
	exit 1
fi

declare -A HOOKS_TEMPLATE_COMMITS
HOOKS_TEMPLATE_COMMITS["_d_arraysetcapacity"]="master"
HOOKS_TEMPLATE_COMMITS["_d_dynamic_cast"]="47c7321477ae8d97f881efa6a3de360da4f4a6d3"
HOOKS_TEMPLATE_COMMITS["_d_paint_cast"]="9e7f0af277b7762efa6ae1a3a35a0b6cb7257d17"
HOOKS_TEMPLATE_COMMITS["_d_class_cast"]="e0f222194cd412f71b2b4eabfef966f90849ce36"
HOOKS_TEMPLATE_COMMITS["_d_interface_cast"]="6e8eb081cfa3cb58f1b308cb290ca8f364666cfd"
HOOKS_TEMPLATE_COMMITS["_adEq2_equals"]="ad35200fe3bb6b7f6a9e08bd2d83bc4857cd441e"
HOOKS_TEMPLATE_COMMITS["_adEq2_memcmp"]="ad35200fe3bb6b7f6a9e08bd2d83bc4857cd441e"
HOOKS_TEMPLATE_COMMITS["__equals_memcmp"]="ad35200fe3bb6b7f6a9e08bd2d83bc4857cd441e"
HOOKS_TEMPLATE_COMMITS["_d_arrayliteralTX"]="c2c8189599b894771393100ceae1ca2da30202d0"

declare -A HOOKS_NON_TEMPLATE_COMMITS
HOOKS_NON_TEMPLATE_COMMITS["_d_arraysetcapacity"]="master"
HOOKS_NON_TEMPLATE_COMMITS["_d_dynamic_cast"]="99a390f3c6bae3b30c469222a9846273d300c407"
HOOKS_NON_TEMPLATE_COMMITS["_d_paint_cast"]="8762d1eaee42119269b82a1b1b7063c89c1e6a69"
HOOKS_NON_TEMPLATE_COMMITS["_d_class_cast"]="d234a544f13ee7293fc8108a0aba29685ae1ac38"
HOOKS_NON_TEMPLATE_COMMITS["_d_interface_cast"]="9f573c494acc38855027462bde162fabea9cf33f"
HOOKS_NON_TEMPLATE_COMMITS["_adEq2_equals"]="e0cf19144f2afed531cc2f40eee7e051994d4e98"
HOOKS_NON_TEMPLATE_COMMITS["_adEq2_memcmp"]="e0cf19144f2afed531cc2f40eee7e051994d4e98"
HOOKS_NON_TEMPLATE_COMMITS["__equals_memcmp"]="e0cf19144f2afed531cc2f40eee7e051994d4e98"
HOOKS_NON_TEMPLATE_COMMITS["_d_arrayliteralTX"]="9749967b599870b2fdeb2744a3003e5cddf16242"

declare -A druntime_a_size
declare -A phobos2_a_size
declare -A phobos2_so_size

HOOK=$1
FILE=$2
if [[ $# -eq 3 ]]; then
	HOOK_BRANCH=$3
elif [[ -v HOOKS_TEMPLATE_COMMITS[$HOOK] ]]; then
	HOOK_BRANCH=${HOOKS_TEMPLATE_COMMITS[$HOOK]}
fi

DMD_PATH=~/dlang/dmd
PHOBOS_PATH=$DMD_PATH/../phobos
CRT_PATH=$(pwd)

DMD_DIR=$(find $DMD_PATH/.. -maxdepth 1 -type d -name "dmd-2.*")
source $DMD_DIR/activate

function set_if_unset() {
	local -n map_name=$1
	key=$2
	value=$3

	if [[ -z ${!map_name[$key]} ]]; then
		map_name[$key]=$value
	fi
}

function get_current_branch() {
	git_path=$1
	cd $git_path
	cur_branch=$(git rev-parse --abbrev-ref HEAD)
	echo $cur_branch
}

function restore_branch() {
	git_path=$1
	cur_branch=$2
	cd $git_path
	git checkout $cur_branch
}

function sync_repos() {
	commit_sha=$1
	skip_phobos=${2:-false}

	cd $DMD_PATH
	commit_date=$(git show -s --format=%ci $commit_sha)

	git checkout $commit_sha
	make clean &>/dev/null
	make -j$(nproc) &>/dev/null

	druntime_a_bytes=$(stat -Lc %s generated/linux/release/64/libdruntime.a)
	set_if_unset druntime_a_size "$commit_sha" "$druntime_a_bytes"

	cd $PHOBOS_PATH
	git checkout $(git rev-list -n 1 --before="$commit_date" master)
	make clean &>/dev/null

	if [[ $skip_phobos == true ]]; then
		return
	fi

	make -j$(nproc) &>/dev/null

	libphobos2_a_bytes=$(stat -Lc %s generated/linux/release/64/libphobos2.a)
	set_if_unset phobos2_a_size "$commit_sha" "$libphobos2_a_bytes"

	libphobos2_so_bytes=$(stat -Lc %s generated/linux/release/64/libphobos2.so)
	set_if_unset phobos2_so_size "$commit_sha" "$libphobos2_so_bytes"
}

function test_commit() {
	sync_repos $1

	cd $CRT_PATH
	CFLAGS="-release -O -boundscheck=off -version=$HOOK -I$HOOK/"
	CC=$DMD_PATH/generated/linux/release/64/dmd

	# TODO: clean up
	# CFLAGS="$CFLAGS" CC=$CC make;
	$CC $CFLAGS array_benchmark.d
	./array_benchmark >>$FILE
}

function compilation_bench() {
	commit_sha=$1

	sync_repos $commit_sha true

	cd $PHOBOS_PATH

	perf_out=$(perf stat -r 100 bash -c "(make clean && make $DMD_PATH/druntime clean && make -j$(nproc)) &>/dev/null" 2>&1 | tail -n2 | head -n1)

	avg_time=$(echo $perf_out | awk '{print $1}')
	stddev=$(echo $perf_out | awk '{print $3}')
	stddev_percent=$(echo $perf_out | awk '{print $(NF-1)}')

	cd $CRT_PATH
	echo "Average time: $avg_time seconds, Standard deviation: $stddev (+- $stddev_percent) seconds" >>$FILE
}

function compute_percentage_change() {
	old_value=$1
	new_value=$2

	if [[ $old_value -eq 0 ]]; then
		echo "N/A"
		return
	fi

	change=$(awk "BEGIN {printf \"%.2f\", (($new_value - $old_value) / $old_value) * 100}")
	echo "$change%"
}

function test_hook() {
	baseline_commit=$1
	hook_commit=$2

	cur_dmd_branch=$(get_current_branch $DMD_PATH)
	cur_phobos_branch=$(get_current_branch $PHOBOS_PATH)

	for i in {1..5}; do
		echo -e "\n============================================================" >>$FILE
		echo "Testing non-template hook - Commit: ${baseline_commit}" >>$FILE
		test_commit $baseline_commit

		echo -e "\n============================================================" >>$FILE
		echo "Testing template hook - Commit: ${hook_commit}" >>$FILE
		test_commit $hook_commit
	done

	echo -e "\n============================================================" >>$FILE
	echo "Compilation performance non-template hook - Commit: ${baseline_commit}" >>$FILE
	compilation_bench $baseline_commit

	echo -e "\n============================================================" >>$FILE
	echo "Compilation performance template hook - Commit: ${hook_commit}" >>$FILE
	compilation_bench $hook_commit

	druntime_a_size_old=${druntime_a_size[$baseline_commit]}
	druntime_a_size_new=${druntime_a_size[$hook_commit]}

	phobos2_a_size_old=${phobos2_a_size[$baseline_commit]}
	phobos2_a_size_new=${phobos2_a_size[$hook_commit]}

	phobos2_so_size_old=${phobos2_so_size[$baseline_commit]}
	phobos2_so_size_new=${phobos2_so_size[$hook_commit]}

	echo -e "\n============================================================" >>$FILE
	echo "libdruntime.a size: old=${druntime_a_size_old} B / new=${druntime_a_size_new} B => $(compute_percentage_change $druntime_a_size_old $druntime_a_size_new) change" >>$FILE
	echo "libphobos2.a size: old=${phobos2_a_size_old} B / new=${phobos2_a_size_new} B => $(compute_percentage_change $phobos2_a_size_old $phobos2_a_size_new) change" >>$FILE
	echo "libphobos2.so size: old=${phobos2_so_size_old} B / new=${phobos2_so_size_new} B => $(compute_percentage_change $phobos2_so_size_old $phobos2_so_size_new) change" >>$FILE

	restore_branch $DMD_PATH $cur_dmd_branch
	restore_branch $PHOBOS_PATH $cur_phobos_branch
}

if [ $HOOK_BRANCH != "" ]; then
	echo "branch"
	base_branch=${HOOKS_NON_TEMPLATE_COMMITS[$HOOK]:-"master"}
	test_hook $base_branch $HOOK_BRANCH
else
	echo "no branch"
	cd $DMD_PATH
	git checkout master
	hook_commit=$(git log --grep="Translate $HOOK" | head -n 1 | cut -d ' ' -f 2)
	test_hook "$hook_commit^" $hook_commit
fi

cd $CRT_PATH
make clean
