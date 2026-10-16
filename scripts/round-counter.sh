#!/bin/sh
# Advance a persistent round counter, enforcing its cap.
# Usage: sh scripts/round-counter.sh <state-dir> next <max>
#        sh scripts/round-counter.sh <state-dir> next ci
# The remediation rounds live in rounds.txt under the cap given; the
# repairs of failing checks live in ci-rounds.txt under the run's
# ci_fix_rounds setting. Exit 3 when the cap is reached. Each round
# started ("round <n>", "ci-round <n>") and each cap met ("round cap",
# "ci-round cap") is journaled in steps.txt for next-step.sh.
set -eu

dir=${1:?usage: round-counter.sh <state-dir> next <max|ci>}
op=${2:?usage: round-counter.sh <state-dir> next <max|ci>}
max=${3:?usage: round-counter.sh <state-dir> next <max|ci>}
[ "$op" = "next" ] || {
	echo "round-counter: unknown operation: $op" >&2
	exit 1
}
[ -f "$dir/meta.txt" ] || {
	echo "round-counter: no meta.txt in $dir" >&2
	exit 1
}
counter=rounds
label=round
event=round
if [ "$max" = ci ]; then
	counter=ci-rounds
	label='ci round'
	event=ci-round
	max=$(sh "$(dirname -- "$0")/setting.sh" "$dir" ci_fix_rounds)
fi
case "$max" in
'' | *[!0-9]*)
	echo "round-counter: max must be numeric: $max" >&2
	exit 1
	;;
esac

current=0
[ -f "$dir/$counter.txt" ] && current=$(cat "$dir/$counter.txt")
next=$((current + 1))
if [ "$next" -gt "$max" ]; then
	printf '%s cap\n' "$event" >>"$dir/steps.txt"
	echo "round-counter: $label cap of $max reached" >&2
	exit 3
fi
tmp=$(mktemp "$dir/.rounds.XXXXXX")
printf '%d\n' "$next" >"$tmp"
mv "$tmp" "$dir/$counter.txt"
printf '%s %d\n' "$event" "$next" >>"$dir/steps.txt"
echo "$label $next of $max"
