#!/bin/sh
# await-checks: off, pending then pass, a slice, the budget, a failure
# digested with its signature, the same failure read as a repeat, no
# checks with and without workflows, a cancelled run rerun once.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
export AWAIT_CHECKS_INTERVAL=0 AWAIT_CHECKS_SCHEDULE_GRACE=0 AWAIT_CHECKS_STATUS_GRACE=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

clone="$SCRATCH/clone"
git init -q -b main "$clone"
printf 'x\n' >"$clone/a.txt"
git -C "$clone" add a.txt && git -C "$clone" commit -q -m "Start"
git -C "$clone" update-ref refs/remotes/origin/main HEAD

dir="$SCRATCH/data/state/o__r__7"
mkdir -p "$dir/pr-context"
printf 'owner o\nrepo r\npr 7\nhead_sha abc123\nbase_branch main\nrepo_root %s\n' "$clone" >"$dir/meta.txt"
resolve() { printf 'ci_wait_minutes 1\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null; }
resolve
await() { sh "$REPO_ROOT/scripts/await-checks.sh" "$dir" "$@"; }
checks() { printf '%s\n' "$@" >"$stub/pr-checks"; }
run='https://github.com/o/r/actions/runs/11/job/22'

# Off reads nothing.
printf 'ci off\n' >"$dir/overrides.txt"
resolve
[ "$(await)" = "await-checks: off" ]
[ "$(cat "$dir/ci-result.txt")" = "off abc123" ]
[ ! -f "$stub/calls.log" ]
: >"$dir/overrides.txt"
resolve

# Pending, then every check passed or skipped.
printf 'pending\tbuild\t%s\tCI\t\n' "$run" >"$stub/pr-checks.1"
printf 'pass\tbuild\t%s\tCI\t\nskipping\tdocs\t%s\tCI\t\n' "$run" "$run" >"$stub/pr-checks.2"
[ "$(await)" = "await-checks: pass 2 checks" ]
[ "$(cat "$dir/ci-result.txt")" = "pass abc123" ]
grep -q '^abc123 [0-9]* [0-9]*$' "$dir/ci-wait.txt"
[ "$(grep -c '^pr checks 7 --repo o/r --json' "$stub/calls.log")" -eq 2 ]

# A slice ends with checks pending; the budget, kept per head, ends the wait.
checks "pending	build	$run	CI	"
rc=0
out=$(await --slice 0) || rc=$?
[ "$rc" -eq 5 ]
[ "$out" = "await-checks: pending 1 of 1, call again" ]
printf 'abc123 0 0\n' >"$dir/ci-wait.txt"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 6 ]
[ "$out" = "await-checks: wait budget of 1 minutes spent, 1 pending" ]
# After exit 6, --extend gives the head a fresh budget and polls again.
printf 'pass\tbuild\t%s\tCI\t\n' "$run" >"$stub/pr-checks.1"
printf 'abc123 0 0\n' >"$dir/ci-wait.txt"
[ "$(await --extend)" = "await-checks: pass 1 checks" ]
grep -q '^abc123 0 [1-9][0-9]*$' "$dir/ci-wait.txt"
if grep -q '^abc123 0 0$' "$dir/ci-wait.txt"; then
	echo "--extend must move the deadline" >&2
	exit 1
fi
rm -f "$dir/ci-wait.txt"

# A failed gh call is not "no checks": with the head long seen, it ends
# as budget spent or a slice, never as none.
rm -f "$stub/pr-checks"
printf '1\n' >"$stub/pr-checks.exit"
printf 'abc123 0 0\n' >"$dir/ci-wait.txt"
rm -f "$dir/ci-result.txt"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 6 ]
if printf '%s\n' "$out" | grep -q 'no checks'; then
	echo "a failed poll must not read as no checks" >&2
	exit 1
fi
printf 'abc123 0 99999999999\n' >"$dir/ci-wait.txt"
rc=0
out=$(await --slice 0) || rc=$?
[ "$rc" -eq 5 ]
[ ! -f "$dir/ci-result.txt" ] || ! grep -q '^none' "$dir/ci-result.txt"
rm -f "$stub/pr-checks.exit" "$dir/ci-wait.txt"

# A failure is digested for the editor: the check, its run's title,
# summary, and annotations, and the failed steps' log with colour and
# timestamps removed. Nothing of it reaches the output.
checks "fail	tests	$run	CI	Tests failed" "pass	build	$run	CI	"
printf '55\ttests\tTests failed\t2 failed\\n1 passed\n56\tbuild\t\t\n' >"$stub/api-repos_o_r_commits_abc123_check-runs"
printf 'src/app.py:42 failure AssertionError assert 1 == 2\n' >"$stub/api-repos_o_r_check-runs_55_annotations"
printf 'tests\tRun tests\t2026-10-14T10:00:00.1234567Z \033[31m##[error]assert 1 == 2\033[0m\ntests\tRun tests\t2026-10-14T10:00:01.0000000Z FAILED tests/test_app.py::test_x\n' >"$stub/run-view"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "await-checks: fail 1 of 2: tests; signature new" ]
[ "$(cat "$dir/ci-result.txt")" = "fail abc123" ]
digest="$dir/pr-context/ci-failure.txt"
grep -qx "check tests fail $run" "$digest"
grep -qx 'description Tests failed' "$digest"
grep -qx 'title Tests failed' "$digest"
grep -qx 'summary 2 failed' "$digest"
grep -qx 'summary 1 passed' "$digest"
grep -qx 'annotation src/app.py:42 failure AssertionError assert 1 == 2' "$digest"
grep -qx 'log tests	Run tests	##\[error\]assert 1 == 2' "$digest"
grep -qx 'log tests	Run tests	FAILED tests/test_app.py::test_x' "$digest"
if grep -q 'build' "$digest"; then
	echo "a passing check has no place in the digest" >&2
	exit 1
