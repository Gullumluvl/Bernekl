#!/bin/bash

printprogress=`basename "$0"`

help="USAGE:
    $printprogress <command> <args> [<args>]

ARGUMENTS:

    <command>: Must be a single-quoted string.
               '{}' will be replaced by each argument
               '{.}' will be replaced by each argument (without its extension)
    <args>: either one double-quoted string, then newlines separate each argument;
            or a list of unquoted args, then any whitespace separate arguments.

EXAMPLES:
    $printprogress 'echo {}' *.txt

    $printprogress 'echo {}' "'"'"\$(grep -v '^#' file.csv)"'"'"
"

# unofficial bash strict mode
set -eu
set -o pipefail
#IFS=$'\t\n'
IFS=$'\n'

#my_help() {
#	echo -n "\nAborted by user." >&2
#	exit 1
#}
my_int() {
	echo -ne "\nAborted by user." >&2
	exit 1
}

my_err() {
	echo "$help"
}

trap my_int INT
trap my_err ERR

action=${1:-}
shift
[[ -n "$action" && -n "$@" ]]

my_err() {
	echo -ne "\nError during execution." >&2
}

arglist=( $@ )
total="${#arglist[@]}"

#if [[ $total -eq 1 ]]; then
#	IFS=$' \t\n'
#	arglist=( $@ )
#	total="${#arglist[@]}"
#	IFS=$'\n'
#fi
#echo $total
#exit

set +e
count=0
set -e

for arg in ${arglist[@]}; do
#while read -r -d" " arg; do
	arg_noext="${arg%.*}"
	#percentage="$(bc <<< 'scale=2; 100*'$((++count))'/'$total'')"
	#percentage="$(python3 -c 'print(round(100*'$((++count))'/'$total', 2))')"
	#percentage="$(python3 -c 'print("%.2f" % (100*'$((++count))'/'$total'))')"
	#percentage="$(perl -e 'printf "%.2f", 100*'$((++count))'/'$total'')"
	#percentage="$(awk 'BEGIN{100*'$((++count))'/'$total'}')"
	percentage="$(awk 'BEGIN{printf "%.2f", 100*'$((++count))'/'$total'}')"
	printf "\r%5d/%d (%s%%) : $arg " $((++count)) $total $percentage >&2
	#echo "$arg"
	argaction="${action//\{\}/$arg}"
	argaction="${argaction//\{\.\}/$arg_noext}"
	#echo -e "\n$argaction"
	eval "$argaction"
done <<< "$@"

echo -e "\nDone." >&2


