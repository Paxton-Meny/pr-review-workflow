#!/bin/sh
# Reap sibling ledgers whose pull request closed, then apply retention.
# Usage: sh scripts/sweep-state.sh <state-dir> <keep>
set -eu

dir=${1:?usage: sweep-state.sh <state-dir> <keep>}
keep=${2:?usage: sweep-state.sh <state-dir> <keep>}
case "$keep" in
'' | *[!0-9]* | 0)
	echo "sweep-state: keep must be a positive number: $keep" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "sweep-state: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$dir/.." && pwd)
prefix="${owner}__${repo}__"

swept=0
for sib in "$root/$prefix"*; do
	[ -d "$sib" ] || continue
	[ -d "$sib/worktree" ] || continue
	[ "$sib" = "$root/${dir##*/}" ] && continue
	pr=$(sed -n 's/^pr //p' "$sib/meta.txt" 2>/dev/null)
	[ -n "$pr" ] || continue
	state=$(gh pr view "$pr" --repo "$owner/$repo" --json state --jq .state 2>/dev/null) || continue
	[ "$state" = "OPEN" ] && continue
	sh "$scripts_dir/cleanup-state.sh" "$sib" >/dev/null
	swept=$((swept + 1))
done

pruned=0
kept=0
cd "$root"
for name in $(ls -1td "$prefix"* 2>/dev/null); do
	sib="$root/$name"
	[ -d "$sib" ] || continue
	[ -d "$sib/worktree" ] && continue
	kept=$((kept + 1))
	if [ "$kept" -gt "$keep" ]; then
		rm -rf "$sib"
		pruned=$((pruned + 1))
		kept=$((kept - 1))
	fi
done

echo "sweep-state: $swept stale runs cleaned, $pruned old ledgers pruned, $kept kept"
