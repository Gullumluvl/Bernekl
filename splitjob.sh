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
 -S number of header lines in standard output
 -N nice level (0-19) [19]
 -D ionice level (0-7) [5]
 -t separator pattern for the split command.

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
nicelvl=19
ionicelvl=5
sep=

while getopts "hnp:i:o:I:O:H:e:s:S:N:D:t:" opt; do
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
        N)
            nicelvl=$OPTARG ;;
        D)
            ionicelvl=$OPTARG ;;
        t)
            sep=$OPTARG ;;
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


maxpart=$(( ${#nparts} - 1 ))  # String length of this number.
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
cleanup() {
    last_exit=$?
    echo "Cleaning Temporary files.">&2
    for input in ${tmpinputs[@]:-}; do
        rm -v ${input}-+([0-9]) || :
    done
    for output in ${tmpoutputs[@]:-}; do
        rm -v ${output}-+([0-9]) || :
    done
    if [[ -n "${thistmpdir:-}" ]]; then
        rmdir -v "$thistmpdir" || :
    fi

    echo "Last return code: $last_exit. Exit." >&2
}

((dryrun)) || trap cleanup ERR SIGINT SIGTERM EXIT
#TODO: this trap should kill children jobs!!!

# Setup filenames in temporary directory

if [[ -n "${TMPDIR:-}" ]]; then
    # Make tmp directory
    if (( dryrun )); then
        thistmpdir="$(mktemp --dry-run -d -t splitjob.XXXXXXXX)"
    else
        thistmpdir="$(mktemp -d -t splitjob.XXXXXXXX)"
    fi

    if [[ -n "$stdoutfile" ]]; then
        tmpstdoutfile="$thistmpdir/${stdoutfile##*/}"
    fi
    if [[ -n "$stderrfile" ]]; then
        tmpstderrfile="$thistmpdir/${stderrfile##*/}"
    fi

    # Replace dirname by the tmpdir, for all inputs at once.
    #if (( ${#inputs[@]} )); then
    #    # Does not work if there is no '/' in the file name.
    #    tmpinputs=(${inputs[@]/#*\//$thistmpdir})
    #fi
    tmpinputs=()
    for input in ${inputs[@]:-}; do
        tmpinputs+=("$thistmpdir/${input##*/}")
    done
    #if (( ${#outputs[@]} )); then
    #    tmpoutputs+=(${outputs[@]/#*\//$thistmpdir})
    #fi
    tmpoutputs=()
    for output in ${outputs[@]:-}; do
        tmpoutputs+=("$thistmpdir/${output##*/}")
    done
    # Create array $tmpall
    #tmpall=(${any[@]/#*\//$thistmpdir})
    tmpall=()
    for any in ${all[@]:-}; do
        tmpall+=("$thistmpdir/${any##*/}")
    done

    #echo ${tmpinputs[@]}
    #echo ${tmpoutputs[@]}
    #echo ${tmpall[@]}

    # Check that there are no unwanted duplicate names.
    Nall=$(printf '%s\n' "${all[@]:-}" | sort -u | wc -l)
    Ntmpall=$(printf '%s\n' "${tmpall[@]:-}" | sort -u | wc -l)
    (( Nall == Ntmpall ))
else
    tmpstdoutfile=$stdoutfile
    tmpstderrfile=$stderrfile
    tmpinputs=(${inputs[@]:-})
    tmpoutputs=(${outputs[@]:-})
    tmpall=(${all[@]:-})
fi

echo "    - tmpdir: ${thistmpdir:-}
    - tmpinputs: ${tmpinputs[@]:-}
    - tmpoutputs: ${tmpoutputs[@]:-}
    - tmpstdoutfile: ${tmpstdoutfile:-}
    - tmpstderrfile: ${tmpstderrfile:-}" >&2

unsplit() {
    ## When splitted into too many files (because of split reading from stdin),
    ## reduces the number of outputs to the requested number (with records in order).
    local tmpinput=$1
    local sufflen=$2
    local nparts=$3

    local out=("${tmpinput}"-*([0-9])[0-9])
    local nout=$(( ${#out[@]} - 1 ))
    #(( nout+1 > nparts )) || return 0

    local pack=$(( nout / nparts ))
    local remain=$(( nout % nparts ))

    local next_first=1

    #for p in {0..$((nparts-1))}; do
    for ((p=0; p<=nparts-1; p++)); do
        local packsize=$(( (0<p && p<=remain) ? pack+1 : pack ))
        #packsize=$(( p<remain ? pack+1 : pack ))
        local infiles=($(seq -f "${tmpinput}-%0${sufflen}.0f" $((next_first)) $((next_first + packsize - 1))))
        (( ${#infiles[@]} )) || { echo "Zero input files.">&2 ; break ; }
        printf -v unsplitoutfile "${tmpinput}-%0${sufflen}d" $p
        #echo "# PUT ${infiles[@]} >> $unsplitoutfile  && rm infiles."
        cat ${infiles[@]} >> "$unsplitoutfile" && rm ${infiles[@]}
        ((next_first += packsize))

    done
}

# Split input files
if [[ -n "$sep" ]]; then
    split_cmd_base() {
        local input=$1
        local tmpinput=$2
        local sufflen=$3
        local nparts=$4
        egrep -q -E "$sep" $input || {
            echo "Pattern '$sep' not found in $input" >&2;
            exit 1; }
        !egrep -q -Pa '\x00' $input || {
            echo "Nul characters already present in $input, can't use them as separator." >&2;
            exit 1; }
        if (( dryrun )); then
            echo '$' 'sed "s/'$sep'/\x0\1/g" "'$input'" | split -t'"'"'\0'"'"' -d -a '$sufflen' -n "l/'$nparts'" - "'${tmpinput}'-"'
        else
            #[[ -n "$(sed -n /$sep/pq $input)" ]] || {
            sed -r "s/$sep/\x0\1/g" "$input" |\
                split -t'\0' -d -a $sufflen -n "l/$nparts" - "${tmpinput}-"
        fi
    }
else
    split_cmd_base() {
        local input=$1
        local tmpinput=$2
        local sufflen=$3
        local nparts=$4
        if (( dryrun )); then
            if [[ "$input" =~ ^/dev/fd/ ]]; then
                echo '$' 'split -d -a '$sufflen' -l 1000 "'${input}'" "'${tmpinput}'-"'
                echo '$ unsplit "'${tmpinput}'" '$sufflen' '"$nparts"
            else
                echo '$' 'split -d -a '$sufflen' -n "l/'$nparts'" "'${input}'" "'${tmpinput}'-"'
            fi
        else
            if [[ "$input" =~ ^/dev/fd/ ]]; then
                split -d -a $sufflen -l 1000 "${input}" "${tmpinput}-"
                unsplit "${tmpinput}" $sufflen $nparts
            else
                #[[ -n "$(sed -n /$sep/pq $input)" ]] || {
                split -d -a $sufflen -n "l/$nparts" "${input}" "${tmpinput}-"
            fi
        fi
    }
fi
if (( iheader )); then
    split_cmd() {
        local input=$1
        local tmpinput=$2
        local header="$(head -n $iheader $input)"
        split_cmd_base $@
        # Precede each newline by a backslash and insert header (or printf '%q' ?)
        # fails if no file
        if (( dryrun )); then
            echo '$' 'sed -i "1i '${header//$'\n'/\\$'\n'}'" '${tmpinput}'-*([0-9])[1-9]' #|| \
                #{ echo "Can't insert header: no input parts available.">&2 ;
                # exit 1; }
        else
            sed -i "1i ${header//$'\n'/\\$'\n'}" ${tmpinput}-*([0-9])[1-9] || \
                { echo "Can't insert header: no input parts available.">&2 ;
                 exit 1; }
        fi
    }
else
    split_cmd() {
        split_cmd_base $@
    }
fi

#if (( ${#inputs} )); then
#for input in ${inputs[@]:-}; do
for i_input in ${!inputs[@]}; do
    input=${inputs[$i_input]}
    tmpinput=${tmpinputs[$i_input]}
    ##lcount=$(wc -l "$input" | cut -d' ' -f1)
    ##((lcount -= iheader))
    ##lpart=$(( lcount / nparts ))
    ##(( lcount % nparts )) && (( lpart++ ))
    #if (( dryrun )); then
    #    if (( iheader )); then
    #        echo '$' tail -n +$((iheader+1)) "$input" \| split -d -a $sufflen -n "l/$nparts" - "${tmpinput}-"
    #    else
    #        echo '$' split -d -a $sufflen -n "l/$nparts" "$input" "${tmpinput}-"
    #    fi
    #else
    #    if [[ -n "$sep" ]]; then
    #        sed "s/$sep/\0\1/g" "$input" | split -t'\0' -d -a $sufflen -n "l/$nparts" - "${tmpinput}-"
    #    fi
    #    split -d -a $sufflen -n "l/$nparts" "$input" "${tmpinput}-"
    #    if (( iheader )); then
    #        #tail -n +$((iheader+1)) "$input" | split -d -a $sufflen -n "l/$nparts" - "${input}-"
    #        header="$(head -n $iheader $input)"
    #        # Precede each newline by a backslash and insert header
    #        # fails if no file
    #        sed -i "1i ${header//$'\n'/\\$'\n'}" ${tmpinput}-*([0-9])[1-9] || \
    #            { echo "Can't insert header: no input parts available.">&2 ;
    #             exit 1; }
    #    fi
    #fi
    split_cmd "$input" "$tmpinput" "$sufflen" "$nparts"
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
    if (( ${#tmpall[@]} )); then
        allpartfiles=(${tmpall[*]/%/-$part})
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
trap cleanup ERR SIGINT SIGTERM EXIT

echo "Merging output files" >&2


merge_output_with_header() {
    local nheader=$1
    local output=$2
    local tmpoutput=${3:-$output}
    if (( nheader )); then
        head -n $nheader ${tmpoutput}-+(0) > $output
        sed -s "1,${nheader}d" ${tmpoutput}-+([0-9]) >> $output
    else
        cat ${tmpoutput}-+([0-9]) > $output
    fi
}


#for output in ${outputs[@]:-}; do
for i_output in ${!outputs[@]}; do
    output=${outputs[$i_output]}
    tmpoutput=${tmpoutputs[$i_output]}
    merge_output_with_header $oheader "$output" "$tmpoutput"
done

if [[ -n "$stderrfile" ]]; then
    cat ${tmpstderrfile}-+([0-9]) > $stderrfile
    # For the clean exit:
    tmpoutputs+=("$tmpstderrfile")
fi
if [[ -n "$stdoutfile" ]]; then
    merge_output_with_header $sheader "$stdoutfile" "$tmpstdoutfile"
    # For the clean exit:
    # TODO: handle the case where nothing was outputted to stdout. (error in `head`)
    tmpoutputs+=("$tmpstdoutfile")
fi


trap - ERR SIGINT SIGTERM EXIT

echo "Part return codes: ${waitreturns[@]}" >&2
cleanup

[[ "${waitreturns}" =~ [1-9] ]] && return=1 || return=0
exit $return
