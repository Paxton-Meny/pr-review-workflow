#!/bin/sh
# Validate reviewer finding records from stdin and write them to the ledger.
# Usage: sh scripts/save-findings.sh <state-dir>
set -eu

dir=${1:?usage: save-findings.sh <state-dir>}
[ -f "$dir/round.txt" ] || {
	echo "save-findings: no round.txt in $dir, run init-state.sh first" >&2
	exit 1
}
round=$(($(cat "$dir/round.txt") + 1))

findings="$dir/findings"
mkdir -p "$findings"
next=1
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	n=$((${f##*/F} + 0))
	[ "$n" -ge "$next" ] && next=$((n + 1))
done

spool=$(mktemp -d "$dir/.save.XXXXXX")
trap 'rm -rf "$spool"' EXIT

awk -v spool="$spool" -v first="$next" -v round="$round" '
function fail(msg) {
	printf "save-findings: record %d: %s\n", rec, msg > "/dev/stderr"
	bad = 1
	exit 1
}
function flush() {
	if (rec == 0) return
	if (h["category"] !~ /^(correctness|security|performance|best-practices|antipatterns|content-leakage|outdated-docs)$/)
		fail("bad category: " h["category"])
	if (h["severity"] !~ /^(blocker|major|minor|nit)$/)
		fail("bad severity: " h["severity"])
	if (h["path"] == "" || h["path"] ~ /^\// || h["path"] ~ /(^|\/)\.\.(\/|$)/)
		fail("bad path: " h["path"])
	if (h["line"] !~ /^[1-9][0-9]*$/)
		fail("bad line: " h["line"])
	if (h["side"] !~ /^(RIGHT|LEFT)$/)
		fail("bad side: " h["side"])
	if (h["end_line"] != "" && (h["end_line"] !~ /^[1-9][0-9]*$/ || h["end_line"] + 0 <= h["line"] + 0))
		fail("bad end_line: " h["end_line"])
	if (h["title"] == "")
		fail("missing title")
	if (!sawbody)
		fail("missing body")
	if (!sawresolution)
		fail("missing Resolution line in the body")
	id = sprintf("F%03d", first + rec - 1)
	out = spool "/" id
	printf "id: %s\nstatus: open\ncategory: %s\nseverity: %s\npath: %s\nline: %s\nend_line: %s\nside: %s\nplacement:\ncomment_id:\ncommit:\nround: %d\nreopens: 0\ntitle: %s\n---\n", \
		id, h["category"], h["severity"], h["path"], h["line"], h["end_line"], h["side"], round, h["title"] > out
	printf "%s", body > out
	close(out)
}
/^=== finding$/ {
	flush()
	rec++
	delete h
	body = ""
	inbody = 0
	sawbody = 0
	sawresolution = 0
	next
}
rec == 0 { next }
/^---$/ && !inbody { inbody = 1; sawbody = 1; next }
{
	if (inbody) {
		if ($0 ~ /^Resolution: ./) sawresolution = 1
		body = body $0 "\n"
	} else if (match($0, /^[a-z_]+: ?/)) {
		key = substr($0, 1, index($0, ":") - 1)
		val = substr($0, RSTART + RLENGTH)
		h[key] = val
	} else if ($0 != "") {
		fail("stray header line: " $0)
	}
}
END {
	if (bad) exit 1
	flush()
	if (rec == 0) {
		print "save-findings: no records on stdin" > "/dev/stderr"
		exit 1
	}
	printf "%d\n", rec > (spool "/.count")
}
'

count=$(cat "$spool/.count")
rm -f "$spool/.count"
for f in "$spool"/F*; do
	mv "$f" "$findings/${f##*/}"
done

echo "save-findings: $count findings saved, next id F$(printf '%03d' $((next + count)))"
