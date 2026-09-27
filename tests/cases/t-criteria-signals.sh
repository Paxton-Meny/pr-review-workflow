#!/bin/sh
# criteria-signals: lists other-category findings and criteria notes.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf '0\n' >"$dir/round.txt"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: other
severity: minor
path: a.c
line: 1
side: RIGHT
title: Belongs nowhere defined
---
Evidence.
Fix: done.
Resolution: done.
=== finding
category: security
severity: major
path: b.c
line: 2
side: RIGHT
title: Listed category, unlisted item
---
Evidence.
Fix: done.
Resolution: done.
Criteria note: security lists nothing about timing side channels.
=== finding
category: correctness
severity: nit
path: c.c
line: 3
side: RIGHT
title: Plain finding
---
Evidence.
Fix: done.
Resolution: done.
REC

out=$(sh "$REPO_ROOT/scripts/criteria-signals.sh" "$dir")
printf '%s\n' "$out" | grep -qx 'other F001: Belongs nowhere defined'
printf '%s\n' "$out" | grep -qx 'note F002: security lists nothing about timing side channels.'
printf '%s\n' "$out" | grep -qx 'criteria-signals: 1 other, 1 notes'
if printf '%s\n' "$out" | grep -q 'F003'; then
	echo "a plain finding must not appear in the signals" >&2
	exit 1
fi

if sh "$REPO_ROOT/scripts/criteria-signals.sh" "$SCRATCH/empty" 2>"$SCRATCH/err"; then
	echo "expected failure without a findings directory" >&2
	exit 1
fi
grep -q "no findings directory" "$SCRATCH/err"
