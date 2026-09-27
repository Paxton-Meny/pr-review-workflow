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
