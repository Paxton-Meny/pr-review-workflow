#!/bin/sh
# List recorded review runs, newest first, with their ledger counts.
# Usage: sh scripts/list-runs.sh <data-root> [all|owner/repo]
set -eu

root=${1:?usage: list-runs.sh <data-root> [all|owner/repo]}/state
filter=${2:-}
case "$filter" in
all) filter='' ;;
'')
	url=$(git remote get-url origin 2>/dev/null) || url=''
	if [ -n "$url" ]; then
		trimmed=${url%/}
		trimmed=${trimmed%.git}
		repo=${trimmed##*/}
		rest=${trimmed%/*}
		owner=${rest##*[:/]}
		[ -n "$owner" ] && [ -n "$repo" ] && filter="$owner/$repo"
	fi
	;;
esac

count=0
if [ -d "$root" ]; then
	cd "$root"
	for name in $(ls -1td -- */ 2>/dev/null); do
		dir="${name%/}"
		[ -f "$dir/meta.txt" ] || continue
		owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
		repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
		pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
		[ -z "$filter" ] || [ "$owner/$repo" = "$filter" ] || continue
		rounds=0
		[ -f "$dir/rounds.txt" ] && rounds=$(cat "$dir/rounds.txt")
		open=0 addressed=0 verified=0 wontfix=0
		for f in "$dir/findings"/F*; do
			[ -f "$f" ] || continue
			case "$(sed -n 's/^status: //p' "$f")" in
			open) open=$((open + 1)) ;;
			addressed) addressed=$((addressed + 1)) ;;
			verified) verified=$((verified + 1)) ;;
			wont-fix) wontfix=$((wontfix + 1)) ;;
			esac
		done
		live=no
		[ -d "$dir/worktree" ] && live=yes
		echo "run $owner/$repo#$pr rounds $rounds open $open addressed $addressed verified $verified wont-fix $wontfix resumable $live"
		count=$((count + 1))
	done
fi
echo "list-runs: $count runs${filter:+ for $filter}"
