#!/bin/sh
# Report what the review phase (steps 5 and 6) still owes, from the ledger.
# Usage: sh scripts/review-progress.sh <state-dir>
#
# route-models.sh records the review plan in review.txt, save-findings.sh
# --unit records each report saved, dedup-findings.sh each dedup, and a
# skipped gap pass its skip. Exit 0 prints "review-progress: complete".
# Exit 3 prints "review-progress: pending" and then one line per item
# still owed, in the order to run them:
#   review not planned               step 5 never routed its reviewers
#   review <unit> needs <k> of <n>   k more reviewers of that unit to save
#   dedup not run                    samples above 1 saved findings
#   gap not run                      neither saved nor skipped
# A ledger without review.txt predates the record: it counts as complete
# once it holds findings, and as not planned otherwise.
set -eu

dir=${1:?usage: review-progress.sh <state-dir>}
[ -d "$dir" ] || {
	echo "review-progress: no state directory $dir" >&2
	exit 1
}
file="$dir/review.txt"
if [ ! -f "$file" ]; then
	for f in "$dir/findings"/F*; do
		[ -f "$f" ] || continue
		echo "review-progress: complete, recorded before progress was kept"
		exit 0
	done
	printf 'review-progress: pending\nreview not planned\n'
	exit 3
fi

awk '
$1 == "plan" { split("", samples); split("", order); n = 0; next }
$1 == "planned" {
	if (!($2 in samples)) order[++n] = $2
	samples[$2] = $4 + 0
	next
}
$1 == "saved" && $2 == "gap" { gap = 1; next }
$1 == "saved" { saved[$2]++; records += $3; next }
$1 == "dedup" { dedup = 1; next }
$1 == "gap" { gap = 1; next }
END {
	if (n == 0) owed[++k] = "review not planned"
	most = 0
	for (i = 1; i <= n; i++) {
		u = order[i]
		if (samples[u] > most) most = samples[u]
		if (saved[u] < samples[u]) {
			owed[++k] = sprintf("review %s needs %d of %d", u, samples[u] - saved[u], samples[u])
			units = 1
		}
	}
	if (n > 0 && !units && most > 1 && records > 0 && !dedup) owed[++k] = "dedup not run"
	if (!gap) owed[++k] = "gap not run"
	if (k == 0) {
		print "review-progress: complete"
		exit 0
	}
	print "review-progress: pending"
	for (i = 1; i <= k; i++) print owed[i]
	exit 3
}
' "$file"
