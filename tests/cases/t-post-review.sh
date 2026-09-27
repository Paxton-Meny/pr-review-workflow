#!/bin/sh
# post-review: posts placeable findings, demotes the rest, summarizes, bumps round.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
printf 'owner acme\nrepo widgets\npr 7\nhead_sha abc123\n' >"$dir/meta.txt"
printf '0\n' >"$dir/round.txt"
printf 'src/app.py\tRIGHT\t2\nsrc/app.py\tRIGHT\t3\nsrc/app.py\tRIGHT\t4\n' >"$dir/pr-context/commentable.txt"

sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: correctness
severity: major
path: src/app.py
line: 2
side: RIGHT
title: Off by one
---
The loop stops early.
Fix: loop to len(items), matching the sibling loops in this file.
Resolution: the loop covers every element.
=== finding
category: best-practices
severity: minor
path: src/app.py
line: 3
end_line: 4
side: RIGHT
title: Duplicated block
---
Extract the shared branch.
Fix: hoist the duplicated block into a helper beside its callers.
Resolution: the branches share one implementation.
=== finding
category: outdated-docs
severity: nit
path: docs/other.md
line: 9
side: RIGHT
title: Stale mention
---
The doc names a removed flag.
Fix: drop the flag from the doc list.
Resolution: the doc drops the flag.
REC

printf '{"id": 9001}\n' | tr -d '{}" ' >/dev/null
printf '9001\n' >"$stub/api-repos_acme_widgets_pulls_7_comments.1"
printf '9002\n' >"$stub/api-repos_acme_widgets_pulls_7_comments.2"
: >"$stub/pr-comment"

out=$(sh "$REPO_ROOT/scripts/post-review.sh" "$dir")
[ "$out" = "post-review: 2 posted inline, 1 in the summary, round 1" ]

grep -qx 'comment_id: 9001' "$dir/findings/F001"
grep -qx 'placement: inline' "$dir/findings/F001"
grep -qx 'comment_id: 9002' "$dir/findings/F002"
grep -qx 'placement: summary' "$dir/findings/F003"
grep -qx 'comment_id:' "$dir/findings/F003"
grep -qx '1' "$dir/round.txt"

grep -q -- '-F start_line=3' "$stub/calls.log"
grep -q -- '-F line=4' "$stub/calls.log"

out=$(sh "$REPO_ROOT/scripts/post-review.sh" "$dir")
[ "$out" = "post-review: nothing to post, round 1 unchanged" ]
grep -qx '1' "$dir/round.txt"

if sh "$REPO_ROOT/scripts/post-review.sh" "$SCRATCH/nostate" 2>"$SCRATCH/err"; then
	echo "expected failure without state" >&2
	exit 1
fi
grep -q "incomplete" "$SCRATCH/err"

printf 'src/app.py\tRIGHT\t5\n' >>"$dir/pr-context/commentable.txt"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: security
severity: minor
path: src/app.py
line: 5
side: RIGHT
title: Quiet gap
---
Evidence.
Fix: done.
Resolution: done.
Criteria note: nothing lists this item yet.
REC
printf '9003\n' >"$stub/api-repos_acme_widgets_pulls_7_comments.3"
sh "$REPO_ROOT/scripts/post-review.sh" "$dir" >/dev/null
grep -q "nothing lists this item yet" "$stub/bodies.log" && {
	echo "criteria notes must not reach the pull request" >&2
	exit 1
}
grep -q "^Fix: done." "$stub/bodies.log"
grep -q "Quiet gap" "$stub/bodies.log"
