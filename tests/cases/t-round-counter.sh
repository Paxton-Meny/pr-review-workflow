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

if sh "$REPO_ROOT/scripts/round-counter.sh" "$dir" wat 3 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown operation" >&2
	exit 1
fi
grep -q "unknown operation" "$SCRATCH/err"
