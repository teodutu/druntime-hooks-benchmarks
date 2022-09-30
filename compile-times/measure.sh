#!/bin/bash

if [[ $# -lt 1 ]]; then
    echo "Usage: ./measure.sh <package> [mode]";
    exit 1;
fi

CMD="dub build"
if [[ $# -eq 2 ]]; then
    CMD="${CMD} --compiler /usr/local/google/home/teodutu/work/dlang/dmd/generated/linux/release/64/dmd"
fi

echo $CMD

cd $1

min=10000
for i in {0..99}; do
    dub clean &> /dev/null;
    TIMEFORMAT=%R;
    t=$( { time $CMD; } 2>&1 )
    t=$(echo $t | rev | cut -d ' ' -f1 | rev)
    if (( $(echo "$min > $t" | bc -l) )); then
        min=$t;
        echo $min
    fi
done

echo $min
