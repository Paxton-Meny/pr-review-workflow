#!/bin/sh
# Record the user's approval to run the pull request's author's code here.
# Usage: sh scripts/approve-author.sh <state-dir>
# The check command, suggestion proving, and contracts then run on this
# pull request although its author cannot push to the repository
# (exec-approved.txt, read by author-trust.sh --exec). This is a script of
# its own, and the review skill's allowed-tools leaves it out, so Claude
# Code asks the user each time; only the user gives this approval.
set -eu

dir=${1:?usage: approve-author.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "approve-author: no meta.txt in $dir" >&2
	exit 1
}
author=$(sed -n 's/^author //p' "$dir/meta.txt" | head -n 1)
[ -n "$author" ] || {
	echo "approve-author: no author recorded to approve" >&2
	exit 1
}
tmp=$(mktemp "$dir/.approve.XXXXXX")
printf 'approved %s\n' "$author" >"$tmp"
mv "$tmp" "$dir/exec-approved.txt"
echo "approve-author: approved running $author's code for this pull request"
