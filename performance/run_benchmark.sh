#! /bin/bash

if [ $# -ne 3 ] && [ $# -ne 2 ]; then
	echo "Use DMD to compile a benchmark to compare the performance of a hook."
	echo "Compare the performance of a given branch against master in case the branch hasn't been merged yet."
	echo -e "Alternatively, compare the performance of a given hook before and after its translation PR was merged.\n"
	echo "Usage: $0 <runtime_hook> <output_file> [branch_name]"
	exit 1
fi

HOOK=$1
FILE=$2
if [[ $# -ne 3 ]]; then
	HOOK_BRANCH=$3
fi

DMD_PATH=~/dlang/dmd
PHOBOS_PATH=$DMD_PATH/../phobos
CRT_PATH=$(pwd)

DMD_DIR=$(find $DMD_PATH/.. -maxdepth 1 -type d -name "dmd-2.*")
source $DMD_DIR/activate

function sync_repos() {
	commit_sha=$1;

    cd $DMD_PATH;
    commit_date=$(git show -s --format=%ci $commit_sha);

    git checkout $commit_sha;
    make -f posix.mak clean &> /dev/null;
	make -f posix.mak -C compiler/src -j8 &> /dev/null;

	cd $PHOBOS_PATH;
    git checkout "master@{$commit_date}";
	make -f posix.mak clean &> /dev/null;
	make -f posix.mak -j8 &> /dev/null;
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

	for i in {1..5}; do
		echo -e "\n============================================================" >> $FILE;
		echo "Testing non-template hook" >> $FILE;
		test_commit $baseline_commit;

		echo -e "\n============================================================" >> $FILE;
		echo "Testing template hook" >> $FILE;
		test_commit $hook_commit;
	done
}

if [[ $HOOK_BRANCH -ne "" ]]; then
	echo "branch";
	test_hook "master" $HOOK_BRANCH
else
	echo "no branch";
	cd $DMD_PATH;
	git checkout master
	hook_commit=$(git log --grep=$HOOK | head -n 1 | cut -d ' ' -f 2);
	test_hook "$hook_commit^" $hook_commit;
fi

cd $CRT_PATH
make clean
