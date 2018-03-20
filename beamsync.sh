#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'
#shopt extglob
shopt -s extglob # Off by default in a script

help="USAGE: $0 [<u|up|d|down>] [-h]
No argument:  print the state of the repositories;
       u/up:  upload (push);
     d/down:  download (pull);
         -h:  show help.
         
Requires the file ~/beamsync.list.
Formatted like: tab separated list of synchronized directories:
Column 1	Column 2	(Column 3, optional)
path	description	rsync remote repository

~ or \$HOME is replaced by the \$HOME value.
"

# synchronize up or down?
updown="${1:-}"

# Check args
[[ $# -gt 1 ]]         && echo "$help" >&2 && exit 1
[[ "$updown" = "-h" ]] && echo "$help" >&2 && exit 0
[[ -n "$updown" ]] && [[ ! "$updown" =~ ^(u|up|d|down)$ ]] && \
    echo "$help">&2 && exit 1

#echo "END" && exit
RED="\e[00;31m"
#BRED="\e[01;31m"
CYAN="\e[00;36m"
PURPL="\e[00;35m"
RESET="\e[00;00m"
#BOLD="\e[00;01m"
BGREY="\e[01;30m"
ITAL="\e[00;03m"
currdir="$(pwd)"

##host_md5sum=$(hostname | md5sum | cut -f1)
#
listfile="$HOME/beamsync.list"
[[ ! -f "$listfile" ]] && echo "File $listfile not found." >&2 && exit 1

git_synced_dirs=()
git_dir_desc=()
#rsync_synced=()
rsync_remotes=()

dircount=0
while read -a line; do
    if [[ ${#line[@]} -gt 0 ]] && [[ ! "${line[0]}" =~ ^# ]]; then
        dir=${line[0]/@(\~|\$HOME)/$HOME}
        dir=${dir%%+( )} # strip trailing spaces
        dir=${dir%/}
        git_synced_dirs+=("$dir")
        dirbasename=${dir##*/}
        desc=${line[1]-$dirbasename}
        git_dir_desc+=("${desc%%+( )}")
        if [[ ${#line[@]} -ge 3 ]] && [[ ! "${line[2]}" =~ ^# ]]; then
            rsync_r="${line[2]/@(\~|\$HOME)/$HOME}"
            rsync_remotes[$dircount]="$rsync_r"
            #rsync_synced+=($dircount)
        fi
        #rsync_remotes+=("")
        ((++dircount))
        #echo "READ: ${line[@]}"
    fi
done < "$listfile"

#echo -e "$dircount\t${#git_synced_dirs[@]}\t${#git_dir_desc[@]}\t${#rsync_remotes[@]}"
#for dc in $(seq 0 $dircount);do
#    echo -ne "${git_synced_dirs[$dc]}\t"
#    echo -ne "${git_dir_desc[$dc]}\t"
#    echo "${rsync_remotes[$dc]-}"
#done

[[ "${#git_dir_desc[@]}" -ne "${#git_synced_dirs[@]}" ]] && \
    echo "Description and directory lists don't match">&2 && exit 1


# Check that no git repository contains uncommitted change
not_clean=()
countn=0
# Check that git repository do not contain unpushed changes (before pulling)
ahead=()
counta=0

echo -e "${BGREY}# Git${RESET}"

for git_synced_dir in ${git_synced_dirs[@]}; do
    #echo -n "$git_synced_dir   "
    cd "$git_synced_dir"
    notready=0
    if ! git diff-index --quiet HEAD --; then
        echo -en "${RED}NOT clean${RESET}  " # In red color.
        not_clean[((countn++))]="$git_synced_dir"
        ((++notready))
    else
        echo -n "Clean      "
    fi

    ahead_commits=$(git rev-list --oneline ^origin/master HEAD | wc -l)
    ahead_col=""
    if [[ ${ahead_commits} -gt 0 ]]; then
        ahead[((counta++))]="$git_synced_dir"
        ahead_col=$CYAN
        ((notready+=2))
    fi
    printf "Ahead commits: ${ahead_col}%2d$RESET    " ${ahead_commits}

    case $notready in
        1) echo -ne $RED ;;
        2) echo -ne $CYAN ;;
        3) echo -ne $PURPL ;;
    esac
    echo -e "${git_synced_dir/$HOME/\~}$RESET"
done
cd "$currdir"

if [ -z "$updown" ]; then
    for rsync_i in ${!rsync_remotes[@]}; do
    
        cd "${git_synced_dirs[$rsync_i]}"
        rsync_desc="${git_dir_desc[$rsync_i]}"
        remote="${rsync_remotes[$rsync_i]}"

        echo -e "\n${BGREY}# Git data${RESET}\n${ITAL}$rsync_desc data${RESET}"

        set +e
        echo -n "Down:"
        rsync -aruOh -n --stats --files-from="gitdata.index" "$remote/" ./ | head -5
        echo -n "Up:" 
        rsync -aruOh -n --stats --files-from="gitdata.index" ./ "$remote/" | head -5
        #echo "Return code $?"
        set -e
    done

    echo "Done.">&2
    exit
fi

if [[ ${#not_clean[@]} -gt 0 ]]; then
    echo "Working trees not clean, please commit your changes in:" >&2
    for dir in ${not_clean[@]}; do
        echo "    ${dir}" >&2
    done
    exit 1
fi

if [[ "$updown" =~ ^(d|down)$ ]] && [[ ${#ahead[@]} -gt 0 ]]; then
    echo "Ahead commits should be pushed before pulling:" >&2
    for dir in ${ahead[@]}; do
        echo "    ${dir}" >&2
    done
    exit 1
fi

echo "############################"

verbose_git_sync() {
    #echo "executing verbose_git_sync"
    if [[ $# -ne 1 ]]; then
        echo "Wrong nb of args in verbose_git_sync">&2 && return 1
    elif [[ ! "$1" =~ ^[0-9]+$ ]]; then
        echo "Argument of verbose_git_sync must be an integer">&2 && return 1
    fi
    
    synced_dir="${git_synced_dirs[$1]}"
    cd "$synced_dir" #&& echo "moved to dir $synced_dir">&2 echo "failed to move"
    
    echo -e "\n### Synchronizing ${ITAL}${git_dir_desc[$1]}${RESET} at ${synced_dir/$HOME/\~}"

    #git status -uno
    ahead_commits=$(git rev-list --oneline ^origin/master HEAD | wc -l)
    if [[ "$updown" =~ ^(d|down)$ ]]; then
        git pull
    elif [[ "$ahead_commits" -eq 0 ]]; then
        echo "Nothing to push"
    else
        git push
    fi

    cd "$currdir"
}

#rsync_sync(){
#}


# Git

# Enumerate indices
for i in ${!git_synced_dirs[@]}; do
    verbose_git_sync $i
done

# Git data
echo -e "\n${BGREY}# Git Data${RESET}"
for rsync_i in ${!rsync_remotes[@]}; do
    cd "${git_synced_dirs[$rsync_i]}"
    rsync_desc="${git_dir_desc[$rsync_i]}"
    remote="${rsync_remotes[$rsync_i]}"
    echo -e "### Synchronizing ${ITAL}$rsync_desc data${RESET} (rsync)"

    set +e
    if [[ "$updown" =~ ^(d|down)$ ]]; then
        echo "Down:"
        rsync -rauOvh --files-from="gitdata.index" "$remote/" ./
    else
        echo "Up:"
        rsync -rauOvh --files-from="gitdata.index" ./ "$remote/"
    fi
    rsync_return=$?
    set -e
    [[ "$rsync_return" -ne 0 ]] && echo -e "Return code ${RED}${rsync_return}${RESET}"
done


cd "$currdir"
