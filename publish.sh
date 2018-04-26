#!/bin/bash

set -euo pipefail

destfile="$1" || echo "Missing arguments: <destfile> [<pandoc options> ...]" >&2
shift

basefilename="${destfile%.*}"
# pandoc version > 2.0:
# extension "smart" and "fenced_code_attributes" enabled by default.

for ext in "mkd" "md" "markdown" "txt"; do
    if [ -f "$basefilename.$ext" ]; then
        pandoc \
            --from=markdown \
            -c css/buttondown.css \
            --lua-filter=task-list.lua \
            --standalone \
            $@ \
            -o "$destfile" "$basefilename.$ext"
        break
    fi
done
