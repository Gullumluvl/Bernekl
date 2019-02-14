#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'
#shopt extglob
shopt -s extglob # Off by default in a script

help="USAGE: $0 [<u|up|d|down>] [-h]
No argument:  print the state of the repositories;
       u/up:  upload (push);
     d/down:  download (pull);
         -h:  show help;
         -r:  specify a special remote to:
              1. replace the \${remote} string in the list file;
              2. choose as a remote with git.
         -d:  print debugging messages;
         -f:  use this config file instead of the default [~/beamsync.list].
              (NOT IMPLEMENTED)

Requires the file "'`'"~/beamsync.list"'`'".

Formatted like: tab separated list of synchronized directories:
Column 1	Column 2	(Column 3, optional)
path	description	rsync/git remote repository

~ or \$HOME is replaced by the \$HOME value.
\$remote or \${remote} is replaced by the value of the -r option.

If a line has 2 columns: assume it's a git command.
If a line has a 3rd and 4th column:
  - if the 3rd column is 'R', use the 4th one as a rsync remote.
  - else give the remaining args to git push/pull.
If there is only a 3rd column (potentially dangerous), try to guess:
  - if it contains ':', use a rsync command.
  (In summary, configure your git remotes with git-remote, and don't try to rsync
  to a local directory without giving a 'R' column.)

Comments are specified by:
  - a '#' at the beginning of the line;
  - a '#' after a tabulation.

TODO: the first line is: remote=somename, use it as the default remote.
"

set -o errtrace
trap "echo $? l.$LINENO '$BASH_COMMAND':$BASH_LINENO" ERR

remote=
debug=0
listfile="$HOME/beamsync.list"

while getopts "hr:df:" opt; do
    #echo $OPTIND
    case $opt in
        h)
            echo "$help"
            exit 0
            ;;
        r)
            remote=$OPTARG ;;
        d)
            debug=1 ;;
        f)
            listfile=$OPTARG ;;
        #*)
        #    echo "Invalid option -$opt" >&2
        #    exit 1
        #    ;;
    esac
done
shift $((OPTIND-1))

# synchronize up or down?
updown="${1:-}"

