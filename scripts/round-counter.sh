#!/bin/sh
# Advance the persistent remediation round counter, enforcing the cap.
# Usage: sh scripts/round-counter.sh <state-dir> next <max>
set -eu

dir=${1:?usage: round-counter.sh <state-dir> next <max>}
op=${2:?usage: round-counter.sh <state-dir> next <max>}
max=${3:?usage: round-counter.sh <state-dir> next <max>}
[ "$op" = "next" ] || {
	echo "round-counter: unknown operation: $op" >&2
	exit 1
}
case "$max" in
'' | *[!0-9]*)
	echo "round-counter: max must be numeric: $max" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "round-counter: no meta.txt in $dir" >&2
	exit 1
}

current=0
[ -f "$dir/rounds.txt" ] && current=$(cat "$dir/rounds.txt")
next=$((current + 1))
if [ "$next" -gt "$max" ]; then
	echo "round-counter: round cap of $max reached" >&2
	exit 3
fi
tmp=$(mktemp "$dir/.rounds.XXXXXX")
printf '%d\n' "$next" >"$tmp"
mv "$tmp" "$dir/rounds.txt"
echo "round $next of $max"
