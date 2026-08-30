#!/bin/sh
# Run every test case under tests/cases/ against a scratch workspace.
# Usage: sh tests/run.sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT INT TERM

passed=0
failed=0
for tc in "$root/tests/cases"/t-*.sh; do
	[ -f "$tc" ] || continue
	name=$(basename "$tc")
	tc_scratch="$scratch/${name%.sh}"
	mkdir -p "$tc_scratch"
	if REPO_ROOT="$root" SCRATCH="$tc_scratch" sh "$tc" >"$tc_scratch/log" 2>&1; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		echo "FAIL  $name" >&2
		sed 's/^/      /' "$tc_scratch/log" >&2
	fi
done

echo "tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
