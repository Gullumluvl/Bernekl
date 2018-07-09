#!/bin/bash

set -euo pipefail

### Read command line arguments
options=()
destfile="-"

while [[ "$destfile" =~ ^-.* ]]; do
    [ "$destfile" != "-" ] && options+=("$destfile")
    
    destfile="$1" || {
        echo "Missing arguments: <destfile> [<pandoc options> ...]" >&2;
        exit 1;
    }
    shift
done

options+=($@)

### Infer input file and convert

basefilename="${destfile%.*}"

# pandoc version > 2.0:
# extension "smart" and "fenced_code_attributes" enabled by default.

done=0

for ext in "mkd" "md" "markdown" "txt"; do
    if [ -f "$basefilename.$ext" ]; then
        if [ "$destfile" = "$basefilename.$ext" ]; then
            echo "Destination file equals the source file: $destfile. Aborting." >&2
            exit 1
        fi
        pandoc \
            --from=markdown \
            -c $HOME/.pandoc/styles/buttondown.css \
            --filter=pandoc-mustache \
            --lua-filter=task-list.lua \
            --standalone \
            ${options[@]:-} \
            -o "$destfile" "$basefilename.$ext"
        done=1
        break
    fi
done

(( "$done" )) || { echo "Error: no source file was found!"; exit 1;}
