#!/bin/sh
# Run the project's check command in the worktree and record any failure.
# Usage: sh scripts/run-check.sh <state-dir> <command>
set -eu

dir=${1:?usage: run-check.sh <state-dir> <command>}
cmd=${2:-}
worktree="$dir/worktree"
ctx="$dir/pr-context"
[ -d "$worktree" ] && [ -d "$ctx" ] || {
	echo "run-check: state in $dir is incomplete, run checkout-pr.sh first" >&2
	exit 1
}
rm -f "$ctx/check-failure.txt"
if [ -z "$cmd" ]; then
	echo "run-check: no command configured"
	exit 0
fi

out=$(mktemp "$ctx/.check.XXXXXX")
trap 'rm -f "$out"' EXIT
if (cd "$worktree" && sh -c "$cmd") >"$out" 2>&1; then
	echo "run-check: pass"
	exit 0
fi

tail -n 60 "$out" >"$ctx/check-failure.txt"
echo "run-check: fail, output tail in pr-context/check-failure.txt"
exit 3