# Check args
[[ $# -gt 1 ]]         && echo "$help" >&2 && exit 1
#[[ "$updown" = "-h" ]] && echo "$help" >&2 && exit 0
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
[[ ! -f "$listfile" ]] && echo "File $listfile not found." >&2 && exit 1

synced_dirs=()
dir_desc=()
#rsync_synced=()
rsync_remotes=()
git_remotes=()

dircount=0
while read -a line; do
    if [[ ${#line[@]} -gt 0 ]] && [[ ! "${line[0]}" =~ ^# ]]; then
        # Local directory
        dir=${line[0]/@(\~|\$HOME)/$HOME}
        dir=${dir%%+( )} # strip trailing spaces
        dir=${dir%/}
        synced_dirs+=("$dir")
        dirbasename=${dir##*/}
        desc=${line[1]-$dirbasename}  # Default if not specified.
        dir_desc+=("${desc%%+( )}")
        if [[ ${#line[@]} -eq 3 ]] && [[ ! "${line[2]}" =~ ^# ]] || \
            [[ ${#line[@]} -gt 3 ]] && [[ "${line[3]}" =~ ^# ]]; then
            # Replace the remote keyword by the given option.
            if [[ -z "${remote}" ]] && [[ ${line[2]} =~ ^\$remote|^\${remote} ]]; then
                echo "ERROR: keyword remote but no option given." >&2
                exit 1
            fi
            rsync_r="${line[2]/\$@(remote|{remote})/$remote}"

            if [[ ${line[2]} =~ : ]]; then
                rsync_remotes[$dircount]="$rsync_r"
            else #if [[  ]]; then
                # THIS WILL BE A GIT COMMAND
                git_remotes[$dircount]="$rsync_r"
            fi
        elif [[ ${#line[@]} -ge 4 ]]; then
            if [[ -z "${remote}" ]] && [[ ${line[3]} =~ ^\$remote|^\${remote} ]]; then
                echo "ERROR: keyword remote but no option given." >&2
                exit 1
            fi
            rsync_r="${line[3]/#\$@(remote|\{remote\})/$remote}"

            if [[ ${line[2]} = 'R' ]]; then
                rsync_r="${rsync_r/#@(\~|\$HOME)/$HOME}"  # substitute only at the beginning.
                rsync_remotes[$dircount]="$rsync_r"
                #rsync_synced+=($dircount)
            elif [[ ${line[2]} = 'G' ]]; then
                git_remotes[$dircount]="$rsync_r"
            else
                echo "ERROR: invalid value for 3rd column (l.$dircount): '${line[2]}'" >&2
                exit 1
            fi
        fi
        #rsync_remotes+=("")
        ((++dircount))
        #echo "READ: ${line[@]}"
    fi
done < "$listfile"

if (( debug )); then
    echo -e "$dircount\t${#synced_dirs[@]}\t${#dir_desc[@]}\t${#rsync_remotes[@]}\t${#git_remotes[@]}"
    for dc in ${!synced_dirs[@]}; do
        echo -ne "${synced_dirs[$dc]}\t"
        echo -ne "${dir_desc[$dc]}\t"
        echo "${rsync_remotes[$dc]-}${git_remotes[$dc]-}"
    done
fi

[[ "${#dir_desc[@]}" -ne "${#synced_dirs[@]}" ]] && \
    echo "ERROR: Description and directory lists don't match">&2 && exit 1


# Check that no git repository contains uncommitted change
not_clean=()
countn=0
# Check that git repository do not contain unpushed changes (before pulling)
ahead=()
counta=0

echo -e "${BGREY}# Git${RESET}"

#for synced_i in ${!synced_dirs[@]}; do
#    synced_dir=${synced_dirs[$synced_i]}
#    git_remote=${git_remotes[$synced_i]-}
for synced_dir in ${synced_dirs[@]}; do
    #echo -n "$synced_dir   "
    cd "$synced_dir"
    notready=0
    if ! git diff-index --quiet HEAD --; then
        echo -en "${RED}NOT clean${RESET}  " # In red color.
        not_clean[((countn++))]="$synced_dir"
        ((++notready))
    else
        echo -n "Clean      "
    fi

    ahead_commits=$(git rev-list --oneline ^${remote:-origin}/master HEAD | wc -l)
    ahead_col=""
    if [[ ${ahead_commits} -gt 0 ]]; then
        ahead[((counta++))]="$synced_dir"
        ahead_col=$CYAN
        ((notready+=2))
    fi
    printf "Ahead commits: ${ahead_col}%2d$RESET    " ${ahead_commits}

    case $notready in
        1) echo -ne $RED ;;
        2) echo -ne $CYAN ;;
        3) echo -ne $PURPL ;;
    esac
    echo -e "${synced_dir/$HOME/\~}$RESET"
done
cd "$currdir"

# Rsync dry-run. TODO: git dry-run.
if [ -z "$updown" ]; then
    # Iterate over all indices where an element was filled.
    for rsync_i in ${!rsync_remotes[@]}; do
    
        cd "${synced_dirs[$rsync_i]}"
        rsync_desc="${dir_desc[$rsync_i]}"
        remote="${rsync_remotes[$rsync_i]}"  # Not allowed to be undefined.

        echo -e "\n${BGREY}# Git data${RESET}\n${ITAL}$rsync_desc data${RESET}"

        set +e
        echo -n "Down:"
        rsync -aruOh -n --stats --ignore-missing-args --files-from="gitdata.index" "$remote/" ./ | head -5
        echo -n "Up:" 
        rsync -aruOh -n --stats --ignore-missing-args --files-from="gitdata.index" ./ "$remote/" | head -5
        #echo "Return code $?"
        set -e
    done

    echo "Done.">&2
    exit
fi

if [[ ${#not_clean[@]} -gt 0 ]]; then
    echo "ERROR: Working trees not clean, please commit your changes in:" >&2
    for dir in ${not_clean[@]}; do
        echo "    ${dir}" >&2
    done
    exit 1
fi

if [[ "$updown" =~ ^(d|down)$ ]] && [[ ${#ahead[@]} -gt 0 ]]; then
    echo "ERROR: Ahead commits should be pushed before pulling:" >&2
    for dir in ${ahead[@]}; do
        echo "    ${dir}" >&2
    done
    exit 1
fi

echo "############################"

verbose_git_sync() {
    # Take the index of the directory to sync.

    #echo "executing verbose_git_sync"
    if [[ $# -ne 1 ]]; then
        echo "Wrong nb of args in verbose_git_sync">&2 && return 1
    elif [[ ! "$1" =~ ^[0-9]+$ ]]; then
        echo "Argument of verbose_git_sync must be an integer">&2 && return 1
    fi
    
    synced_dir="${synced_dirs[$1]}"
    git_remote=${git_remotes[$1]-}
    git_branch=
    [[ -z "$git_remote" ]] || git_branch="master"

    cd "$synced_dir" #&& echo "moved to dir $synced_dir">&2 echo "failed to move"
    
    echo -e "\n### Synchronizing ${ITAL}${dir_desc[$1]}${RESET} at ${synced_dir/$HOME/\~}"

    #git status -uno
    ahead_commits=$(git rev-list --oneline ^${remote:-origin}/master HEAD | wc -l)
    if [[ "$updown" =~ ^(d|down)$ ]]; then
        git pull ${git_remote} ${git_branch}
    elif [[ "$ahead_commits" -eq 0 ]]; then
        echo "Nothing to push"
    else
        git push ${git_remote} ${git_branch}
    fi

    cd "$currdir"
}

#rsync_sync(){
#}


# Git

# Enumerate indices
###TODO: Ignore synced_dirs that are **only rsync** synchronized.
for i in ${!synced_dirs[@]}; do
    verbose_git_sync $i
done

# Git data (with rsync)
echo -e "\n${BGREY}# Git Data${RESET}"
for rsync_i in ${!rsync_remotes[@]}; do
    cd "${synced_dirs[$rsync_i]}"
    rsync_desc="${dir_desc[$rsync_i]}"
    repo="${rsync_remotes[$rsync_i]}"
    echo -e "### Synchronizing ${ITAL}$rsync_desc data${RESET} (rsync)"

    set +e
    if [[ "$updown" =~ ^(d|down)$ ]]; then
        echo "Down:"
        rsync -rauOvh --files-from="gitdata.index" "$repo/" ./
    else
        echo "Up:"
        rsync -rauOvh --files-from="gitdata.index" ./ "$repo/"
    fi
    rsync_return=$?
    set -e
    [[ "$rsync_return" -ne 0 ]] && echo -e "Return code ${RED}${rsync_return}${RESET}"
done


cd "$currdir"
