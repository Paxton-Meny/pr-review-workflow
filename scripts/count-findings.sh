#!/bin/sh
# Report finding counts by status. Exit 0 when converged, 3 while open remain.
# Usage: sh scripts/count-findings.sh <state-dir>
set -eu

dir=${1:?usage: count-findings.sh <state-dir>}
findings="$dir/findings"
[ -d "$findings" ] || {
	echo "count-findings: no findings directory in $dir" >&2
	exit 1
}

open=0 addressed=0 verified=0 wontfix=0 max_reopens=0
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	status=$(sed -n 's/^status: //p' "$f")
	case "$status" in
	open) open=$((open + 1)) ;;
	addressed) addressed=$((addressed + 1)) ;;
	verified) verified=$((verified + 1)) ;;
	wont-fix) wontfix=$((wontfix + 1)) ;;
	*)
		echo "count-findings: ${f##*/} has bad status: $status" >&2
		exit 1
		;;
	esac
	r=$(sed -n 's/^reopens: //p' "$f")
	[ "$r" -gt "$max_reopens" ] && max_reopens=$r
done

echo "open $open addressed $addressed verified $verified wont-fix $wontfix max_reopens $max_reopens"
[ "$open" -eq 0 ]  || exit 3
