#!/bin/sh
# Tell whether the pull request's head moved past the head the review covered.
# Usage: sh scripts/reviewed-head.sh <state-dir> [--mark]
# Without --mark the head is read from GitHub. It is current (exit 0)
# when it is the head the review last covered or this run last pushed.
# Otherwise someone pushed since: the new head becomes head_sha in
# meta.txt, so a fetch and checkout follow it, and the line names both
# heads (exit 3): fetch and check out again, review the files
# "round-diff.sh <dir> --all <reviewed>" lists, then run --mark, which
# records head_sha as the head the review covered. merge-pr.sh refuses
# a head the review did not cover, so nothing pushed after the review
# merges unread.
set -eu

dir=${1:?usage: reviewed-head.sh <state-dir> [--mark]}
mark=0
case "${2:-}" in
'') ;;
--mark) mark=1 ;;
*)
	echo "reviewed-head: unknown argument: $2" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "reviewed-head: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
reviewed=$(sed -n 's/^reviewed_head //p' "$dir/meta.txt")
[ -n "$reviewed" ] || reviewed=$head_sha

rewrite() {
	# rewrite <field> <value>: replace or add one meta.txt line
	tmp=$(mktemp "$dir/.meta.XXXXXX")
	sed "/^$1 /d" "$dir/meta.txt" >"$tmp"
	printf '%s %s\n' "$1" "$2" >>"$tmp"
	mv "$tmp" "$dir/meta.txt"
}

if [ "$mark" -eq 1 ]; then
	[ -n "$head_sha" ] || {
		echo "reviewed-head: meta.txt records no head_sha" >&2
		exit 1
	}
	rewrite reviewed_head "$head_sha"
	echo "reviewed-head: reviewed $head_sha"
	exit 0
fi

live=$(gh pr view "$pr" --repo "$owner/$repo" --json headRefOid --jq .headRefOid)
case "$live" in
'' | *[!0-9a-f]*)
	echo "reviewed-head: GitHub reported no head commit for $owner/$repo#$pr" >&2
	exit 1
	;;
esac
if [ "$live" = "$reviewed" ]; then
	echo "reviewed-head: current $live"
	exit 0
fi
rewrite head_sha "$live"
echo "reviewed-head: moved $reviewed $live"
exit 3
