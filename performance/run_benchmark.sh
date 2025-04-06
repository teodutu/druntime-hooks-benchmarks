#! /bin/bash

if [ $# -ne 3 ] && [ $# -ne 2 ]; then
	echo "Use DMD to compile a benchmark to compare the performance of a hook."
	echo "Compare the performance of a given branch against master in case the branch hasn't been merged yet."
	echo -e "Alternatively, compare the performance of a given hook before and after its translation PR was merged.\n"
	echo "Usage: $0 <runtime_hook> <output_file> [branch_name]"
	exit 1
fi

declare -A HOOKS_TEMPLATE_COMMITS
HOOKS_TEMPLATE_COMMITS["_d_arraysetcapacity"]="b28d1dbdf6244f09b85a73b70a05a46580d42163"

declare -A HOOKS_NON_TEMPLATE_COMMITS
HOOKS_NON_TEMPLATE_COMMITS["_d_arraysetcapacity"]="3106359a2b9f206ef69917ccc10bb01f1ad807ca"

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
	commit_sha=$1;

    cd $DMD_PATH;
    commit_date=$(git show -s --format=%ci $commit_sha);

    git checkout $commit_sha;
    make clean &> /dev/null;
	make -j$(nproc) &> /dev/null;

	cd $PHOBOS_PATH;
    git checkout "master@{$commit_date}";
	make clean &> /dev/null;
	make -j$(nproc) &> /dev/null;

	libphobos2_a_bytes=$(stat -Lc %s generated/linux/release/64/libphobos2.a)
	libphobos2_so_bytes=$(stat -Lc %s generated/linux/release/64/libphobos2.so)

	echo "libphobos2.a size: $libphobos2_a_bytes B / $((libphobos2_a_bytes / 1024)) KiB / $((libphobos2_a_bytes / 1024 / 1024)) MiB"
	echo "libphobos2.so size: $libphobos2_so_bytes B / $((libphobos2_so_bytes / 1024)) KiB / $((libphobos2_so_bytes / 1024 / 1024)) MiB"
}

function test_commit() {
	sync_repos $1;

	cd $CRT_PATH;
	CFLAGS="-release -O -boundscheck=off -version=$HOOK -I$HOOK/";
	CC=~/dlang/dmd/generated/linux/release/64/dmd;

	# TODO: clean up
	# CFLAGS="$CFLAGS" CC=$CC make;
	$CC $CFLAGS array_benchmark.d;
	./array_benchmark >> $FILE;
}

function test_hook() {
	baseline_commit=$1;
	hook_commit=$2;

	cur_dmd_branch=$(get_current_branch $DMD_PATH);
	cur_phobos_branch=$(get_current_branch $PHOBOS_PATH);

	for i in {1..5}; do
		echo -e "\n============================================================" >> $FILE;
		echo "Testing non-template hook - Commit: ${baseline_commit}" >> $FILE;
		libphobos2_sizes=$(test_commit $baseline_commit | grep "libphobos2");
		echo "$libphobos2_sizes" >> $FILE;

		echo -e "\n============================================================" >> $FILE;
		echo "Testing template hook - Commit: ${hook_commit}" >> $FILE;
		libphobos2_sizes=$(test_commit $hook_commit | grep "libphobos2");
		echo "$libphobos2_sizes" >> $FILE;
	done

	restore_branch $DMD_PATH $cur_dmd_branch
	restore_branch $PHOBOS_PATH $cur_phobos_branch
}

if [ $HOOK_BRANCH != "" ]; then
	echo "branch";
	base_branch=${HOOKS_NON_TEMPLATE_COMMITS[$HOOK]:-"master"}
	test_hook $base_branch $HOOK_BRANCH
else
	echo "no branch";
	cd $DMD_PATH;
	git checkout master
	hook_commit=$(git log --grep="Translate $HOOK" | head -n 1 | cut -d ' ' -f 2);
	test_hook "$hook_commit^" $hook_commit;
fi

cd $CRT_PATH
make clean
