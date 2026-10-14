#!/bin/sh
# Validate the assembler's conventions block proposal from stdin and file
# it under the survey.
# Usage: sh scripts/save-proposal.sh <survey-dir> [--drop-lines] < proposal
#
# The proposal is the body of a review-conventions block: at most 30
# non-empty lines, no markers, no URLs, no absolute paths, and every
# token that names a path must be a ref in digest.txt or a directory
# above one, so the map says nothing the verified claims do not back.
# A token names a path when it holds a slash. A refusal prints one
# "save-proposal: line N: <reason>" line for every offence in the
# draft, not only the first, so one revision can fix them all. With
# --drop-lines the lines that offend, and any past the first 30, are
# left out instead, each named by a "save-proposal: dropped line N:
# <reason>" line, and the rest is filed; only a draft left with nothing
# is still refused. Writes conventions-proposal.md atomically and prints one line:
# "proposal: lines N paths N", with " dropped N" under --drop-lines.
set -eu

dir=${1:?usage: save-proposal.sh <survey-dir> [--drop-lines]}
drop=0
case "${2:-}" in
'') ;;
--drop-lines) drop=1 ;;
*)
	echo "save-proposal: usage: save-proposal.sh <survey-dir> [--drop-lines]" >&2
	exit 1
	;;
esac
[ -f "$dir/digest.txt" ] || {
	echo "save-proposal: no digest.txt in $dir, run verify-claims.sh first" >&2
	exit 1
}
MAX_LINES=30

tmp=$(mktemp "$dir/.proposal.XXXXXX")
trap 'rm -f "$tmp" "$tmp.in" "$tmp.line"' EXIT
tr -d '\r' >"$tmp.in"

awk -v max_lines="$MAX_LINES" -v digest="$dir/digest.txt" -v drop="$drop" -v out="$tmp" '
function known(tok,    r) {
	if (tok in refs) return 1
	for (r in refs) if (index(r, tok "/") == 1 || index(r, tok) == 1 && substr(r, length(tok) + 1, 1) == "/") return 1
	return 0
}
function offend(msg) { if (NR in why) msg = why[NR] "; " msg; why[NR] = msg }
BEGIN {
	while ((getline line < digest) > 0) {
		ref = line; sub(/^[0-9]+ [a-z]+ /, "", ref); sub(/ \| .*$/, "", ref)
		refs[ref] = 1
		d = ref; sub(/\/\*\*$/, "", d); sub(/\/$/, "", d); refs[d] = 1
		while (sub(/\/[^\/]*$/, "", d)) refs[d] = 1
	}
}
{
	text[NR] = $0
	if ($0 ~ /^[ \t]*$/) next
	np = 0
	if (index($0, "<!-- review-conventions")) offend("the markers are added where the block is written, not in the proposal")
	if ($0 ~ /:\/\//) offend("a URL has no place in the map")
	n = split($0, tok, /[ \t]+/)
	for (i = 1; i <= n; i++) {
		w = tok[i]
		gsub(/^[`("'"'"'\[]+|[`)"'"'"'\],.;:]+$/, "", w)
		if (w == "") continue
		if (w ~ /^\//) { offend("absolute path: " w); continue }
		if (w in refs) { np++; continue }
		if (index(w, "/") == 0) continue
		if (w ~ /^[0-9]+\/[0-9]+$/) continue
		sub(/\/\*\*$/, "", w); sub(/\/$/, "", w)
		if (!known(w)) { offend("path not in the verified digest: " w); continue }
		np++
	}
	paths[NR] = np
}
END {
	lines = 0; total = 0; dropped = 0; bad = 0; nonempty = 0
	for (i = 1; i <= NR; i++) {
		if (text[i] ~ /^[ \t]*$/) { keep[i] = 1; continue }
		nonempty++
		if (i in why) {
			if (drop) { printf "save-proposal: dropped line %d: %s\n", i, why[i]; dropped++; continue }
			printf "save-proposal: line %d: %s\n", i, why[i] > "/dev/stderr"; bad++; continue
		}
		if (drop && lines >= max_lines) { printf "save-proposal: dropped line %d: beyond the first %d lines\n", i, max_lines; dropped++; continue }
		keep[i] = 1; lines++; total += paths[i]
	}
	if (!drop && nonempty > max_lines) { printf "save-proposal: line %d: more than %d lines\n", NR, max_lines > "/dev/stderr"; bad++ }
	if (!bad && lines == 0) { printf "save-proposal: line %d: empty proposal\n", NR > "/dev/stderr"; bad++ }
	if (bad) exit 1
	for (i = 1; i <= NR; i++) if (i in keep) print text[i] > out
	close(out)
	printf "proposal: lines %d paths %d%s\n", lines, total, (drop ? " dropped " dropped : "")
}
' "$tmp.in" >"$tmp.line" || {
	cat "$tmp.line" >&2
	exit 1
}
mv "$tmp" "$dir/conventions-proposal.md"
cat "$tmp.line"
rm -f "$tmp.in" "$tmp.line"
trap - EXIT
