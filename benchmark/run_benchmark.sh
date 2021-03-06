#! /bin/bash

if [[ $# -ne 3 ]]; then
	echo "Use DMD to compile a benchmark to compare the performance of a hook (on a given branch) against the master."
	echo "Usage: $0 <runtime_hook> <branch_name> <output_file>"
	exit 1
fi

HOOK=$1
HOOK_BRANCH=$2
FILE=$3	

DMD_PATH=~/dlang/dmd
CRT_PATH=$(pwd)

source $DMD_PATH-2.099.1/activate

function run_on_branch() {
	BRANCH=$1

	echo -e "\n============================================================" >> $FILE;
	echo "Testing branch: $BRANCH" >> $FILE;

	cd $DMD_PATH;
	git checkout $BRANCH;
	make -f posix.mak;

	cd $CRT_PATH;
	CFLAGS="-release -O -boundscheck=off -version=$HOOK -I$HOOK/";
	CC=~/dlang/dmd/generated/linux/release/64/dmd;

	# TODO: clean up
	# CFLAGS="$CFLAGS" CC=$CC make;
	$CC $CFLAGS array_benchmark.d;
	./array_benchmark >> $FILE;
}

for i in {1..1000}; do
	run_on_branch $HOOK_BRANCH;
	run_on_branch "master";
done

cd $CRT_PATH
make clean
