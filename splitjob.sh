#!/bin/bash

set -euo pipefail
IFS=$'\t\n'
shopt -s extglob

help="DESCRIPTION

Automatic command line parallelization:
take a command line, input and output file arguments, split them into
smaller parts, run them in parallel, and join the outputs.

USAGE
${0##*/} [-h] [-n]
          -p <N>
          -i <input file> [-i ...] -o <output file> [-o ...]
          -I <N> -O <N> | -H <N>
          -e <stderr file> -s <stdout file>
          <command>

 -h help
 -n dry run
 -p number of parts
 -i input file (can be reused to append more input files)
 -o output file (idem)
 -I number of header lines in input
 -O number of header lines in output
 -H number of header lines in input and output
 -e name of the file to collect stderr
 -s name of the file to collect stdout
 -S number of header lines in standard output.
 -N nice level (0-19) NOT implemented
 -D ionice level (0-7) NOT implemented

command formatting:
Using printf format (%s to format string).
"

### PARSE COMMAND LINE ###

#
OPTIND=1

nparts=2
#echo ${#nparts}
inputs=()
outputs=()
all=()
iheader=0
oheader=0
sheader=0
dryrun=0
stderrfile=""
stdoutfile=""
nicelvl=0
ionicelvl=0

while getopts "hnp:i:o:I:O:H:e:s:S:N:D:" opt; do
    #echo $OPTIND
    case $opt in
        h)
            echo "$help"
            exit 0
            ;;
        n)
            dryrun=1 ;;
        p)
            nparts=$OPTARG ;;
        H)
            iheader=$OPTARG
            oheader=$OPTARG
            ;;
        I)
            iheader=$OPTARG ;;
        O)
            oheader=$OPTARG ;;
        i)
            inputs+=("$OPTARG")
            all+=("$OPTARG")
            ;;
        o)
            outputs+=("$OPTARG")
            all+=("$OPTARG")
            ;;
        e)
            stderrfile="$OPTARG" ;;
        s)
            stdoutfile="$OPTARG" ;;
        S)
            sheader=$OPTARG ;;
        N)  nicelvl=$OPTARG ;;
        D)  ionicelvl=$OPTARG ;;
        #*)
        #    echo "Invalid option -$opt" >&2
        #    exit 1
        #    ;;
    esac
done
#echo ' - Read options.'

shift $((OPTIND-1))
#echo ' - Shifted args.'

#[ "$1" = "--" ] && shift

[ -z "$*" ] && echo "$help" && exit 1
#echo ' - Checked args presence.'

IFS=' ' command="$*"
IFS=$'\t\n'

set +e
Nformats="$(grep -o '%s' <<<"$command" | wc -l)"
set -e

if [[ "$Nformats" -lt "${#all[@]}" ]]; then
    echo "WARNING: Too many files for formatting">&2
elif [[ "$Nformats" -gt "${#all[@]}" ]]; then
    echo "ERROR: Not enough files for formatting">&2
    exit 1
fi

if [[ -n "$stdoutfile" ]]; then
    if [[ ! -d "${stdoutfile%/*}" ]]; then
        echo "Directory for stdoutfile does not exist.">&2
        exit 1
    fi
    all+=("$stdoutfile")
    command+=" >%s"
fi
if [[ -n "$stderrfile" ]]; then
    if [[ ! -d "${stderrfile%/*}" ]]; then
        echo "Directory for stderrfile does not exist.">&2
        exit 1
    fi
    all+=("$stderrfile")
    command+=" 2>%s"
fi

for optval in "$nparts" "$iheader" "$oheader" "$sheader" "$ionicelvl" "$nicelvl"; do
    # Check integer options
    [[ ! "$optval" =~ ^[0-9]+$ ]] && echo "Integer required">&2 && exit 1
    # TODO: do not allow zero value
done
#echo ' - Checked integer options.'

if (( $ionicelvl )); then
    command="ionice -c2 -n$ionicelvl $command"
fi
if (( $nicelvl )); then
    command="nice -$nicelvl $command"
fi


