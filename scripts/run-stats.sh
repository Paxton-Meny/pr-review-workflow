#!/bin/sh
# Append one summary line per finished run to the state root's stats file.
# Usage: sh scripts/run-stats.sh <state-dir> <outcome>
#
# The stats file is the evidence loop: routing thresholds, the gap-pass
# rule, and the filter earn their tuning from these lines instead of
# guesses. Run it before cleanup-state.sh, which removes pr-context.
set -eu

dir=${1:?usage: run-stats.sh <state-dir> <outcome>}
outcome=${2:?usage: run-stats.sh <state-dir> <outcome>}
case "$outcome" in
merged | parked | held | review-only) ;;
*)
	echo "run-stats: outcome must be merged, parked, held, or review-only: $outcome" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "run-stats: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

rounds=0
[ -f "$dir/rounds.txt" ] && rounds=$(cat "$dir/rounds.txt")

total=0 verified=0 wontfix=0 open=0 reopens=0 demoted=0 contracts=0 samples=1
for f in "$dir/findings"/F*; do
	[ -f "$f" ] || continue
	total=$((total + 1))
	case "$(sed -n 's/^status: //p' "$f")" in
	verified) verified=$((verified + 1)) ;;
	wont-fix) wontfix=$((wontfix + 1)) ;;
	open | addressed) open=$((open + 1)) ;;
	esac
	r=$(sed -n 's/^reopens: //p' "$f")
	[ "${r:-0}" -gt "$reopens" ] && reopens=$r
	grep -q '^Filter: ' "$f" && demoted=$((demoted + 1))
	grep -q '^Check: ' "$f" && contracts=$((contracts + 1))
	s=$(sed -n 's/^support: [0-9]*\///p' "$f" | head -n 1)
	[ "${s:-1}" -gt "$samples" ] && samples=$s
done

kind=none
[ -f "$dir/pr-context/class.txt" ] &&
	kind=$(sed -n 's/^classify-change: kind \([a-z-]*\).*/\1/p' "$dir/pr-context/class.txt")
groups=1
[ -f "$dir/pr-context/shards.txt" ] && groups=$(grep -c . "$dir/pr-context/shards.txt")
seams=0
[ -f "$dir/pr-context/seams.txt" ] && seams=$(grep -c . "$dir/pr-context/seams.txt")

root=$(CDPATH= cd -- "$dir/.." && pwd)
line="run $owner/$repo#$pr outcome $outcome rounds $rounds findings $total verified $verified wont-fix $wontfix unresolved $open reopens $reopens demoted $demoted contracts $contracts samples $samples kind $kind groups $groups seams $seams"
printf '%s\n' "$line" >>"$root/stats.txt"
echo "run-stats: $line"
