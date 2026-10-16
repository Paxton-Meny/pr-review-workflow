#!/bin/sh
# round-counter: persists across invocations and enforces the cap.
set -eu

dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner a\nrepo w\npr 7\n' >"$dir/meta.txt"

[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 3)" = "round 1 of 3" ]
[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 3)" = "round 2 of 3" ]
[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 3)" = "round 3 of 3" ]
rc=0
sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" next 3 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 3 ]
grep -q "round cap of 3 reached" "$SCRATCH/err"
grep -qx '3' "$dir/rounds.txt"
# Each round and the cap are journaled for next-step.sh.
[ "$(cat "$dir/steps.txt")" = "$(printf 'round 1\nround 2\nround 3\nround cap')" ]

if sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" wat 3 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown operation" >&2
	exit 1
fi
grep -q "unknown operation" "$SCRATCH/err"

# The repairs of failing checks have their own counter, capped by the
# run's ci_fix_rounds setting.
run="$SCRATCH/data/state/a__w__7"
mkdir -p "$run"
printf 'owner a\nrepo w\npr 7\n' >"$run/meta.txt"
printf 'ci_fix_rounds 2\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$run" >/dev/null
[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$run" next ci)" = "ci round 1 of 2" ]
[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$run" next 4)" = "round 1 of 4" ]
[ "$(sh "$REPO_ROOT/scripts/round-counter.sh" "$run" next ci)" = "ci round 2 of 2" ]
rc=0
sh "$REPO_ROOT/scripts/round-counter.sh" "$run" next ci 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 3 ]
grep -q "ci round cap of 2 reached" "$SCRATCH/err"
grep -qx '2' "$run/ci-rounds.txt"
grep -qx '1' "$run/rounds.txt"
[ "$(cat "$run/steps.txt")" = "$(printf 'ci-round 1\nround 1\nci-round 2\nci-round cap')" ]
