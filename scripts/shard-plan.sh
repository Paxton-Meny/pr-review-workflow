#!/bin/sh
# Plan reviewer shards: cluster coupled files, balance groups, name seams.
# Usage: sh scripts/shard-plan.sh <state-dir> [max-groups] [shard-lines]
#
# Files whose added lines mention another changed file's name stem are
# clustered together, clusters are packed into line-balanced groups in
# diff order, and any coupling that still crosses a group boundary is
# recorded in seams.txt for the gap pass. Each pair of changed files
# that reference each other counts as one coupling, pairs with a docs
# file left out: the total, then one "group <g> <n>" line per group,
# is saved in couplings.txt for route-models.sh. The plan persists in
# shards.txt, so a resumed run shards identically. Max-groups defaults
# to 4. Shard-lines defaults to the run's cost posture (economy 2250,
# balanced 1500, quality 1000, read from the resolved settings when
# there are any), so a cheaper run keeps one reviewer, and so skips the
# gap pass a sharded review always gets, up to a larger change, and a
# more thorough run puts a second reader on a smaller one. A change
# under the limit is one group and no shards.txt: it is not a sharded
# review. The result line names the couplings and the limit used.
set -eu

dir=${1:?usage: shard-plan.sh <state-dir> [max-groups] [shard-lines]}
maxg=${2:-4}
tl=${3:-}
ctx="$dir/pr-context"
[ -f "$ctx/diff-index.txt" ] && [ -s "$ctx/diff-index.txt" ] || {
	echo "shard-plan: no diff-index.txt in $ctx, run fetch-pr.sh first" >&2
	exit 1
}
if [ -z "$tl" ]; then
	posture=balanced
	[ -f "$dir/settings.txt" ] && posture=$(sh "$(dirname "$0")/setting.sh" "$dir" cost_posture)
	case "$posture" in
	economy) tl=2250 ;;
	balanced) tl=1500 ;;
	quality) tl=1000 ;;
	*)
		echo "shard-plan: posture must be quality, balanced, or economy: $posture" >&2
		exit 1
		;;
	esac
fi
case "$maxg$tl" in
*[!0-9]*)
	echo "shard-plan: max-groups and shard-lines must be numbers" >&2
	exit 1
	;;
esac

rm -f "$ctx/shards.txt" "$ctx/seams.txt" "$ctx/couplings.txt"

set --
while IFS='	' read -r n _p; do
	set -- "$@" "$ctx/files/$n.diff"
done <"$ctx/diff-index.txt"

plan=$(awk -v idx="$ctx/diff-index.txt" -v cnt="$ctx/files.txt" \
	-v maxg="$maxg" -v tl="$tl" -v kinds="$ctx/files-kind.txt" \
	-v shards="$ctx/shards.txt" -v seams="$ctx/seams.txt" -v couplings="$ctx/couplings.txt" '
function find(x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x] } return x }
function join(a, b,   ra, rb) {
	ra = find(a); rb = find(b)
	if (ra == rb) return
	if (ra < rb) parent[rb] = ra; else parent[ra] = rb
}
BEGIN {
	n = 0
	while ((getline line < idx) > 0) {
		split(line, a, "\t"); n++; num[n] = a[1]; path[n] = a[2]; id[a[1]] = n
	}
	close(idx)
	while ((getline line < cnt) > 0) {
		split(line, a, "\t"); pl[a[1]] = a[2] + a[3]
	}
	close(cnt)
	while ((getline line < kinds) > 0) {
		split(line, a, "\t"); cls[a[1]] = a[3]
	}
	close(kinds)
	total = 0
	for (i = 1; i <= n; i++) { fl[i] = pl[path[i]] + 0; total += fl[i] }
	split("main test tests index util utils init setup mod lib app core base common config types data", sw, " ")
	for (k in sw) stop[sw[k]] = 1
	for (i = 1; i <= n; i++) {
		b = path[i]; sub(/.*\//, "", b); s = b; sub(/\..*$/, "", s)
		sub(/^test_/, "", s); sub(/_test$/, "", s); sub(/_spec$/, "", s)
		if (length(s) < 4 || stop[s] || s !~ /^[A-Za-z0-9_-]+$/) s = ""
		stem[i] = s
		if (s != "") re[i] = "(^|[^A-Za-z0-9_])" s "([^A-Za-z0-9_]|$)"
		parent[i] = i
	}
}
FNR == 1 {
	fb = FILENAME; sub(/.*\//, "", fb); sub(/\.diff$/, "", fb); cur = id[fb] + 0
}
/^R[0-9]+ \+/ {
	if (cur == 0) next
	for (i = 1; i <= n; i++) {
		if (i == cur || stem[i] == "") continue
		if (match($0, re[i])) {
			if (!((cur SUBSEP i) in edge) && !((i SUBSEP cur) in edge))
				edge[cur, i] = stem[i]
			join(cur, i)
		}
	}
}
END {
	gneed = int((total + tl - 1) / tl)
	if (gneed < 1) gneed = 1
	if (gneed > maxg) gneed = maxg
	bal = int((total + gneed - 1) / gneed)
	if (bal < tl) bal = tl
	for (i = 1; i <= n; i++) { r = find(i); croot[i] = r; clines[r] += fl[i] }
	ucount = 0
	for (i = 1; i <= n; i++) {
		r = croot[i]
		if (clines[r] > bal * 1.25) {
			if (!(r in uacc) || uacc[r] + fl[i] > bal) { ucount++; ulast[r] = ucount; uacc[r] = 0 }
			unit[i] = ulast[r]; uacc[r] += fl[i]
		} else {
			if (!(r in uwhole)) { ucount++; uwhole[r] = ucount }
			unit[i] = uwhole[r]
		}
		ulines[unit[i]] += fl[i]
	}
	g = 1
	for (u = 1; u <= ucount; u++) {
		if (gl[g] > 0 && gl[g] + ulines[u] > bal && g < gneed) g++
		ug[u] = g; gl[g] += ulines[u]
	}
	gcount = g
	for (i = 1; i <= n; i++) fg[i] = ug[unit[i]]
	for (gi = 1; gi <= gcount; gi++) {
		printf "group %d lines %d files", gi, gl[gi] > shards
		for (i = 1; i <= n; i++) if (fg[i] == gi) printf " %s", num[i] > shards
		printf "\n" > shards
	}
	close(shards)
	ccount = 0
	for (k in edge) {
		split(k, e, SUBSEP)
		if (cls[num[e[1]]] == "docs" || cls[num[e[2]]] == "docs") continue
		ccount++
		gcouple[fg[e[1]]]++
		if (fg[e[2]] != fg[e[1]]) gcouple[fg[e[2]]]++
	}
	printf "%d\n", ccount > couplings
	for (gi = 1; gi <= gcount; gi++) printf "group %d %d\n", gi, gcouple[gi] + 0 > couplings
	close(couplings)
	scount = 0
	for (i = 1; i <= n; i++)
		for (j = 1; j <= n; j++)
			if (((i SUBSEP j) in edge) && fg[i] != fg[j]) {
				scount++
				printf "%s and %s split across groups %d and %d (shared name: %s)\n", \
					path[i], path[j], fg[i], fg[j], edge[i, j] > seams
			}
	if (scount > 0) close(seams)
	printf "%d %d %d\n", gcount, scount, ccount
}
' "$@")
set -- $plan
groups=$1 seams=$2 couplings=$3
[ "$groups" -gt 1 ] || rm -f "$ctx/shards.txt"
echo "shard-plan: groups $groups seams $seams couplings $couplings limit $tl"
