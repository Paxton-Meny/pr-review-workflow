#!/bin/sh
# Record the precision filter's one-line result in the ledger.
# Usage: printf '%s\n' "filter: demoted M of N" | sh scripts/filter-result.sh <state-dir>
# The filter runs it last, with the line it is about to report:
# "filter: demoted M of N" or "filter: skipped (<what stopped it>)".
# The line is kept in filter.txt, where run-stats.sh tells a pass that
# read nothing from one that found nothing to demote, and from a filter
# that was routed and never reported.
set -eu

dir=${1:?usage: filter-result.sh <state-dir>   (the result line on stdin)}
[ -f "$dir/meta.txt" ] || {
	echo "filter-result: no meta.txt in $dir" >&2
	exit 1
}
line=$(cat)
if [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" -ne 1 ] || ! printf '%s\n' "$line" | grep -qx -e 'filter: demoted [0-9][0-9]* of [0-9][0-9]*' -e 'filter: skipped ([^()]*)'; then
	echo "filter-result: expected \"filter: demoted M of N\" or \"filter: skipped (<why>)\" on one line" >&2
	exit 1
fi
tmp=$(mktemp "$dir/.filter.XXXXXX")
printf '%s\n' "$line" >"$tmp"
mv "$tmp" "$dir/filter.txt"
echo "filter-result: recorded"
