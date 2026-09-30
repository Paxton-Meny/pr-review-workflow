#!/bin/sh
# save-findings: assigns ids, validates records, rejects batches atomically.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"

sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" <<'REC' | grep -qx 'save-findings: 2 findings saved, next id F003'
=== finding
category: security
severity: blocker
path: src/auth.py
line: 42
side: RIGHT
title: Token written to the debug log
---
The token value reaches the log sink unredacted.
Fix: drop the token argument from the log call; the redact helper sits two lines above.
Resolution: no token value reaches any log sink.
=== finding
category: outdated-docs
severity: minor
path: docs/usage.md
line: 3
end_line: 5
side: LEFT
title: Removed flag still documented
---
The flag was deleted in this diff but the docs keep it.
Fix: remove the flag bullet from the options list in docs/usage.md.
Resolution: the docs no longer mention the flag.
REC

grep -qx 'id: F001' "$dir/findings/F001"
grep -qx 'status: open' "$dir/findings/F001"
grep -qx 'round: 1' "$dir/findings/F001"
grep -qx 'reopens: 0' "$dir/findings/F001"
grep -qx 'placement:' "$dir/findings/F001"
grep -qx 'title: Token written to the debug log' "$dir/findings/F001"
grep -qx 'The token value reaches the log sink unredacted.' "$dir/findings/F001"
grep -qx 'end_line: 5' "$dir/findings/F002"

printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: Third\n---\nFix: done.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
grep -qx 'id: F003' "$dir/findings/F003"

if printf '=== finding\ncategory: vibes\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: Bad\n---\nResolution: done.\n=== finding\ncategory: correctness\nseverity: nit\npath: b.c\nline: 2\nside: RIGHT\ntitle: Fine\n---\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection of a bad category" >&2
	exit 1
fi
grep -q "bad category: vibes" "$SCRATCH/err"
[ ! -f "$dir/findings/F004" ]

if printf '=== finding\ncategory: security\nseverity: major\npath: ../etc/passwd\nline: 1\nside: RIGHT\ntitle: Escape\n---\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection of a path escape" >&2
	exit 1
fi
grep -q "bad path" "$SCRATCH/err"

if printf '' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection of empty input" >&2
	exit 1
fi
grep -q "no records" "$SCRATCH/err"

if printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: No criterion\n---\nJust vibes.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection without a Resolution line" >&2
	exit 1
fi
grep -q "exactly one Resolution line, found 0" "$SCRATCH/err"

if printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: Two contracts\n---\nResolution: one.\nResolution: two.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection of two Resolution lines" >&2
	exit 1
fi
grep -q "exactly one Resolution line, found 2" "$SCRATCH/err"

printf '=== finding\ncategory: other\nseverity: minor\npath: a.c\nline: 1\nside: RIGHT\ntitle: Uncategorized but real\n---\nEvidence.\nFix: done.\nResolution: done.\nCriteria note: nothing covers licensing drift.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
grep -qx 'category: other' "$dir/findings/F004"

if printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: No repair context\n---\nEvidence.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection without a Fix line or fence" >&2
	exit 1
fi
grep -q "needs a Fix line or a suggestion fence" "$SCRATCH/err"

printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: Fence stands in for Fix\n---\nEvidence.\nResolution: line one reads z.\n```suggestion\nz\n```\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null
grep -qx 'title: Fence stands in for Fix' "$dir/findings/F005"

if printf '=== finding\ncategory: correctness\nseverity: nit\npath: a.c\nline: 1\nside: RIGHT\ntitle: Two repairs\n---\nFix: one.\nFix: two.\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected rejection of two Fix lines" >&2
	exit 1
fi
grep -q "at most one Fix line, found 2" "$SCRATCH/err"

dirc="$SCRATCH/state-check"
mkdir -p "$dirc"
printf '0\n' >"$dirc/round.txt"
printf '=== finding\ncategory: correctness\nseverity: minor\npath: a.c\nline: 1\nside: RIGHT\ntitle: One check\n---\nevidence\nFix: do.\nCheck: pytest tests/test_a.py::t\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dirc" >/dev/null
grep -qx 'Check: pytest tests/test_a.py::t' "$dirc/findings/F001"

if printf '=== finding\ncategory: correctness\nseverity: minor\npath: a.c\nline: 1\nside: RIGHT\ntitle: Two checks\n---\nevidence\nFix: do.\nCheck: pytest a\nCheck: pytest b\nResolution: done.\n' \
	| sh "$REPO_ROOT/scripts/save-findings.sh" "$dirc" 2>"$SCRATCH/err"; then
	echo "expected refusal of a second Check line" >&2
	exit 1
fi
grep -q "at most one Check line" "$SCRATCH/err"
