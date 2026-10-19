#!/bin/sh
# next-step: a run is walked through the review, a round with two
# batches, a failed gate and its repair, verification, an incremental
# review, arbitration, the wont-fix acceptance, a ci repair, a base
# sync, and the merge, and at every point the ledger alone names the
# step to run next. The loop scripts write the journal it reads.
set -eu
unset CLAUDE_CODE_EFFORT_LEVEL

data="$SCRATCH/data"
dir="$data/state/o__r__7"
ctx="$dir/pr-context"
wt="$dir/worktree"
mkdir -p "$dir"
ns() { sh "$REPO_ROOT/scripts/next-step.sh" "$1"; }
expect() {
	# expect <output> [state-dir]: next-step prints exactly that, exit 0
	rc=0
	out=$(ns "${2:-$dir}") || rc=$?
	[ "$rc" -eq 0 ] && [ "$out" = "$1" ] || {
		printf 'expected:\n%s\ngot (exit %s):\n%s\n' "$1" "$rc" "$out" >&2
		exit 1
	}
}
first() {
	# first <line> [state-dir]: the placement line alone
	out=$(ns "${2:-$dir}" | head -n 1)
	[ "$out" = "$1" ] || {
		printf 'expected:\n%s\ngot:\n%s\n' "$1" "$out" >&2
		exit 1
	}
}
lines() { printf '%s\n' "$@"; }
route() { sh "$REPO_ROOT/scripts/route-models.sh" "$dir" "$@"; }
update() { sh "$REPO_ROOT/scripts/update-finding.sh" "$dir" "$@" >/dev/null; }
gate() { sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate >/dev/null || true; }
journal() { printf '%s\n' "$*" >>"$dir/steps.txt"; }
tip() { git -C "$wt" rev-parse HEAD; }
push() {
	# push <file>: the editor commits a change and pushes, as push-branch.sh records it
	old=$(tip)
	printf '%s\n' "$1" >>"$wt/$1"
	git -C "$wt" add "$1"
	git -C "$wt" commit -qm "Change $1"
	sed -i -e "s/^head_sha .*/head_sha $(tip)/" -e '/^prev_head /d' "$dir/meta.txt"
	printf 'prev_head %s\n' "$old" >>"$dir/meta.txt"
	journal push "$(tip)"
}
finding() {
	# finding <severity> <line> [suggestion]
	printf '=== finding\ncategory: correctness\nseverity: %s\npath: src/a.py\nline: %s\nside: RIGHT\ntitle: Thing %s\n---\nEvidence.\n' "$1" "$2" "$2"
	[ -z "${3:-}" ] || printf '```suggestion\nfixed\n```\n'
	printf 'Fix: do.\nResolution: done.\n'
}
posted() { for id in "$@"; do update "$id" comment_id=1 placement=inline; done; journal post; }
variant() {
	# variant <name>: a copy of the run, with more settings from stdin
	v="$data/state/o__r__$1"
	rm -rf "$v"
	cp -R "$dir" "$v"
	{
		echo 'check_command test -f ok'
		cat
	} | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$v" >/dev/null
	printf '%s\n' "$v"
}

# Before the ledger and its settings exist: step 2.
expect 'next-step: 2 create the ledger with init-state.sh'
git init -q "$wt"
git -C "$wt" config user.name tester
git -C "$wt" config user.email tester@example.invalid
mkdir -p "$wt/src"
printf 'a\n' >"$wt/src/a.py"
: >"$wt/ok"
git -C "$wt" add -A
git -C "$wt" commit -qm base
base=$(tip)
printf 'owner o\nrepo r\npr 7\nhead_sha %s\ncross_repo false\nmaintainer_can_modify true\n' "$base" >"$dir/meta.txt"
printf '0\n' >"$dir/round.txt"
expect 'next-step: 2 resolve the settings with resolve-settings.sh, then the rest of step 2'
printf 'check_command test -f ok\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null

# A ledger without the journal cannot be placed.
rc=0
out=$(ns "$dir") || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = 'next-step: unplaced, the ledger predates the step journal; resume as step 2 says' ]

