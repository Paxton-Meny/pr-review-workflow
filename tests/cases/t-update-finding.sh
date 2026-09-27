#!/bin/sh
# update-finding: field updates, legal transitions only, reopen counting.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"
printf '=== finding\ncategory: correctness\nseverity: major\npath: a.c\nline: 3\nside: RIGHT\ntitle: Thing\n---\nFix: done.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 comment_id=12345 placement=inline >/dev/null
grep -qx 'comment_id: 12345' "$dir/findings/F001"
grep -qx 'placement: inline' "$dir/findings/F001"

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed commit=abc123 >/dev/null
grep -qx 'status: addressed' "$dir/findings/F001"

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=open >/dev/null
grep -qx 'reopens: 1' "$dir/findings/F001"

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=verified >/dev/null

if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=open 2>"$SCRATCH/err"; then
	echo "expected refusal to leave verified" >&2
	exit 1
fi
grep -q "illegal transition verified to open" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 severity=nit 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown field" >&2
	exit 1
fi
grep -q "unknown field: severity" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F999 status=addressed 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown id" >&2
	exit 1
fi
grep -q "unknown finding: F999" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 comment_id='12|34&' 2>"$SCRATCH/err"; then
	echo "expected refusal of a non-alphanumeric comment id" >&2
	exit 1
fi
grep -q "must be alphanumeric" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 placement=everywhere 2>"$SCRATCH/err"; then
	echo "expected refusal of a bad placement" >&2
	exit 1
fi
grep -q "placement must be inline or summary" "$SCRATCH/err"
