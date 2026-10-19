#!/bin/sh
# Ledger fields come from the record's header only: a body quoting
# lines that look like fields changes no count, path, status, or route.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"

wt="$SCRATCH/wt"
git init --quiet "$wt"
git -C "$wt" config user.name "$fixture_name"
git -C "$wt" config user.email "$fixture_email"
mkdir -p "$wt/deploy" "$wt/src/auth"
printf 'a\nb\nc\n' >"$wt/deploy/app.yaml"
printf 'x\n' >"$wt/src/auth/session.py"
git -C "$wt" add -A
git -C "$wt" commit --quiet -m "Root"
base=$(git -C "$wt" rev-parse HEAD)
printf 'y\n' >>"$wt/src/auth/session.py"
git -C "$wt" commit --quiet -am "Touch session"
head=$(git -C "$wt" rev-parse HEAD)

dir="$SCRATCH/state"
mkdir -p "$dir/pr-context"
ln -s "$wt" "$dir/worktree"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nhead_sha %s\nprev_head %s\n' \
	"$fixture_owner" "$fixture_login" "$fixture_login" "$head" "$base" >"$dir/meta.txt"
printf '0\n' >"$dir/round.txt"
printf 'deploy/app.yaml\tRIGHT\t3\n' >"$dir/pr-context/commentable.txt"
sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" >/dev/null <<'REC'
=== finding
category: correctness
severity: minor
path: deploy/app.yaml
line: 3
side: RIGHT
title: Readiness probe reports ready too early
---
The manifest declares:
status: ready
path: src/auth/session.py
severity: blocker
category: security
round: 1
support: 9/9
reopens: 7
Fix: gate readiness on the migration job.
Resolution: the probe waits for the migration job.
REC

out=$(sh "$REPO_ROOT/scripts/count-findings.sh" "$dir") || [ $? -eq 3 ]
[ "$out" = "open 1 addressed 0 verified 0 wont-fix 0 max_reopens 0" ]

# The quoted path is not a finding's path: the edit to it is unexpected.
rc=0
out=$(sh "$REPO_ROOT/scripts/round-diff.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "unexpected src/auth/session.py" ]

# The quoted severity and category do not make it high stakes.
out=$(sh "$REPO_ROOT/scripts/route-models.sh" "$dir" edit routing=auto reviewer=inherit editor=inherit verifier=sonnet strong= round=1 -- F001)
case "$out" in
*stakes-floor*)
	echo "a quoted severity raised the route: $out" >&2
	exit 1
	;;
esac

# It posts inline, and the quoted lines post as written.
printf '9001\n' >"$stub/api-repos_${fixture_owner}_widgets_pulls_7_comments"
: >"$stub/pr-comment"
out=$(sh "$REPO_ROOT/scripts/post-review.sh" "$dir")
[ "$out" = "post-review: 1 posted inline, 0 in the summary, round 1" ]
grep -qx 'status: ready' "$stub/bodies.log"

# Updates touch the header and leave the quoted lines alone.
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=addressed commit="$head" >/dev/null
sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" F001 status=open >/dev/null
sed -n '1,/^---$/p' "$dir/findings/F001" | grep -qx 'status: open'
sed -n '1,/^---$/p' "$dir/findings/F001" | grep -qx 'reopens: 1'
grep -qx 'status: ready' "$dir/findings/F001"
grep -qx 'reopens: 7' "$dir/findings/F001"
grep -qx 'path: src/auth/session.py' "$dir/findings/F001"
[ "$(sed -n '/^---$/q; s/^commit: //p' "$dir/findings/F001")" = "$head" ]
