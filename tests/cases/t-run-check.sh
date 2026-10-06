#!/bin/sh
# run-check: passes, fails with a recorded tail, no-ops without a command.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir/worktree" "$dir/pr-context"
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
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt")
[ "$out" = "run-check: pass" ]
printf 'y\n' >"$dir/worktree/file.txt"
rc=0
sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt" >/dev/null || rc=$?
[ "$rc" -eq 3 ]

# A baseline that failed disarms the gate for that command.
out=$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --baseline "grep -q x file.txt")
[ "$out" = "run-check: fail, output tail in pr-context/check-failure.txt" ]
grep -q '^fail ' "$dir/check-baseline.txt"
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q x file.txt")" = "run-check: gate disarmed, the baseline failed" ]

# A changed command, or no baseline at all, is baselined again first.
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q y file.txt")" = "run-check: rebaselined, pass" ]
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q y file.txt")" = "run-check: pass" ]
rm -f "$dir/check-baseline.txt"
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate "grep -q z file.txt")" = "run-check: rebaselined, fail; gate disarmed" ]
[ "$(sh "$REPO_ROOT/scripts/run-check.sh" "$dir" --gate)" = "run-check: no command configured" ]
