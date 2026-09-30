#!/bin/sh
# Report finding counts by status. Exit 0 when converged, 3 while open remain.
# Usage: sh scripts/count-findings.sh <state-dir> [--list]
set -eu

dir=${1:?usage: count-findings.sh <state-dir> [--list]}
list=${2:-}
case "$list" in
'' | --list) ;;
*)
	echo "count-findings: unknown argument: $list" >&2
	exit 1
	;;
esac
findings="$dir/findings"
[ -d "$findings" ] || {
	echo "count-findings: no findings directory in $dir" >&2
	exit 1
}

open=0 addressed=0 verified=0 wontfix=0 max_reopens=0
open_ids='' addressed_ids='' verified_ids='' wontfix_ids=''
mech_ids='' capped_ids=''
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	status=$(sed -n 's/^status: //p' "$f")
	case "$status" in
	open)
		open=$((open + 1))
		open_ids="$open_ids ${f##*/}"
		sev=$(sed -n 's/^severity: //p' "$f")
		case "$sev" in
		minor | nit)
			grep -q '^```suggestion' "$f" && mech_ids="$mech_ids ${f##*/}"
			;;
		esac
		;;
	addressed)
		addressed=$((addressed + 1))
		addressed_ids="$addressed_ids ${f##*/}"
		;;
	verified)
		verified=$((verified + 1))
		verified_ids="$verified_ids ${f##*/}"
		;;
	wont-fix)
		wontfix=$((wontfix + 1))
		wontfix_ids="$wontfix_ids ${f##*/}"
		;;
	*)
		echo "count-findings: ${f##*/} has bad status: $status" >&2
		exit 1
		;;
	esac
	r=$(sed -n 's/^reopens: //p' "$f")
	[ "$r" -gt "$max_reopens" ] && max_reopens=$r
	[ "$r" -gt 2 ] && capped_ids="$capped_ids ${f##*/}"
done

echo "open $open addressed $addressed verified $verified wont-fix $wontfix max_reopens $max_reopens"
if [ "$list" = "--list" ]; then
	echo "open_ids$open_ids"
	echo "addressed_ids$addressed_ids"
	echo "verified_ids$verified_ids"
	echo "wont_fix_ids$wontfix_ids"
	echo "open_mechanical_ids$mech_ids"
	echo "capped_ids$capped_ids"
fi
[ "$open" -eq 0 ]  || exit 3
