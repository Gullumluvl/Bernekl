#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'

help="USAGE: $0 [<up|down>] [-h]
No argument:  print the state of the repositories;
         up:  upload (push);
       down:  download (pull);
         -h:  show help."

# synchronize up or down?
updown="${1:-}"

# Check args
[[ $# -gt 1 ]]         && echo "$help" >&2 && exit 1
[[ "$updown" = "-h" ]] && echo "$help" >&2 && exit 0
[[ -n "$updown" ]] && [[ ! "$updown" =~ ^up|down$ ]] && \
    echo "$help">&2 && exit 1

#echo "END" && exit
RED="\e[00;31m"
RESET="\e[00;00m"
BOLD="\e[00;01m"
ITAL="\e[00;03m"
currdir="$(pwd)"
currdirbase="$(basename $currdir)"
#if [[ "$currdirbase" != "phd_notes" ]]; then
#    echo "This script must be run from the 'phd_notes' directory." >&2
#    exit 1
#fi

git_dir_desc=("home dotfiles"
              "my bin tools"
              "SVGGuru"
              "beamer theme"
              "phd_notes")

host=$(hostname)
#host_md5sum=$(hostname | md5sum | cut -f1)

case "$host" in
   Tuatara)
        git_synced_dirs=("$HOME"
                         "$HOME/programTestingArea/mytools"
                         "$HOME/programTestingArea/SVGGuru"
                         "$HOME/texmf/tex/latex/beamer/themes"
                         "$HOME/Documents/biologie/these/phd_notes");;
    ldog27|ldog31)
        git_synced_dirs=("$HOME"
                         "$HOME/mydvpt/mytools"
                         "$HOME/mydvpt/SVGGuru"
                         "$HOME/texmf/tex/latex/beamer/beamerthemes"
                         "$HOME/Documents/these/phd_notes");;
esac

# Check that no git repository contains uncommitted change
not_clean=()
countn=0
# Check that git repository do not contain unpushed changes (before pulling)
ahead=()
counta=0

echo -e "${BOLD}# Git${RESET}"

for git_synced_dir in ${git_synced_dirs[@]}; do
    cd "$git_synced_dir"
    if ! git diff-index --quiet HEAD --; then
        echo -en "${RED}NOT clean${RESET}.  " # In red color.
        not_clean[((countn++))]="$git_synced_dir"
    else
        echo -n "Clean.      "
    fi

    ahead_commits=$(git rev-list --oneline ^origin/master HEAD | wc -l)
    [[ ${ahead_commits} -gt 0 ]] && ahead[((counta++))]="$git_synced_dir" && \
        ahead_commits=$RED$ahead_commits$RESET
    echo -ne "Ahead commits: ${ahead_commits}.    "

    echo "${git_synced_dir/$HOME/\~}"
done
cd "$currdir"


cd ${git_synced_dirs[4]}

if [[ "$host" = "ldog27" ]]; then
    remote="$HOME/ws2/mygitdata/phd_notes"
else
    remote="dyojord:ws2/mygitdata/phd_notes"
fi

if [ -z "$updown" ]; then
    echo -e "\n${BOLD}# Git data${RESET}\n${ITAL}phd_notes data${RESET}"

    set +e
    echo -n "Down:"
    rsync -aruOh -n --stats --files-from="gitdata.index" "$remote/" ./ | head -5
    echo -n "Up:" 
    rsync -aruOh -n --stats --files-from="gitdata.index" ./ "$remote/" | head -5
    #echo "Return code $?"
    set -e

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

if [[ "$updown" = "down" ]] && [[ ${#ahead[@]} -gt 0 ]]; then
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
    if [[ "$updown" = "down" ]]; then
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

echo -e "\n### Synchronizing ${ITAL}phd_notes data${RESET} (rsync)"

cd ${git_synced_dirs[0]}

if [[ "$host" = "ldog27" ]]; then
    remote="$HOME/ws2/mygitdata/phd_notes"
else
    remote="dyojord:ws2/mygitdata/phd_notes"
fi

set +e
if [[ "$updown" = "down" ]]; then
    rsync -rauOvh --files-from="gitdata.index" "$remote/" ./
else
    rsync -rauOvh --files-from="gitdata.index" ./ "$remote/"
fi
echo "Return code $?"
set -e


# phd_notes
#verbose_git_sync 0

for dir_nb in {0..4}; do
    verbose_git_sync "$dir_nb"
done

cd "$currdir"