fi
grep -q '^run view 11 --repo o/r --log-failed$' "$stub/calls.log"
[ "$(grep -c . "$dir/ci-attempts.txt")" -eq 1 ]
grep -q '^abc123 [0-9a-f]* tests$' "$dir/ci-attempts.txt"

# The same failure again is a repeat; a different annotation is new,
# and a check without an Actions run says its logs are unavailable.
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "await-checks: fail 1 of 2: tests; signature repeat" ]
[ "$(grep -c . "$dir/ci-attempts.txt")" -eq 2 ]
printf 'src/app.py:50 failure AssertionError assert 2 == 3\n' >"$stub/api-repos_o_r_check-runs_55_annotations"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "await-checks: fail 1 of 2: tests; signature new" ]
checks "fail	lint	https://ci.example.invalid/builds/9	external	Lint failed"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "await-checks: fail 1 of 1: lint; signature new" ]
grep -qx 'logs unavailable' "$digest"
if grep -q 'assert' "$digest"; then
	echo "the digest must hold only this failure" >&2
	exit 1
fi

# Empty fields stay in place: a check without a workflow keeps its
# description, and a run with no title keeps its summary.
checks "fail	lint	https://ci.example.invalid/builds/9		Lint failed"
printf '57\tlint\t\tonly a summary\n' >"$stub/api-repos_o_r_commits_abc123_check-runs"
printf '' >"$stub/api-repos_o_r_check-runs_57_annotations"
rc=0
out=$(await) || rc=$?
[ "$rc" -eq 3 ]
grep -qx 'description Lint failed' "$digest"
grep -qx 'summary only a summary' "$digest"
if grep -q '^title' "$digest"; then
	echo "an empty title must not shift the summary into it" >&2
	exit 1
fi

# No checks: with no workflows on the base the status grace passes and
# the run goes on; with workflows the schedule grace keeps it pending.
: >"$stub/pr-checks"
[ "$(await)" = "await-checks: no checks" ]
[ "$(cat "$dir/ci-result.txt")" = "none abc123" ]
mkdir -p "$clone/.github/workflows"
printf 'on: pull_request\n' >"$clone/.github/workflows/ci.yml"
git -C "$clone" add .github && git -C "$clone" commit -q -m "Add a workflow"
git -C "$clone" update-ref refs/remotes/origin/main HEAD
rm -f "$dir/ci-wait.txt"
rc=0
out=$(AWAIT_CHECKS_SCHEDULE_GRACE=600 await --slice 0) || rc=$?
[ "$rc" -eq 5 ]
[ "$out" = "await-checks: no checks reported yet, call again" ]
[ "$(await)" = "await-checks: no checks" ]

# A cancelled Actions run is rerun once and waited for; cancelled
# again after the rerun grace, it is a failure.
rm -f "$stub/pr-checks" "$stub/calls.log"
printf 'cancel\tbuild\thttps://github.com/o/r/actions/runs/77/job/1\tCI\t\n' >"$stub/pr-checks.1"
printf 'pass\tbuild\thttps://github.com/o/r/actions/runs/77/job/1\tCI\t\n' >"$stub/pr-checks.2"
: >"$stub/run-rerun"
out=$(await)
[ "$out" = "$(printf 'await-checks: run 77 was cancelled, rerunning its failed jobs once\nawait-checks: pass 1 checks')" ]
grep -qx 'run rerun 77 --failed --repo o/r' "$stub/calls.log"
grep -q '^77 [0-9]*$' "$dir/ci-reruns.txt"
checks "cancel	build	https://github.com/o/r/actions/runs/77/job/1	CI	"
rc=0
out=$(AWAIT_CHECKS_RERUN_GRACE=0 await) || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "await-checks: fail 1 of 1: build; signature new" ]
[ "$(grep -c '^run rerun' "$stub/calls.log")" -eq 1 ]
grep -qx 'check build cancel https://github.com/o/r/actions/runs/77/job/1' "$digest"

if sh "$REPO_ROOT/scripts/await-checks.sh" "$SCRATCH/nowhere" 2>"$SCRATCH/err"; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
grep -q "no meta.txt" "$SCRATCH/err"
if await --wat 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --wat" "$SCRATCH/err"
