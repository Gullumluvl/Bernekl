#!/bin/bash

set -euo pipefail
IFS=$'\t\n'
shopt -s extglob

help="USAGE
${0##*/} [-h] [-n]
          -p <N>
          -i <input file> [-i ...] -o <output file> [-o ...]
          -I <N> -O <N> | -H <N>
          <command>

 -h help
 -n dry run
 -p number of parts
 -i input file (can be reused to append more input files)
 -o output file (idem)
 -I number of header lines in input
 -O number of header lines in output
 -H number of header lines in input and output

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
dryrun=0

while getopts "hnp:i:o:I:O:H:" opt; do
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
        #*)
        #    echo "Invalid option -$opt" >&2
        #    exit 1
        #    ;;
    esac
done
echo ' - Read options.'

shift $((OPTIND-1))
echo ' - Shifted args.'

#[ "$1" = "--" ] && shift

[ -z "$*" ] && echo "$help" && exit 1
echo ' - Checked args presence.'

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

for optval in "$nparts" "$iheader" "$oheader"; do
    # Check integer options
    [[ ! "$optval" =~ ^[0-9]+$ ]] && echo -e "Integer required">&2 && exit 1
done
echo ' - Checked integer options.'

# Split input files

#ilinecounts=()
#olinecounts=()
#for ii in ${!inputs[@]}; do
#    ilinecounts[$ii]=$(wc -l ${inputs[$ii]} | cut -d' ' -f1)
#    lcount=$(wc -l ${inputs[$ii]} | cut -d' ' -f1)

sufflen="${#nparts}"
if [[ "$sufflen" =~ ^10+$ ]]; then
    (( --sufflen )) || echo "suffixe length can't be zero">&2 && exit 1
fi

echo "- DEBUG:
    - nparts:  $nparts
    - inputs:  (${inputs[*]:-})
    - outputs: (${outputs[*]:-})
    - I:       $iheader
    - O:       $oheader
    - sufflen: $sufflen
    - command:     '$command'"


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
            sed -i "1i ${header//$'\n'/\\$'\n'}" ${input}-*([0-9])[1-9] # fails if no file
        fi
    fi
done
#fi

#inpatt=$((for if in ${inputs[@]}; do echo "${if}-%0${#nparts}d"; done))
#outpatt=$((for of in ${inputs[@]}; do echo "${of}-%0${#nparts}d"; done))
allpatt=($(for f in ${all[@]:-}; do echo "${f}-%0${#nparts}d"; done))
#echo "allpatt: ${allpatt[*]:-}"

allpids=()

for (( part=0; part<nparts; part++ )); do
    allparts=($(for p in ${allpatt[@]:-}; do printf "$p\n" $part; done))
    #echo "allparts: ${allparts[*]:-}"
    cmd=$(printf "$command" ${allparts[@]:-})
    if (( dryrun )); then
        echo '$' "$cmd"
    else
        eval "$cmd" &
        allpids+=($!)
    fi
done

echo "allpids: (${allpids[*]:-})"

if (( dryrun )); then exit; fi

wait ${allpids[@]}

for input in ${inputs[@]:-}; do
    #ls ${input}-+([0-9])
    rm -v ${input}-+([0-9])
done
for output in ${outputs[@]:-}; do
    if (( oheader )); then
        #sed -s '$R'
        head -n $oheader ${output}-+(0) > $output
        sed -s "1,${oheader}d" ${output}-+([0-9]) >> $output
        #awk "FNR > $oheader" ${output}-+([0-9]) >> $output
    else
        cat ${output}-+([0-9]) > $output
    fi
    rm -v ${output}-+([0-9])
done
