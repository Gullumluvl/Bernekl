#!/usr/bin/env sh

# WARNING: this is a draft.

set -euo pipefail

# First get the list of remote files removed locally

# 1. rsync -n -i: list the files that would be created
# 2. tac: reverse the list, so that directory paths appear after (and are empty when deleting)
# 3. sed: only output the file name: remove itemize string, and the arrow indicating symlinks.
rsync -n -i -auOh --exclude-from=gitdata.index --ignore-missing-args $REMOTE:$REPOPATH/ ./ \
| tac
| sed -r 's/^\S+\s+/\//; s/ -> .*$//' > todelete-remote-files.txt

# Actually tell rsync to delete those remote files:
rsync -i -PRruavh -e ssh ./ $LOCAL:$REPOPATH/ --ignore-errors --force --delete-missing-args --files-from=todelete-remote-files.txt