# The review phase: fetch, checkout, plan, reviewers, gap pass.
journal invoke
expect 'next-step: 3 fetch-pr.sh, probe-diff.sh, classify-change.sh, then step 4'
mkdir -p "$ctx"
: >"$ctx/diff.patch"
printf 'classify-change: kind code files 1 lines 40 code_lines 40\n' >"$ctx/class.txt"
: >"$ctx/probe-slugs.txt"
mv "$wt" "$SCRATCH/wt"
expect 'next-step: 4 checkout-pr.sh, extract-standards.sh, run-check.sh --baseline, then step 5'
mv "$SCRATCH/wt" "$wt"
sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --baseline >/dev/null
expect 'next-step: 5 shard-plan.sh, route-models.sh review, then the reviewers it routes'
reviewer=$(route review)
expect "$(lines 'next-step: 5 spawn the reviewers still owed and save each report with --unit' \
	'review all needs 1 of 1' 'gap not run' "$reviewer")"
{ finding minor 3 fence; finding nit 5 fence; finding major 9; } | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit all >/dev/null
expect 'next-step: 6 the gap pass: route-models.sh gap, then the reviewer it routes, saved with --unit gap'
printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit gap >/dev/null

# Posting: the first time with the filter, later rounds without.
expect "$(lines 'next-step: 7 route-models.sh filter and its filter, then prove-suggestions.sh, then post-review.sh' 'ids F001 F002 F003')"
# A fork that allows no edits ends after posting.
v=$(variant 8 </dev/null)
posted F001 F002 F003
sed -i -e 's/^cross_repo .*/cross_repo true/' -e 's/^maintainer_can_modify .*/maintainer_can_modify false/' "$v/meta.txt"
printf 'post\n' >>"$v/steps.txt"
sed -i 's/^placement:$/placement: inline/' "$v"/findings/F00*
expect 'next-step: 7 review-only: the status comment, run-stats.sh review-only, and stop' "$v"
expect "$(lines 'next-step: 8a round-counter.sh next 4, then the round' 'ids F001 F002 F003')"

# Round 1: two batches, cheapest first, each followed by the gate.
sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 4 >/dev/null
expect "$(lines 'next-step: 8b route-models.sh edit round=1 -- <open ids>, then the editor for each line it prints' 'ids F001 F002 F003')"
batches=$(route edit round=1 -- F001 F002 F003)
[ "$(printf '%s\n' "$batches" | grep -c .)" -eq 2 ]
batch1=$(printf '%s\n' "$batches" | sed -n 1p)
batch2=$(printf '%s\n' "$batches" | sed -n 2p)
expect "$(lines 'next-step: 8b spawn the editor for batch 1 of 2 in round 1, then run-check.sh --gate' "$batch1")"
push src/a.py
update F001 status=addressed
update F002 status=addressed
expect 'next-step: 8c run-check.sh --gate, after batch 1 of 2 in round 1'
gate
expect "$(lines 'next-step: 8b spawn the editor for batch 2 of 2 in round 1, then run-check.sh --gate' "$batch2")"
# An editor that pushed nothing but settled its findings has still run.
v=$(variant 9 </dev/null)
sh "$REPO_ROOT/scripts/update-finding.sh" "$v" F003 status=wont-fix >/dev/null
expect 'next-step: 8c run-check.sh --gate, after batch 2 of 2 in round 1' "$v"
push src/a.py
update F003 status=addressed
rm "$wt/ok"
gate
expect "$(lines 'next-step: 8c the check failed after batch 2 of 2 in round 1: route-models.sh repair round=1 -- <ids>, then the repair editor, then run-check.sh --gate' 'ids F003')"
repair=$(route repair round=1 -- F003)
expect "$(lines 'next-step: 8c spawn the repair editor on this route; once it has reported, run-check.sh --gate' "$repair")"
# A second failure after the repair is non-convergence.
v=$(variant 10 </dev/null)
printf 'push x\ngate fail x\n' >>"$v/steps.txt"
expect 'next-step: 9 non-convergence: the check failed again after its repair in round 1' "$v"
: >"$wt/ok"
git -C "$wt" add ok
push src/a.py
expect 'next-step: 8c run-check.sh --gate, after batch 2 of 2 in round 1'
gate

