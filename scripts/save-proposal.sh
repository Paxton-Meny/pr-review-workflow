#!/bin/sh
# Validate the assembler's conventions block proposal from stdin and file
# it under the survey.
# Usage: sh scripts/save-proposal.sh <survey-dir> < proposal
#
# The proposal is the body of a review-conventions block: at most 30
# non-empty lines, no markers, no URLs, no absolute paths, and every
# token that names a path must be a ref in digest.txt or a directory
# above one, so the map says nothing the verified claims do not back.
# Writes conventions-proposal.md atomically and prints one line:
# "proposal: lines N paths N".
set -eu

dir=${1:?usage: save-proposal.sh <survey-dir>}
[ -f "$dir/digest.txt" ] || {
	echo "save-proposal: no digest.txt in $dir, run verify-claims.sh first" >&2
	exit 1
}
MAX_LINES=30

tmp=$(mktemp "$dir/.proposal.XXXXXX")
trap 'rm -f "$tmp" "$tmp.line"' EXIT
tr -d '\r' >"$tmp"

awk -v max_lines="$MAX_LINES" -v digest="$dir/digest.txt" '
function fail(msg) { printf "save-proposal: line %d: %s\n", NR, msg > "/dev/stderr"; exit 1 }
function known(tok,    r) {
	if (tok in refs) return 1
	for (r in refs) if (index(r, tok "/") == 1 || index(r, tok) == 1 && substr(r, length(tok) + 1, 1) == "/") return 1
	return 0
}
BEGIN {
	while ((getline line < digest) > 0) {
		ref = line; sub(/^[0-9]+ [a-z]+ /, "", ref); sub(/ \| .*$/, "", ref)
		refs[ref] = 1
		d = ref; sub(/\/\*\*$/, "", d); sub(/\/$/, "", d); refs[d] = 1
		while (sub(/\/[^\/]*$/, "", d)) refs[d] = 1
	}
}
{
	if ($0 ~ /^[ \t]*$/) next
	lines++
	if (lines > max_lines) fail("more than " max_lines " lines")
	if (index($0, "<!-- review-conventions")) fail("the markers are added where the block is written, not in the proposal")
	if ($0 ~ /:\/\//) fail("a URL has no place in the map")
	n = split($0, tok, /[ \t]+/)
	for (i = 1; i <= n; i++) {
		w = tok[i]
		gsub(/^[`("'"'"'\[]+|[`)"'"'"'\],.;:]+$/, "", w)
		if (w == "") continue
		if (w ~ /^\//) fail("absolute path: " w)
		if (w in refs) { paths++; continue }
		if (index(w, "/") == 0) continue
		if (w ~ /^[0-9]+\/[0-9]+$/) continue
		sub(/\/\*\*$/, "", w); sub(/\/$/, "", w)
		if (!known(w)) fail("path not in the verified digest: " w)
		paths++
	}
}
END { if (lines == 0) fail("empty proposal"); printf "proposal: lines %d paths %d\n", lines, paths }
' "$tmp" >"$tmp.line"
mv "$tmp" "$dir/conventions-proposal.md"
cat "$tmp.line"
rm -f "$tmp.line"
trap - EXIT
