#!/bin/sh
# Run every test case under tests/cases/ against a scratch workspace.
# Usage: sh tests/run.sh
set -eu

unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT TERM

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

total=$((passed + failed))
if [ "$total" -eq 0 ]; then
	echo "tests: no cases discovered under tests/cases/" >&2
	exit 1
fi
echo "tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
