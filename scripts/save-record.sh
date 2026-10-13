#!/bin/sh
# Validate a cartographer's record from stdin and file it under the survey.
# Usage: sh scripts/save-record.sh <survey-dir> <partition-id> <<'END'
#        ## layout
#        layout <path> | <statement>
#        ...
#        END
#
# A record has sections headed "## layout", "## tests", "## idioms",
# "## oddities", "## rules", "## sensitive", and "## check", in any
# order, each holding claims of the form "<kind> <ref> | <statement>"
# whose kind is the section's name and whose ref is a repository path
# (a directory ending in / or /**, or a file) or, under check, a
# command. At most 80 lines of at most 240 characters; no absolute
# paths, no parent references, no conventions markers. The partition
# must exist in the plan, so an agent can file only the record it was
# asked for. Writes records/<id>.txt atomically and prints one line:
# "record: <id> lines N claims N".
set -eu

dir=${1:?usage: save-record.sh <survey-dir> <partition-id>}
id=${2:?usage: save-record.sh <survey-dir> <partition-id>}
case "$id" in
'' | *[!0-9]* | 0*)
	echo "save-record: partition id must be a positive number: $id" >&2
	exit 1
	;;
esac
[ -f "$dir/partitions/$id.txt" ] || {
	echo "save-record: no partition $id in $dir/partitions, run inventory-repo.sh first" >&2
	exit 1
}
MAX_LINES=80
MAX_CHARS=240
SECTIONS='layout tests idioms oddities rules sensitive check'

mkdir -p "$dir/records"
tmp=$(mktemp "$dir/records/.record.XXXXXX")
trap 'rm -f "$tmp" "$tmp.line"' EXIT
tr -d '\r' >"$tmp"

awk -v id="$id" -v max_lines="$MAX_LINES" -v max_chars="$MAX_CHARS" -v sections="$SECTIONS" '
function fail(msg) { printf "save-record: line %d: %s\n", NR, msg > "/dev/stderr"; exit 1 }
BEGIN { n = split(sections, s, " "); for (i = 1; i <= n; i++) known[s[i]] = 1 }
{
	if (NR > max_lines) fail("more than " max_lines " lines")
	if (length($0) > max_chars) fail("longer than " max_chars " characters")
	if (index($0, "<!-- review-conventions")) fail("a conventions marker belongs to CLAUDE.md, not a record")
	if ($0 ~ /^[ \t]*$/) next
	if ($0 ~ /^## /) {
		section = $0; sub(/^## /, "", section)
		if (!(section in known)) fail("unknown section: " section)
		next
	}
	if (section == "") fail("a claim before any section header")
	if ($1 != section) fail("claim kind " $1 " under section " section)
	if (index($0, " | ") == 0) fail("a claim needs \" | \" between its ref and its statement")
	ref = $0; sub(/^[a-z]+ /, "", ref); sub(/ \| .*$/, "", ref)
	statement = $0; sub(/^[^|]*\| /, "", statement)
	if (ref == "" || statement == "") fail("empty ref or statement")
	if (section != "check" && (ref ~ /^\// || ref ~ /(^|\/)\.\.(\/|$)/ || ref ~ /[ \t]/)) fail("ref must be a relative repository path: " ref)
	claims++
}
END { if (NR == 0) fail("empty record"); printf "record: %s lines %d claims %d\n", id, NR, claims }
' "$tmp" >"$tmp.line"
mv "$tmp" "$dir/records/$id.txt"
cat "$tmp.line"
rm -f "$tmp.line"
trap - EXIT
