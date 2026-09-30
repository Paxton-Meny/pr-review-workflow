#!/bin/sh
# Merge duplicate findings from parallel review samples; record support.
# Usage: sh scripts/dedup-findings.sh <state-dir> <samples>
#
# Two unposted open findings describe the same defect when they share a
# path and category and sit within three lines of each other. Each such
# cluster keeps its richest record (longest body, lowest id on ties),
# and the kept record gains a "support: k/N" header stating how many of
# the N samples reported it. Posted records are never touched, and a
# rerun changes nothing.
set -eu

dir=${1:?usage: dedup-findings.sh <state-dir> <samples>}
n=${2:?usage: dedup-findings.sh <state-dir> <samples>}
findings="$dir/findings"
[ -d "$findings" ] || {
	echo "dedup-findings: no findings directory in $dir" >&2
	exit 1
}
case "$n" in
'' | *[!0-9]* | 0)
	echo "dedup-findings: samples must be a positive number: $n" >&2
	exit 1
	;;
esac

field() { sed -n "s/^$2: //p" "$1" | head -n 1; }
bodysize() { awk 'f { c += length($0) + 1 } /^---$/ { f = 1 } END { print c + 0 }' "$1"; }

reps=''
merged=0
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	id=${f##*/}
	case "$id" in
	F[0-9][0-9][0-9]) ;;
	*) continue ;;
	esac
	[ "$(field "$f" status)" = "open" ] || continue
	[ -z "$(field "$f" placement)" ] || continue
	path=$(field "$f" path)
	cat=$(field "$f" category)
	line=$(field "$f" line)
	match=''
	for rep in $reps; do
		rf="$findings/$rep"
		[ "$(field "$rf" path)" = "$path" ] || continue
		[ "$(field "$rf" category)" = "$cat" ] || continue
		rl=$(field "$rf" line)
		d=$((line - rl))
		[ "$d" -ge -3 ] && [ "$d" -le 3 ] || continue
		match=$rep
		break
	done
	if [ -z "$match" ]; then
		reps="$reps $id"
		eval "sup_$id=1"
		continue
	fi
	merged=$((merged + 1))
	eval "count=\$sup_$match"
	if [ "$(bodysize "$f")" -gt "$(bodysize "$findings/$match")" ]; then
		rm -f "$findings/$match"
		reps=$(printf '%s' "$reps" | sed "s/ $match\$/ $id/;s/ $match / $id /")
		eval "sup_$id=$((count + 1))"
	else
		rm -f "$f"
		eval "sup_$match=$((count + 1))"
	fi
done

kept=0
for rep in $reps; do
	kept=$((kept + 1))
	rf="$findings/$rep"
	eval "count=\$sup_$rep"
	tmp=$(mktemp "$findings/.$rep.XXXXXX")
	awk -v s="support: $count/$n" '
	/^support: / { next }
	/^reopens: / { print; print s; next }
	{ print }
	' "$rf" >"$tmp"
	mv "$tmp" "$rf"
done

echo "dedup-findings: kept $kept merged $merged"
