#!/bin/sh
# Validate reviewer finding records from stdin and write them to the ledger.
# Usage: sh scripts/save-findings.sh <state-dir> [--unit <unit>]
# A report that is exactly "no findings" saves nothing. With --unit, the
# report belongs to the review phase: "all" or "group-<n>" for a step 5
# reviewer (one call per sample), "gap" for the gap pass, and
# "saved <unit> <count>" is appended to the ledger's review.txt once the
# records are in place, for review-progress.sh. "incremental" is the
# review of files a round, a repair, or a base sync changed: it is not
# part of the review phase, so its "saved incremental <count>" goes to
# the step journal steps.txt instead, for next-step.sh.
set -eu

usage='usage: save-findings.sh <state-dir> [--unit <unit>]'
dir=${1:?$usage}
unit=''
case "${2:-}" in
'') ;;
--unit) unit=${3:-} ;;
*)
	echo "$usage" >&2
	exit 1
	;;
esac
case "$unit" in
'' | all | gap | incremental | group-[1-9]) ;;
group-[1-9]*)
	case "${unit#group-}" in
	*[!0-9]*) unit=bad ;;
	esac
	;;
*) unit=bad ;;
esac
[ "$unit" != bad ] && { [ -n "$unit" ] || [ -z "${2:-}" ]; } || {
	echo "save-findings: the unit must be all, gap, group-<n>, or incremental: ${3:-}" >&2
	exit 1
}
[ -f "$dir/round.txt" ] || {
	echo "save-findings: no round.txt in $dir, run init-state.sh first" >&2
	exit 1
}
round=$(($(cat "$dir/round.txt") + 1))
progress="$dir/review.txt"
[ "$unit" != incremental ] || progress="$dir/steps.txt"

findings="$dir/findings"
mkdir -p "$findings"
next=1
for f in "$findings"/F*; do
	[ -f "$f" ] || continue
	n=${f##*/F}
	n=${n#"${n%%[!0]*}"}
	n=$((${n:-0} + 0))
	[ "$n" -ge "$next" ] && next=$((n + 1))
done

spool=$(mktemp -d "$dir/.save.XXXXXX")
trap 'rm -rf "$spool"' EXIT

cat >"$spool/.in"
if [ "$(awk 'NF' "$spool/.in" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" = 'no findings' ]; then
	[ -z "$unit" ] || printf 'saved %s 0\n' "$unit" >>"$progress"
	echo "save-findings: no findings${unit:+ for $unit}"
	exit 0
fi

awk -v spool="$spool" -v first="$next" -v round="$round" '
function fail(msg) {
	printf "save-findings: record %d: %s\n", rec, msg > "/dev/stderr"
	bad = 1
	exit 1
}
function flush() {
	if (rec == 0) return
	if (h["category"] !~ /^(correctness|security|performance|best-practices|antipatterns|content-leakage|outdated-docs|other)$/)
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
	if (sawresolution != 1)
		fail("the body needs exactly one Resolution line, found " sawresolution + 0)
	if (sawfix > 1)
		fail("at most one Fix line, found " sawfix + 0)
	if (sawfix == 0 && !sawfence)
		fail("the body needs a Fix line or a suggestion fence")
	if (sawcheck > 1)
		fail("at most one Check line, found " sawcheck + 0)
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
	sawfix = 0
	sawfence = 0
	sawcheck = 0
	next
}
rec == 0 { next }
/^---$/ && !inbody { inbody = 1; sawbody = 1; next }
{
	if (inbody) {
		if ($0 ~ /^Resolution: ./) sawresolution++
		if ($0 ~ /^Fix: ./) sawfix++
		if ($0 ~ /^Check: ./) sawcheck++
		if ($0 ~ /^```suggestion$/) sawfence = 1
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
' "$spool/.in"
rm -f "$spool/.in"

count=$(cat "$spool/.count")
rm -f "$spool/.count"
for f in "$spool"/F*; do
	mv "$f" "$findings/${f##*/}"
done
[ -z "$unit" ] || printf 'saved %s %d\n' "$unit" "$count" >>"$progress"

echo "save-findings: $count findings saved, next id F$(printf '%03d' $((next + count)))"
