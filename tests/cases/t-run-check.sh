#!/bin/sh
# run-check: passes, fails with a recorded tail, no-ops without a command.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir/worktree" "$dir/pr-context"
. "$REPO_ROOT/tests/fixture-identity.sh"
# The signed-in account's own pull request: its code may run.
printf 'author %s\nself_login %s\n' "$fixture_login" "$fixture_login" >"$dir/meta.txt"
printf 'x\n' >"$dir/worktree/file.txt"

out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" "grep -q x file.txt")
[ "$out" = "run-check: pass" ]
[ ! -f "$dir/pr-context/check-failure.txt" ]

rc=0
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" "echo boom line; grep -q missing file.txt") || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "run-check: fail, output tail in pr-context/check-failure.txt" ]
grep -qx 'boom line' "$dir/pr-context/check-failure.txt"

out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir")
[ "$out" = "run-check: no command configured" ]
[ ! -f "$dir/pr-context/check-failure.txt" ]

if sh "$REPO_ROOT/scripts/run-check.sh" "$SCRATCH/empty" true 2>"$SCRATCH/err"; then
	echo "expected failure without a worktree" >&2
	exit 1
fi
grep -q "incomplete" "$SCRATCH/err"

# The baseline is recorded per command, so the gate survives a resume.
git -C "$dir/worktree" init -q 2>/dev/null || true
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --baseline "grep -q x file.txt")
[ "$out" = "run-check: pass" ]
grep -q '^pass ' "$dir/check-baseline.txt"
[ ! -f "$dir/check-gate.txt" ]
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt")
[ "$out" = "run-check: pass" ]
# Each gate run records its outcome for merge-pr, a new baseline clears it.
grep -q '^pass ' "$dir/check-gate.txt"
printf 'y\n' >"$dir/worktree/file.txt"
rc=0
sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt" >/dev/null || rc=$?
[ "$rc" -eq 3 ]
grep -q '^fail ' "$dir/check-gate.txt"

# A baseline that failed disarms the gate for that command.
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --baseline "grep -q x file.txt")
[ "$out" = "run-check: fail, output tail in pr-context/check-failure.txt" ]
grep -q '^fail ' "$dir/check-baseline.txt"
[ ! -f "$dir/check-gate.txt" ]
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt")" = "run-check: gate disarmed, the baseline failed" ]

# A changed command, or no baseline at all, is baselined again first.
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q y file.txt")" = "run-check: rebaselined, pass" ]
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q y file.txt")" = "run-check: pass" ]
rm -f "$dir/check-baseline.txt"
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q z file.txt")" = "run-check: rebaselined, fail; gate disarmed" ]
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate)" = "run-check: no command configured" ]

# Another account's fork: the command would run its code, so it is
# skipped in every mode, until the user approves that author.
printf 'author someone-else\nself_login %s\ncross_repo true\n' "$fixture_login" >"$dir/meta.txt"
for mode in '' --baseline --gate; do
	out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" $mode "touch $SCRATCH/ran")
	[ "$out" = "run-check: skipped, the pull request's author is not trusted to run code here (author-trust.sh)" ]
done
[ ! -e "$SCRATCH/ran" ]
sh "$REPO_ROOT/scripts/approve-author.sh" "$dir" >/dev/null
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" "touch $SCRATCH/ran")" = "run-check: pass" ]
[ -e "$SCRATCH/ran" ]
