#! /bin/bash

if [ $# -ne 3 ] && [ $# -ne 2 ]; then
	echo "Use DMD to compile a benchmark to compare the performance of a hook."
	echo "Compare the performance of a given branch against master in case the branch hasn't been merged yet."
	echo -e "Alternatively, compare the performance of a given hook before and after its translation PR was merged.\n"
	echo "Usage: $0 <runtime_hook> <output_file> [branch_name]"
	exit 1
fi

# Used for storing and handling the output of the benchmarks
NT_BENCH_OUTPUT=""
T_BENCH_OUTPUT=""

HOOK=$1
RESULTS_FILE=$2
if [[ "$2" = /* ]]; then
	RESULTS_FILE=$2
else
	RESULTS_FILE="$PWD/$2"
fi
CRT_PATH=$PWD

BASE_DIR=$(realpath ~/src/dlang)
D_COMPILER=${D_COMPILER:-dmd}
DC_PATH="$BASE_DIR/$D_COMPILER"

case $D_COMPILER in
dmd)
	DC=$DC_PATH/generated/linux/release/64/dmd
	DC_FLAGS="-release -O -boundscheck=off -version=$HOOK -I$HOOK/"
	PHOBOS_PATH=$BASE_DIR/phobos
	declare -n TEMPLATED_COMMIT=DMD_TEMPLATED_COMMIT
	declare -n NON_TEMPLATED_COMMIT=DMD_NON_TEMPLATED_COMMIT
	;;
gdc)
	echo "GDC is not supported"
	exit 1
	;;
ldc)
	DC=$DC_PATH/build/bin/ldc2
	DC_FLAGS="--release -O3 --boundscheck=off --d-version=$HOOK -I$HOOK/"
	PHOBOS_PATH=$DC_PATH/runtime/phobos
	declare -n TEMPLATED_COMMIT=LDC_TEMPLATED_COMMIT
	declare -n NON_TEMPLATED_COMMIT=LDC_NON_TEMPLATED_COMMIT
	;;
*)
	echo "Unknown D compiler: $D_COMPILER"
	exit 1
	;;
esac

source ./hook_commits.sh

declare -A druntime_a_size
declare -A phobos2_a_size
declare -A phobos2_so_size

if [[ $# -eq 3 ]]; then
	HOOK_BRANCH=$3
elif [[ -v TEMPLATED_COMMIT[$HOOK] ]]; then
	HOOK_BRANCH=${TEMPLATED_COMMIT[$HOOK]}
fi

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
	pushd $git_path >/dev/null
	cur_branch=$(git rev-parse --abbrev-ref HEAD)
	popd >/dev/null
	echo $cur_branch
}

function restore_branch() {
	git_path=$1
	cur_branch=$2
	pushd $git_path >/dev/null
	git checkout -f $cur_branch
	git submodule update --init
	popd >/dev/null
}

function sync_repos() {
	commit_sha=$1
	skip_phobos=${2:-false}

	pushd $DC_PATH >/dev/null

	case $D_COMPILER in
	dmd)
		commit_date=$(git show -s --format=%ci $commit_sha)
		git checkout $commit_sha
		make clean &>/dev/null

		if [[ $skip_phobos == false ]]; then
			pushd $PHOBOS_PATH >/dev/null
			git checkout $(git rev-list -n 1 --before="$commit_date" master)
			make clean &>/dev/null
			make -j$(nproc) &>/dev/null
			popd >/dev/null

			druntime_a_path=$DC_PATH/generated/linux/release/64/libdruntime.a
			libphobos2_a_path=$PHOBOS_PATH/generated/linux/release/64/libphobos2.a
			libphobos2_so_path=$PHOBOS_PATH/generated/linux/release/64/libphobos2.so
		fi
		make -j$(nproc) &>/dev/null

		;;
	gdc)
		git checkout $commit_sha
		;;
	ldc)
		rm -r runtime
		git reset --hard HEAD
		git checkout -f $commit_sha
		git submodule update --init &>/dev/null

		rm -r build &>/dev/null
		mkdir build
		cmake -S . -B build &>/dev/null

		cd build
		make clean &>/dev/null
		make -j$(nproc) ldc2
		if [[ $skip_phobos == false ]]; then
			make -C runtime -j$(nproc) druntime-ldc phobos2-ldc phobos2-ldc-shared &>/dev/null
			druntime_a_path=$PWD/lib/libdruntime-ldc.a
			libphobos2_a_path=$PWD/lib/libphobos2-ldc.a
			libphobos2_so_path=$PWD/lib/libphobos2-ldc-shared.so
		fi

		;;
	esac

	if [[ $skip_phobos == false ]]; then
		druntime_a_bytes=$(stat -Lc %s "$druntime_a_path")
		set_if_unset druntime_a_size "$commit_sha" "$druntime_a_bytes"

		libphobos2_a_bytes=$(stat -Lc %s "$libphobos2_a_path")
		set_if_unset phobos2_a_size "$commit_sha" "$libphobos2_a_bytes"

		libphobos2_so_bytes=$(stat -Lc %s "$libphobos2_so_path")
		set_if_unset phobos2_so_size "$commit_sha" "$libphobos2_so_bytes"
	fi

	popd >/dev/null
}

function test_commit() {
	declare -n out_var=$1
	sync_repos $2

	pushd $CRT_PATH >/dev/null
	$DC $DC_FLAGS array_benchmark.d
	out_var=$(./array_benchmark)

	popd >/dev/null
}

function compilation_bench() {
	commit_sha=$1

	sync_repos $commit_sha true

	case $D_COMPILER in
	dmd)
		pushd $PHOBOS_PATH >/dev/null
		compile_bench_command="make clean && make $DC_PATH/druntime clean && make -j$(nproc)"
		;;
	gdc) ;;
	ldc)
		pushd $DC_PATH/build/runtime >/dev/null
		compile_bench_command="make clean && make -j$(nproc) druntime-ldc phobos2-ldc"
		;;
	esac

	perf_out=$(perf stat -r 100 bash -c "($compile_bench_command) &>/dev/null" 2>&1 | tail -n2 | head -n1)

	popd >/dev/null

	avg_time=$(echo $perf_out | awk '{print $1}')
	stddev=$(echo $perf_out | awk '{print $3}')
	stddev_percent=$(echo $perf_out | awk '{print $(NF-1)}')

	echo "Average time: $avg_time seconds, Standard deviation: $stddev (+- $stddev_percent) seconds" >>$RESULTS_FILE
}

function compute_percentage_change() {
	old_value=$1
	new_value=$2

	if [[ $(awk -v ov="$old_value" "BEGIN {print (ov == 0)}") -eq 1 ]]; then
		echo "N/A"
		return
	fi

	change=$(awk "BEGIN {printf \"%.2f\", (($new_value - $old_value) / $old_value) * 100}")
	echo "$change%"
}

function print_templated_bench_output() {
	readarray -t nt_lines <<<$NT_BENCH_OUTPUT
	readarray -t t_lines <<<$T_BENCH_OUTPUT

	local out="${t_lines[0]},diff (ms),diff (%)"

	for i in $(seq 1 $((${#t_lines[@]} - 1))); do
		local nt_time=$(echo "${nt_lines[$i]}" | cut -d, -f3)
		local t_line=${t_lines[$i]}
		local t_time=$(echo "$t_line" | cut -d, -f3)

		local diff=$(awk -v nt="$nt_time" -v t="$t_time" 'BEGIN {printf "%.2f", (t - nt)}')
		local diff_pct=$(compute_percentage_change $nt_time $t_time)
		out+=$'\n'"${t_line},$diff,$diff_pct"
	done

	printf "%s\n" "$out" | column -t -s, -o" | " >>$RESULTS_FILE
}

function test_hook() {
	baseline_commit=$1
	hook_commit=$2

	cur_dmd_branch=$(get_current_branch $DC_PATH)
	if [[ $D_COMPILER == "dmd" ]]; then
		cur_phobos_branch=$(get_current_branch $PHOBOS_PATH)
	fi

	for i in {1..5}; do
		echo -e "\n============================================================" >>$RESULTS_FILE
		echo "Testing non-template hook - Commit: ${baseline_commit}" >>$RESULTS_FILE
		test_commit NT_BENCH_OUTPUT $baseline_commit
		printf "%s\n" "$NT_BENCH_OUTPUT" | column -t -s, -o" | " >>$RESULTS_FILE

		echo -e "\n============================================================" >>$RESULTS_FILE
		echo "Testing template hook - Commit: ${hook_commit}" >>$RESULTS_FILE
		test_commit T_BENCH_OUTPUT $hook_commit
		print_templated_bench_output
	done

	echo -e "\n============================================================" >>$RESULTS_FILE
	echo "Compilation performance non-template hook - Commit: ${baseline_commit}" >>$RESULTS_FILE
	compilation_bench $baseline_commit

	echo -e "\n============================================================" >>$RESULTS_FILE
	echo "Compilation performance template hook - Commit: ${hook_commit}" >>$RESULTS_FILE
	compilation_bench $hook_commit

	druntime_a_size_old=${druntime_a_size[$baseline_commit]}
	druntime_a_size_new=${druntime_a_size[$hook_commit]}

	phobos2_a_size_old=${phobos2_a_size[$baseline_commit]}
	phobos2_a_size_new=${phobos2_a_size[$hook_commit]}

	phobos2_so_size_old=${phobos2_so_size[$baseline_commit]}
	phobos2_so_size_new=${phobos2_so_size[$hook_commit]}

	echo -e "\n============================================================" >>$RESULTS_FILE
	local lib_out="lib name,old size (B),new size (B),diff (%)"
	lib_out+=$'\n'"libdruntime.a,$druntime_a_size_old,$druntime_a_size_new,$(compute_percentage_change $druntime_a_size_old $druntime_a_size_new)"
	lib_out+=$'\n'"libphobos2.a,$phobos2_a_size_old,$phobos2_a_size_new,$(compute_percentage_change $phobos2_a_size_old $phobos2_a_size_new)"
	lib_out+=$'\n'"libphobos2.so,$phobos2_so_size_old,$phobos2_so_size_new,$(compute_percentage_change $phobos2_so_size_old $phobos2_so_size_new)"

	printf "%s\n" "$lib_out" | column -t -s, -o" | " >>$RESULTS_FILE

	if [[ $D_COMPILER == "ldc" ]]; then
		pushd $DC_PATH >/dev/null
		rm -r runtime
		git reset --hard HEAD
	fi
	restore_branch $DC_PATH $cur_dmd_branch
	if [[ $D_COMPILER == "dmd" ]]; then
		restore_branch $PHOBOS_PATH $cur_phobos_branch
	fi
}

if [ $HOOK_BRANCH != "" ]; then
	echo "branch"
	base_branch=${NON_TEMPLATED_COMMIT[$HOOK]}
	if [[ $base_branch == "" ]]; then
		echo "Non-template commit hash for hook '$HOOK' not found."
		exit 1
	fi
	test_hook $base_branch $HOOK_BRANCH
else
	echo "no branch -> unsupported"
	exit 1
	# cd $DMD_PATH
	# git checkout master
	# hook_commit=$(git log --grep="Translate $HOOK" | head -n 1 | cut -d ' ' -f 2)
	# test_hook "$hook_commit^" $hook_commit
fi

cd $CRT_PATH
make clean
