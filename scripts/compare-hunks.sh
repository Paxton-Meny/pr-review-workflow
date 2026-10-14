#!/bin/sh
# Judge how closely two sets of hunks touch, file by file.
# Usage: sh scripts/compare-hunks.sh <ours.ranges> <theirs.ranges>
# Both inputs come from hunk-ranges.sh and must be in the same old-side
# coordinates: both diffs taken against the same base commit. The
# comparison is on the old side only, since that is the side the two
# diffs share.
#
# Each shared file gets one line, tab-separated: level, path, our range,
# their range, and the function the pair shares (empty when none),
# naming the closest pair. Levels: same when the ranges intersect; near
# when they lie within NEAR_LINES of each other or their hunk headers
# name the same enclosing function; disjoint otherwise. A final line
# sums it up:
#   level <same|near|disjoint|none> files <shared> near <n> same <m>
# where none means no file is shared. Exit 0 always; callers read the
# level.
set -eu

NEAR_LINES=12

ours=${1:?usage: compare-hunks.sh <ours.ranges> <theirs.ranges>}
theirs=${2:?usage: compare-hunks.sh <ours.ranges> <theirs.ranges>}
[ -f "$ours" ] && [ -f "$theirs" ] || {
	echo "compare-hunks: both range files must exist" >&2
	exit 1
}

awk -F '\t' -v near_lines="$NEAR_LINES" -v theirs="$theirs" '
function rank(level) { return (level == "same") ? 2 : (level == "near") ? 1 : 0 }
function judge(alo, ahi, blo, bhi, afn, bfn,    gap) {
	if (alo <= bhi && blo <= ahi) return "same"
	gap = (alo > bhi) ? alo - bhi : blo - ahi
	if (gap <= near_lines) return "near"
	if (afn != "" && afn == bfn) return "near"
	return "disjoint"
}
BEGIN {
	while ((getline line < theirs) > 0) {
		split(line, f, "\t")
		if (f[1] == "") continue
		n = ++count[f[1]]
		tlo[f[1], n] = f[2] + 0; thi[f[1], n] = f[3] + 0; tfn[f[1], n] = f[6]
	}
	close(theirs)
}
NF >= 5 && $1 != "" && ($1 in count) {
	path = $1; lo = $2 + 0; hi = $3 + 0; fn = $6
	for (i = 1; i <= count[path]; i++) {
		level = judge(lo, hi, tlo[path, i], thi[path, i], fn, tfn[path, i])
		if (!(path in best) || rank(level) > rank(best[path])) {
			if (!(path in best)) order[++shared] = path
			best[path] = level
			ours_r[path] = lo "-" hi
			theirs_r[path] = tlo[path, i] "-" thi[path, i]
			shared_fn[path] = (fn != "" && fn == tfn[path, i]) ? fn : ""
		}
	}
}
END {
	top = "none"
	for (i = 1; i <= shared; i++) {
		path = order[i]
		printf "%s\t%s\t%s\t%s\t%s\n", best[path], path, ours_r[path], theirs_r[path], shared_fn[path]
		if (best[path] == "near") nears++
		if (best[path] == "same") sames++
		if (top == "none" || rank(best[path]) > rank(top)) top = best[path]
	}
	printf "level %s files %d near %d same %d\n", top, shared, nears + 0, sames + 0
}
' "$ours"
