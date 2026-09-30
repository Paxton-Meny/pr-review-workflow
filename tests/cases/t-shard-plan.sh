#!/bin/sh
# shard-plan: coupling clusters, balance, seams, determinism, validation.
set -eu

dir="$SCRATCH/state"
ctx="$dir/pr-context"
mkdir -p "$ctx/files"

printf '001\tsrc/retry.py\n002\tsrc/unrelated.py\n003\ttests/test_retry.py\n004\tdocs/guide.md\n' >"$ctx/diff-index.txt"
printf 'src/retry.py\t900\t100\nsrc/unrelated.py\t800\t0\ntests/test_retry.py\t500\t0\ndocs/guide.md\t700\t0\n' >"$ctx/files.txt"
printf 'path: src/retry.py\n@@ -0,0 +1,1 @@\nR1 +def backoff():\n' >"$ctx/files/001.diff"
printf 'path: src/unrelated.py\n@@ -0,0 +1,1 @@\nR1 +def solo():\n' >"$ctx/files/002.diff"
printf 'path: tests/test_retry.py\n@@ -0,0 +1,1 @@\nR1 +from src.retry import backoff\n' >"$ctx/files/003.diff"
printf 'path: docs/guide.md\n@@ -0,0 +1,1 @@\nR1 +plain words only\n' >"$ctx/files/004.diff"

out=$(sh "$REPO_ROOT/scripts/shard-plan.sh" "$dir" 4 1500)
[ "$out" = "shard-plan: groups 2 seams 0" ]
grep -q '^group 1 lines 1500 files 001 003$' "$ctx/shards.txt"
grep -q '^group 2 lines 1500 files 002 004$' "$ctx/shards.txt"
[ ! -f "$ctx/seams.txt" ]

first=$(cat "$ctx/shards.txt")
out2=$(sh "$REPO_ROOT/scripts/shard-plan.sh" "$dir" 4 1500)
[ "$out2" = "$out" ]
[ "$(cat "$ctx/shards.txt")" = "$first" ]

printf 'src/retry.py\t2600\t0\nsrc/unrelated.py\t800\t0\ntests/test_retry.py\t2500\t0\ndocs/guide.md\t700\t0\n' >"$ctx/files.txt"
out=$(sh "$REPO_ROOT/scripts/shard-plan.sh" "$dir" 4 1500)
printf '%s\n' "$out" | grep -q '^shard-plan: groups '
printf '%s\n' "$out" | grep -qv 'seams 0$'
grep -q 'split across groups' "$ctx/seams.txt"
grep -q 'src/retry.py' "$ctx/seams.txt"
grep -q 'tests/test_retry.py' "$ctx/seams.txt"
grep -q 'shared name: retry' "$ctx/seams.txt"

printf '001\tsrc/a.py\n' >"$ctx/diff-index.txt"
printf 'src/a.py\t100\t0\n' >"$ctx/files.txt"
printf 'path: src/a.py\n@@ -0,0 +1,1 @@\nR1 +x = 1\n' >"$ctx/files/001.diff"
out=$(sh "$REPO_ROOT/scripts/shard-plan.sh" "$dir" 4 1500)
[ "$out" = "shard-plan: groups 1 seams 0" ]
grep -q '^group 1 lines 100 files 001$' "$ctx/shards.txt"

if sh "$REPO_ROOT/scripts/shard-plan.sh" "$SCRATCH/empty" 4 1500 2>"$SCRATCH/err"; then
	echo "expected failure without a diff index" >&2
	exit 1
fi
grep -q "no diff-index.txt" "$SCRATCH/err"

if sh "$REPO_ROOT/scripts/shard-plan.sh" "$dir" 4 abc 2>"$SCRATCH/err"; then
	echo "expected refusal of a non-numeric shard size" >&2
	exit 1
fi
grep -q "must be numbers" "$SCRATCH/err"
