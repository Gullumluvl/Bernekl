#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'

help="Usage:
parts.sh <file to split> <n parts> [<n header lines>]
"

infile=${1}
nparts=${2}
hlines=${3:-0}

fileroot="${infile%.*}"
fileext="${infile##*.}"

echo "'$fileroot' . '$fileext'"

split -n "l/$nparts" --additional-suffix=".$fileext" --numeric-suffixes=1 "$infile" "${fileroot}-part"

if (( hlines )); then
    for ((i=2; i<=$nparts; i++)); do
        part=$(printf "part%02d" ${i})
        sed -i '1e head -n '"$hlines"' '"${fileroot}-part01.${fileext}"'' "${fileroot}-${part}.${fileext}"
    done
fi
