#!/bin/sh
# Summarize the stats ledger: outcomes, rounds, finding totals, routes.
# Usage: sh scripts/stats-report.sh <data-root>
set -eu

root=${1:?usage: stats-report.sh <data-root>}
stats="$root/state/stats.txt"
if [ ! -f "$stats" ]; then
	echo "stats-report: no finished runs recorded"
	exit 0
fi

awk '
{
	for (i = 1; i < NF; i += 2) v[$i] = $(i + 1)
	runs++
	oc[v["outcome"]]++
	r = v["rounds"] + 0; if (r > 4) r = 4
	hist[r]++
	findings += v["findings"]; verified += v["verified"]
	wontfix += v["wont-fix"]; demoted += v["demoted"]
	contracts += v["contracts"]; seams += v["seams"]
	cheap += v["cheap"]; base += v["base"]; strong += v["strong"]; wanted += v["strong_wanted"]; esc += v["escalations"]
	if (v["reopens"] + 0 > 0) reopened++
	delete v
}
END {
	printf "stats-report: runs %d merged %d parked %d held %d review-only %d\n", \
		runs, oc["merged"] + 0, oc["parked"] + 0, oc["held"] + 0, oc["review-only"] + 0
	printf "stats-report: rounds 0:%d 1:%d 2:%d 3:%d 4:%d runs-with-reopens %d\n", \
		hist[0] + 0, hist[1] + 0, hist[2] + 0, hist[3] + 0, hist[4] + 0, reopened + 0
	printf "stats-report: findings %d verified %d wont-fix %d demoted %d contracts %d seams %d\n", \
		findings, verified, wontfix, demoted, contracts, seams
	printf "stats-report: routes cheap %d base %d strong %d strong-wanted %d escalations %d\n", \
		cheap, base, strong, wanted, esc
}
' "$stats"