# Verification, then the round's diff and its incremental review.
expect "$(lines 'next-step: 8d count-findings.sh --list, route-models.sh verify -- <addressed ids>, then the verifier it routes' 'ids F001 F002 F003')"
verifier=$(route verify -- F001 F002 F003)
expect "$(lines 'next-step: 8d spawn the verifier on this route' "$verifier" 'ids F001 F002 F003')"
update F001 status=verified
update F002 status=verified
update F003 status=open
expect 'next-step: 8e round-diff.sh'
push other.txt
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" >/dev/null || true
expect 'next-step: 8e round-diff.sh again for its paths, fetch-pr.sh, route-models.sh incremental, then the reviewer on those files, saved with --unit incremental'
incremental=$(route incremental)
expect "$(lines 'next-step: 8e spawn the incremental reviewer on this route and save its report with --unit incremental' "$incremental")"
finding major 12 | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit incremental >/dev/null
[ "$(tail -n 1 "$dir/steps.txt")" = 'saved incremental 1' ]
expect "$(lines 'next-step: 8e prove-suggestions.sh, then post-review.sh, for the new findings' 'ids F004')"
posted F004
expect "$(lines 'next-step: 8a round-counter.sh next 4, then the round' 'ids F003 F004')"

# A spent cap parks; a park closes the round, and the next invocation
# starts a new one.
v=$(variant 11 </dev/null)
printf 'round cap\n' >>"$v/steps.txt"
expect 'next-step: 9 non-convergence: the round cap is spent' "$v"
printf 'outcome parked\n' >>"$v/steps.txt"
expect 'next-step: end parked; invoking review-pr again resumes it' "$v"
printf 'invoke\n' >>"$v/steps.txt"
first 'next-step: 8a round-counter.sh next 4, then the round' "$v"
# A ledger whose rounds ran before the journal cannot be placed mid-round.
sed -i '/^round /d' "$v/steps.txt"
rc=0
out=$(ns "$v") || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = 'next-step: unplaced, round 1 ran before the step journal; resume as step 2 says' ]

# Round 2: one finding reopened past the cap goes to arbitration once.
sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 4 >/dev/null
n=$(route edit round=2 -- F003 F004 | grep -c .)
push src/a.py
update F003 status=addressed
update F004 status=wont-fix
while [ "$n" -gt 0 ]; do
	gate
	n=$((n - 1))
done
route verify -- F003 >/dev/null
update F003 status=open
sed -i 's/^reopens: .*/reopens: 3/' "$dir/findings/F003"
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" >/dev/null
expect "$(lines 'next-step: 8f route-models.sh arbitrate, then the arbitration verifier' 'ids F003')"
arbiter=$(route arbitrate)
expect "$(lines 'next-step: 8f spawn the arbitration verifier on this route unless it has reported; once it has, these findings still open park the run (step 9)' "$arbiter" 'ids F003')"
update F003 status=verified

# Convergence: the wont-fix is accepted before step 11.
expect "$(lines 'next-step: 10 present each wont-fix; update-finding.sh <id> accepted=yes for each the user accepts' 'ids F004')"
update F004 accepted=yes

# Step 11: method, sync, checks, a ci repair and its review.
expect 'next-step: 11a merge-method.sh, then sync-branch.sh'
printf 'method undecided\n' >"$ctx/merge-method.txt"
first 'next-step: 12 the merge method is undecided: attended, ask which allowed method and merge-method.sh --set it; unattended, park (step 9)'
printf 'method merge\n' >"$ctx/merge-method.txt"
journal sync current "$(tip)"
expect 'next-step: 11b await-checks.sh'
v=$(variant 12 <<'EOF'
ci_checks wait
EOF
)
printf 'checks fail %s\n' "$(tip)" >>"$v/steps.txt"
expect 'next-step: 11c the checks failed: a comment naming them, then attended hold (step 12), unattended park (step 9)' "$v"
ci_base=$(tip)
journal checks fail "$ci_base"
expect 'next-step: 11c round-counter.sh next ci, then the ci repair'
sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next ci >/dev/null
expect "next-step: 11c route-models.sh ci-repair repeat=0, then the editor with the ci repair prompt (ci base $ci_base), posting its paragraph"
printf '%s sig1 tests\n%s sig1 tests\n' "$ci_base" "$ci_base" >"$dir/ci-attempts.txt"
first "next-step: 11c route-models.sh ci-repair repeat=1, then the editor with the ci repair prompt (ci base $ci_base), posting its paragraph"
ci_repair=$(route ci-repair)
expect "$(lines 'next-step: 11c spawn the ci repair editor on this route unless it has reported; once it has, run-check.sh --gate' "$ci_repair")"
push fix.txt
expect 'next-step: 11c run-check.sh --gate'
gate
expect "next-step: 11c round-diff.sh --all $ci_base"
sh "$REPO_ROOT/scripts/round-diff.sh" "$dir" --all "$ci_base" >/dev/null || true
first "next-step: 11c the incremental review of the listed files as step 8e: round-diff.sh --all $ci_base for them, fetch-pr.sh, route-models.sh incremental, the reviewer, saved with --unit incremental"
route incremental >/dev/null
printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit incremental >/dev/null
expect 'next-step: 11a merge-method.sh, then sync-branch.sh'
v=$(variant 13 </dev/null)
printf 'ci-round cap\n' >>"$v/steps.txt"
expect 'next-step: 9 non-convergence: the checks still fail after the repairs' "$v"

