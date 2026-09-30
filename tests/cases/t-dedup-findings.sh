#!/bin/sh
# dedup-findings: merge window, richest wins, support counts, rerun no-op.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"

rec() {
	printf '=== finding\ncategory: %s\nseverity: minor\npath: %s\nline: %s\nside: RIGHT\ntitle: %s\n---\n%s\nFix: do.\nResolution: done.\n' "$1" "$2" "$3" "$4" "$5"
}

{
	rec correctness src/a.py 10 'Dup lean' 'short evidence'
	rec correctness src/a.py 12 'Dup rich' 'much longer evidence with detail that makes this record the richer of the pair'
	rec security src/a.py 11 'Other category' 'evidence'
	rec correctness src/a.py 40 'Far away' 'evidence'
} | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null

out=$(sh "$REPO_ROOT/scripts/dedup-findings.sh" "$dir" 2)
[ "$out" = "dedup-findings: kept 3 merged 1" ]
[ ! -f "$dir/findings/F001" ]
grep -qx 'support: 2/2' "$dir/findings/F002"
grep -qx 'title: Dup rich' "$dir/findings/F002"
grep -qx 'support: 1/2' "$dir/findings/F003"
grep -qx 'support: 1/2' "$dir/findings/F004"

out=$(sh "$REPO_ROOT/scripts/dedup-findings.sh" "$dir" 2)
[ "$out" = "dedup-findings: kept 3 merged 0" ]
[ "$(grep -c '^support: ' "$dir/findings/F002")" = "1" ]

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 placement=inline >/dev/null
rec security src/a.py 12 'Near posted' 'evidence' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
out=$(sh "$REPO_ROOT/scripts/dedup-findings.sh" "$dir" 2)
printf '%s\n' "$out" | grep -q 'merged 0'
grep -qx 'placement: inline' "$dir/findings/F003"
grep -qx 'title: Near posted' "$dir/findings/F005"

if sh "$REPO_ROOT/scripts/dedup-findings.sh" "$SCRATCH/empty" 2 2>"$SCRATCH/err"; then
	echo "expected failure without findings" >&2
	exit 1
fi
grep -q "no findings directory" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/dedup-findings.sh" "$dir" 0 2>"$SCRATCH/err"; then
	echo "expected refusal of zero samples" >&2
	exit 1
fi
grep -q "positive number" "$SCRATCH/err"
