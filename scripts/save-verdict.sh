#!/bin/sh
# Record the comparer's verdict on one overlap bundle. The report arrives
# on stdin.
# Usage: sh scripts/save-verdict.sh <state-dir> <label>
# The label is "base" (commits that landed on the base) or "pr-<n>" (an
# open pull request); its bundle under pr-context/overlap/<label>/ must
# exist. The report must hold exactly one line of the form
#   verdict <label> <independent|complementary|duplicate|contradictory>: <reason>
# which is written to the bundle's verdict.txt beside the base the
# bundle was built on, so a later merge can tell a stale verdict from a
# current one. Anything else is refused and nothing is written.
set -eu

dir=${1:?usage: save-verdict.sh <state-dir> <label>}
label=${2:?usage: save-verdict.sh <state-dir> <label>}
case "$label" in
base) ;;
pr-[0-9]*) [ "$label" = "pr-$(printf '%s' "${label#pr-}" | tr -cd '0-9')" ] || label='' ;;
*) label='' ;;
esac
[ -n "$label" ] || {
	echo "save-verdict: label must be base or pr-<number>" >&2
	exit 1
}
bundle="$dir/pr-context/overlap/$label"
[ -f "$bundle/summary.txt" ] || {
	echo "save-verdict: no overlap bundle for $label in $dir" >&2
	exit 1
}

report=$(tr -d '\r' | sed '/^[[:space:]]*$/d')
[ "$(printf '%s\n' "$report" | grep -c .)" -eq 1 ] || {
	echo "save-verdict: the report must be exactly one verdict line" >&2
	exit 1
}
kind=$(printf '%s\n' "$report" | sed -n "s/^verdict $label \(independent\|complementary\|duplicate\|contradictory\): ..*/\1/p")
[ -n "$kind" ] || {
	echo "save-verdict: not a verdict line for $label: $report" >&2
	exit 1
}

tmp=$(mktemp "$bundle/.verdict.XXXXXX")
{
	printf 'label %s\n' "$label"
	sed -n 's/^base .*/&/p' "$bundle/summary.txt" | head -n 1
	printf '%s\n' "$report"
} >"$tmp"
mv "$tmp" "$bundle/verdict.txt"
echo "save-verdict: $label $kind"
