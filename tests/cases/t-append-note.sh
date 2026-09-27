#!/bin/sh
# append-note: appends to the body, refuses empties and separators.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"
printf '=== finding\ncategory: correctness\nseverity: major\npath: a.c\nline: 3\nside: RIGHT\ntitle: Thing\n---\nEvidence.\nFix: done.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null

printf 'Reopened: the guard still misses the empty case.\n' \
	| sh "$REPO_ROOT/scripts/append-note.sh" "$dir" F001 | grep -qx 'append-note: F001 noted'
grep -qx 'Reopened: the guard still misses the empty case.' "$dir/findings/F001"
grep -qx 'Resolution: done.' "$dir/findings/F001"

if printf '' | sh "$REPO_ROOT/scripts/append-note.sh" "$dir" F001 2>"$SCRATCH/err"; then
	echo "expected refusal of an empty note" >&2
	exit 1
fi
grep -q "empty note" "$SCRATCH/err"

if printf 'x\n=== finding\ny\n' | sh "$REPO_ROOT/scripts/append-note.sh" "$dir" F001 2>"$SCRATCH/err"; then
	echo "expected refusal of a separator in a note" >&2
	exit 1
fi
grep -q "may not contain the record separator" "$SCRATCH/err"

if printf 'z\n' | sh "$REPO_ROOT/scripts/append-note.sh" "$dir" F999 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown id" >&2
	exit 1
fi
grep -q "unknown finding: F999" "$SCRATCH/err"
