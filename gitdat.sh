#!/bin/bash

set -eu
IFS=$'\t\n'


help="USAGE: $0 <command> [<args> ...].

<args> can be taken from stdin (one per line).


COMMANDS:

- help
- untracked - list files not in the index
- find      - find all files whose name matches the given pattern, and tell if
              it is tracked in git, in rsync, or untracked.
              Supports all grep options.
- findsame  - find all files with the same basename: list extensions (colored).
- track
- untrack
- rm        - untrack and remove the file.
- [push]
- [pull]
- [log]


COLOR CODES:

green=git-tracked
purple=rsync-tracked
none=untracked


EXAMPLES:

# Useful command to see if untracked files have tracked source files
# (same basename, different extension):

    gitdat.sh untracked | gitdat.sh findsame

# Only print 'forgotten' files: no source nor output is tracked:

    gitdat.sh untracked | gitdat.sh findsame | grep -v \$'\\x1b\\[0'
"


if [[ $# -eq 0 ]] || [[ "$1" =~ ^(help|--help|-h|-\?)$ ]]; then
    echo "$help"
    exit
fi

#untracked
#exit 0

#echo "DEBUG: checking arguments" >&2

action=$1
shift

if [[ -t 0 ]]; then
    arglist=($@)
else
    while IFS= read -r line; do
        arglist+=("${line}")
    done
fi


trackfile="gitdata.index"
ignorefile="gitdata.ignore"

[[ -f "$trackfile" ]] || { echo "trackfile '$trackfile' does not exists." >&2 ; exit 1 ; }


#echo "DEBUG: define functions." >&2

untracked() {
    #echo "Untracked files:" >&2
    find . ! -type d -printf "%p\n" \
        | grep -vf "$ignorefile" \
        | fgrep -vwf <( git ls-files --full-name | sed 's_^_./_' ) \
        | fgrep -vwf $trackfile
}

#echo "DEBUG: 1 func defined." >&2

track() {
    for arg in $@; do
        if fgrep -wq "$arg" $trackfile; then
            echo "Already tracked: $arg" >&2
            #return 1
        elif git ls-files --full-name | sed 's_^_./_' | fgrep -wq "$arg" ; then
            echo 'Already version-controled (use `git rm --cached` first): '"$arg" >&2
        else
            echo "$arg" >> $trackfile
        fi
    done
}

untrack() {
    for arg in $@; do
        if fgrep -wq "$arg" $trackfile; then
            lineno="$( fgrep -wn "$arg" $trackfile | cut -d':' -f1 )"
            sed -i "${lineno}d"
        else
            echo "NOT tracked: $arg" >&2
            #return 1
        fi
    done
}

trackrm() {
    rm -v $@ || true
    untrack $@
}

RED="\e[00;31m"
BRED="\e[01;31m"
GREEN="\e[00;32m"
YELLOW="\e[00;33m"
BLUE="\e[00;34m"
PURPLE="\e[00;35m"
CYAN="\e[00;36m"
RESET="\e[00;00m"
#BOLD="\e[00;01m"
BGREY="\e[01;30m"
ITAL="\e[00;03m"


trackfind() {
    git ls-files --full-name | sed 's_^_./_' | grep --color=always $@ | sed 's/^/git:/'
    nogit=${PIPESTATUS[2]}

    grep --color=always $@ "$trackfile" | sed 's/^/track:/'
    notrack=${PIPESTATUS[0]}

    #if (( $nogit && $notrack )) ; then
    untracked | grep --color=always $@ | sed 's/^/local untracked:/'
    nofile=${PIPESTATUS[1]}
    #fi

    if (( $nogit && $notrack && $nofile )); then return 1; fi

}
#trackpush() {}
#trackpull() {}
#log() {}

findsame() {
    for arg in $@; do
        dir=$(dirname $arg)
        base=$(basename $arg)
        if [[ "$base" = *.* ]]; then
            name="${base%.*}"
            ext=".${base##*.}"
        else
            continue
            #name="$base"
            #ext=""
        fi

        #if [[ $arg =~ showork/jobim ]]; then echo "DEBUG: base='$base' ext='$ext'" >&2 && break; fi
        other_ext=()
        echo -ne "$arg:\t"
        for same in "$dir/${name}".*; do
            #echo "DEBUG: same=$same" >&2
            if ! grep -qf "$ignorefile" <<<"$same" && ! [[ -d "$same" ]] && ! [[ "$same" -ef "$arg" ]]; then
                # Find if this other file is tracked/versioned:
                status="$(trackfind -xF "$same" | cut -d':' -f1)"
                case "$status" in
                    git) col=$GREEN ;;
                    track) col=$PURPLE ;;
                    *) col="" ;;
                esac

                other_ext+=(${same##*.})
            fi
        done
        echo -e "${col:-}${other_ext[@]:-}${col:+$RESET}"
    done
}


case "$action" in
    untracked)
        untracked ;;
    track)
        track ${arglist[@]:-} ;;
    untrack)
        untrack ${arglist[@]:-} ;;
    rm)
        trackrm ${arglist[@]:-} ;;
    push)
        trackpush ${arglist[@]:-};;
    pull)
        trackpull ;;
    find)
        trackfind ${arglist[@]:-} ;;
    findsame)
        findsame ${arglist[@]:-} ;;
    *)
        echo -e "ERROR: unknown command.\n$help" && exit 2 ;;

esac

