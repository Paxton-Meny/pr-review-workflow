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

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
grep -qx 'status: addressed' "$dir/findings/F001"

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=open >/dev/null
grep -qx 'reopens: 1' "$dir/findings/F001"

sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=verified >/dev/null
if grep -q '^Arbitrated: ' "$dir/findings/F001"; then
	echo "a verification from addressed is not an arbitration" >&2
	exit 1
fi

# Only arbitration verifies an open finding, and the record says so.
printf '=== finding\ncategory: correctness\nseverity: major\npath: b.c\nline: 4\nside: RIGHT\ntitle: Other\n---\nFix: done.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F002 status=verified >/dev/null
grep -qx 'status: verified' "$dir/findings/F002"
[ "$(grep -c '^Arbitrated: ' "$dir/findings/F002")" -eq 1 ]

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

# Acceptance is a header field only a wont-fix record takes; a field the
# record lacks is added to the header, and the body is never rewritten.
printf '=== finding\ncategory: correctness\nseverity: major\npath: c.c\nline: 5\nside: RIGHT\ntitle: Third\n---\nplacement: quoted in the body\nFix: done.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 accepted=yes 2>"$SCRATCH/err"; then
	echo "expected refusal to accept an open finding" >&2
	exit 1
fi
grep -q "only a wont-fix finding can be accepted, F003 is open" "$SCRATCH/err"
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 status=wont-fix placement=summary >/dev/null
if sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 accepted=maybe 2>"$SCRATCH/err"; then
	echo "expected refusal of an acceptance other than yes" >&2
	exit 1
fi
grep -q "accepted must be yes" "$SCRATCH/err"
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 accepted=yes >/dev/null
[ "$(sed '/^---$/q' "$dir/findings/F003" | tail -n 2 | head -n 1)" = 'accepted: yes' ]
grep -qx 'placement: summary' "$dir/findings/F003"
grep -qx 'placement: quoted in the body' "$dir/findings/F003"
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F003 accepted=yes >/dev/null
[ "$(grep -c '^accepted: ' "$dir/findings/F003")" -eq 1 ]
