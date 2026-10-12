#!/bin/sh
# Reap runs whose pull request closed, then apply retention per repository.
# Usage: sh scripts/sweep-state.sh <state-dir> [keep]
# Without a count, the run's resolved keep_ledgers is used.
#
# Runs at the start of every review and after every merge, so a pull
# request merged or closed outside this tool is reaped at the next
# opportunity in any repository, not only its own. A run is live while
# its pull request is open: in progress (its worktree exists), or
# recorded by run-stats.sh as held, parked, or review-only, since a
# held run drops its worktree and resumes from the ledger alone. Live
# runs are never pruned; a closed one is marked in outcome.txt and
# counts as finished from then on. The current run is never pruned.
set -eu

dir=${1:?usage: sweep-state.sh <state-dir> <keep>}
keep=${2:-$(sh "$(dirname "$0")/setting.sh" "$dir" keep_ledgers)}
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
scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$dir/.." && pwd)
current=${dir##*/}

live() {
	[ -d "$1/worktree" ] && return 0
	case "$(cat "$1/outcome.txt" 2>/dev/null)" in
	held | parked | review-only) return 0 ;;
	esac
	return 1
}

swept=0
for sib in "$root"/*; do
	[ -d "$sib" ] || continue
	[ "${sib##*/}" = "$current" ] && continue
	[ -f "$sib/meta.txt" ] || continue
	live "$sib" || continue
	owner=$(sed -n 's/^owner //p' "$sib/meta.txt")
	repo=$(sed -n 's/^repo //p' "$sib/meta.txt")
	pr=$(sed -n 's/^pr //p' "$sib/meta.txt")
	[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr" ] || continue
	state=$(gh pr view "$pr" --repo "$owner/$repo" --json state --jq .state 2>/dev/null) || continue
	[ "$state" = "OPEN" ] && continue
	[ ! -d "$sib/worktree" ] || sh "$scripts_dir/cleanup-state.sh" "$sib" >/dev/null
	printf 'closed\n' >"$sib/outcome.txt"
	swept=$((swept + 1))
done

pruned=0
kept=0
cd "$root"
for prefix in $(ls -1d -- */ 2>/dev/null | sed -n 's/__[0-9][0-9]*\/$/__/p' | sort -u); do
	n=0
	for name in $(ls -1td -- "$prefix"* 2>/dev/null); do
		sib="$root/$name"
		[ -d "$sib" ] || continue
		live "$sib" && continue
		n=$((n + 1))
		kept=$((kept + 1))
		[ "$n" -gt "$keep" ] || continue
		[ "$name" != "$current" ] || continue
		rm -rf "$sib"
		pruned=$((pruned + 1))
		kept=$((kept - 1))
	done
done

echo "sweep-state: stale $swept pruned $pruned kept $kept"
