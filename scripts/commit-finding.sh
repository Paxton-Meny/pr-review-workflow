#!/bin/sh
# Commit one finding's fix in the review worktree and mark it addressed.
# Usage: printf '%s\n' "<subject>" | sh scripts/commit-finding.sh <state-dir> <id> <path>...
# Stages the named paths (relative to the worktree), commits them as the
# signed-in account meta.txt records with the body "Addresses <id>.",
# and records the commit on the finding as status addressed, so the
# ledger shows each fix the moment it lands and an editor that stops
# early leaves nothing unrecorded. The subject is one line of at most
# 72 characters with no trailing period. Exit 3: the paths hold no
# change to commit. A finding that is not open is refused.
set -eu

usage='usage: commit-finding.sh <state-dir> <id> <path>...   (subject on stdin)'
SUBJECT_MAX=72
dir=${1:?$usage}
id=${2:?$usage}
shift 2
[ "$#" -gt 0 ] || {
	echo "$usage" >&2
	exit 1
}
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "commit-finding: no worktree in $dir, run checkout-pr.sh first" >&2
	exit 1
}
record="$dir/findings/$id"
case "$id" in
'' | *[!A-Za-z0-9]*) record='' ;;
esac
[ -n "$record" ] && [ -f "$record" ] || {
	echo "commit-finding: unknown finding: $id" >&2
	exit 1
}
status=$(sed -n '/^---$/q; s/^status: //p' "$record")
[ "$status" = open ] || {
	echo "commit-finding: $id is $status, not open" >&2
	exit 1
}
for path in "$@"; do
	case "$path" in
	'' | -* | /* | '~'* | .. | ../* | */.. | */../*)
		echo "commit-finding: a path must be relative to the worktree and stay inside it: $path" >&2
		exit 1
		;;
	esac
done
subject=$(cat)
case "$subject" in
'' | *'
'*)
	echo "commit-finding: the subject on stdin must be exactly one line" >&2
	exit 1
	;;
*.)
	echo "commit-finding: the subject ends with a period: $subject" >&2
	exit 1
	;;
esac
[ "${#subject}" -le "$SUBJECT_MAX" ] || {
	echo "commit-finding: the subject is ${#subject} characters, over $SUBJECT_MAX" >&2
	exit 1
}
self_login=$(sed -n 's/^self_login //p' "$dir/meta.txt")
self_email=$(sed -n 's/^self_email //p' "$dir/meta.txt")
[ -n "$self_login" ] && [ -n "$self_email" ] || {
	echo "commit-finding: meta.txt records no self_login and self_email" >&2
	exit 1
}

git -C "$worktree" add -- "$@"
if git -C "$worktree" diff --cached --quiet; then
	echo "commit-finding: nothing to commit for $id in: $*" >&2
	exit 3
fi
git -C "$worktree" -c "user.name=$self_login" -c "user.email=$self_email" \
	commit --quiet -m "$subject" -m "Addresses $id."
sha=$(git -C "$worktree" rev-parse --short HEAD)
sh "$(dirname -- "$0")/update-finding.sh" "$dir" "$id" status=addressed "commit=$sha" >/dev/null
echo "commit-finding: $id addressed in $sha"