maxpart=$(( ${#nparts} - 1 ))
sufflen="${#maxpart}"

# TODO: Simply force sufflen=2 and do not allow more than 100 parts...

#sufflen="${#nparts}"
#if [[ "$sufflen" =~ ^10+$ ]]; then
#    (( --sufflen )) || echo "suffixe length can't be zero">&2 && exit 1
#fi

echo "DEBUG:
    - nparts:  $nparts
    - inputs:  (${inputs[*]:-})
    - outputs: (${outputs[*]:-})
    - I:       $iheader
    - O:       $oheader
    - S:       $sheader
    - sufflen: $sufflen
    - stderrfile: $stderrfile
    - stdoutfile: $stdoutfile
    - command:     '$command'" >&2

# Cleanup temporary files in case of error
clean_exit() {
    last_exit=$?
    echo "Cleaning Temporary files.">&2
    for input in ${inputs[@]:-}; do
        rm -v ${input}-+([0-9]) || :
    done
    for output in ${outputs[@]:-}; do
        rm -v ${output}-+([0-9]) || :
    done

    echo "Last return code: $last_exit. Exit." >&2
}

((dryrun)) || trap clean_exit ERR SIGINT SIGTERM EXIT

# Split input files

#if (( ${#inputs} )); then
for input in ${inputs[@]:-}; do
    #lcount=$(wc -l "$input" | cut -d' ' -f1)
    #((lcount -= iheader))
    #lpart=$(( lcount / nparts ))
    #(( lcount % nparts )) && (( lpart++ ))
    if (( dryrun )); then
        if (( iheader )); then
            echo '$' tail -n +$((iheader+1)) "$input" \| split -d -a $sufflen -n "l/$nparts" - "${input}-"
        else
            echo '$' split -d -a $sufflen -n "l/$nparts" "$input" "${input}-"
        fi
    else
        split -d -a $sufflen -n "l/$nparts" "$input" "${input}-"
        if (( iheader )); then
            #tail -n +$((iheader+1)) "$input" | split -d -a $sufflen -n "l/$nparts" - "${input}-"
            header="$(head -n $iheader $input)"
            # Precede each newline by a backslash and insert header
            # fails if no file
            sed -i "1i ${header//$'\n'/\\$'\n'}" ${input}-*([0-9])[1-9] || \
                { echo "Can't insert header: no input parts available.">&2 ;
                 exit 1; }
        fi
    fi
done
#fi

#inpatt=$((for if in ${inputs[@]}; do echo "${if}-%0${#nparts}d"; done))
#outpatt=$((for of in ${inputs[@]}; do echo "${of}-%0${#nparts}d"; done))
#allpatt=($(for f in ${all[@]:-}; do echo "${f}-%0${#nparts}d"; done))
#if (( ${#all[@]} )); then
#    allpatt=(${all[@]/%/-%0${#nparts}d})
#else
#    allpatt=()
#fi
#echo "allpatt: ${allpatt[*]:-}" && exit

allpids=()
allparts=$( seq -f "%0${sufflen}.0f" 0 "$((nparts-1))" )

for part in $allparts; do
    #allpartfiles=($(for p in ${allpatt[@]:-}; do printf "$p\n" $part; done))
    
    #printf "IFS=%q\n" "$IFS"

    # Append suffix to all filenames
    if (( ${#all[@]} )); then
        allpartfiles=(${all[*]/%/-$part})
    fi
    #echo "allpartfiles: ${allpartfiles[@]/#/>}"
    cmd=$( printf "$command" ${allpartfiles[@]:-} )
    if (( dryrun )); then
        echo '$' "$cmd"
    else
        #echo '$' "$cmd"
        eval "$cmd &"
        allpids+=($!)
    fi
done

(( dryrun )) && exit

echo "allpids: (${allpids[@]:-})" >&2

#wait ${allpids[@]}
waitreturns=()

set +e
trap - ERR SIGINT SIGTERM EXIT
for ipid in ${!allpids[@]}; do
    wait ${allpids[$ipid]}
    waitreturn=$?
    (( waitreturn == 127 )) && echo "NO BACKGROUND PROCESSES FOUND!">&2 && exit 127
    if ((waitreturn != 0 )); then
        echo "Part $ipid failed ($waitreturn)!" >&2
    fi
    waitreturns+=($waitreturn)
done
set -e
trap clean_exit ERR SIGINT SIGTERM EXIT

echo "Merging output files" >&2


merge_output_with_header() {
    local nheader=$1
    local output=$2
    if (( nheader )); then
        head -n $nheader ${output}-+(0) > $output
        sed -s "1,${nheader}d" ${output}-+([0-9]) >> $output
    else
        cat ${output}-+([0-9]) > $output
    fi
}


for output in ${outputs[@]:-}; do
    merge_output_with_header $oheader "$output"
done

if [[ -n "$stderrfile" ]]; then
    cat ${stderrfile}-+([0-9]) > $stderrfile
    # For the clean exit:
    outputs+=("$stderrfile")
fi
if [[ -n "$stdoutfile" ]]; then
    merge_output_with_header $sheader "$stdoutfile"
    # For the clean exit:
    outputs+=("$stdoutfile")
fi


trap - ERR SIGINT SIGTERM EXIT

echo "Part return codes: ${waitreturns[@]}" >&2
clean_exit