# A base sync that pushed takes the gate and reviews what it changed.
push merged.txt
journal sync update "$(tip)"
printf 'src/a.py\n' >"$ctx/sync-changed.txt"
expect 'next-step: 11a run-check.sh --gate, since the update pushed'
gate
expect 'next-step: 11a the incremental review of pr-context/sync-changed.txt as step 8e: route-models.sh incremental, the reviewer, saved with --unit incremental'
route incremental >/dev/null
printf 'no findings\n' | sh "$REPO_ROOT/scripts/save-findings.sh" "$dir" --unit incremental >/dev/null
expect 'next-step: 11b await-checks.sh'

# Conflicts: a person under update, the editor under resolve.
for setting in update resolve; do
	v=$(variant 14 <<EOF
branch_sync $setting
EOF
)
	printf 'sync conflicts %s\n' "$(tip)" >>"$v/steps.txt"
	case "$setting" in
	update) expect 'next-step: 11a the base sync needs a person: attended, ask the user and hold (step 12); unattended, park (step 9)' "$v" ;;
	resolve)
		expect 'next-step: 11a route-models.sh conflict, then the editor with the conflict prompt' "$v"
		printf 'sync abort\n' >>"$v/steps.txt"
		expect 'next-step: 9 park: the conflict editor could not resolve the update' "$v"
		;;
	esac
done

# The merge gate: the check must have passed at the head.
journal checks pass "$(tip)"
expect 'next-step: 12 merge-method.sh --refresh, then the merge gate (auto_approve false)'
v=$(variant 15 </dev/null)
sed -i 's/^\(pass [0-9a-f]*\) .*/\1 0000000/' "$v/check-gate.txt"
expect "next-step: 12 run-check.sh --gate first, as step 8c describes: the check has not passed at $(tip)" "$v"
journal merge moved "$(tip)"
expect 'next-step: 11a merge-method.sh, then sync-branch.sh: the base moved'
journal sync current "$(tip)"
journal checks pass "$(tip)"
first 'next-step: 12 merge-method.sh --refresh, then the merge gate (auto_approve false)'

# A hold ends the run; its resume checks out again first.
v=$(variant 16 </dev/null)
printf 'outcome held\n' >>"$v/steps.txt"
expect 'next-step: 12 hold: cleanup-state.sh, report the state directory, and stop' "$v"
printf 'cleanup\n' >>"$v/steps.txt"
expect 'next-step: end held; invoking review-pr again resumes it' "$v"
printf 'invoke\n' >>"$v/steps.txt"
rm -rf "$v/worktree"
expect 'next-step: 3 the worktree is gone: steps 3 and 4, then ask again' "$v"

# After the merge: cleanup, then nothing.
journal merge done "$(tip)"
expect 'next-step: 13 run-stats.sh merged, then cleanup-state.sh, then sweep-state.sh, then the report'
sh "$REPO_ROOT/scripts/run-stats.sh" "$dir" merged >/dev/null
expect 'next-step: 13 cleanup-state.sh, then sweep-state.sh, then the report'
journal cleanup
expect 'next-step: end merged and cleaned up; report as step 13 says'
