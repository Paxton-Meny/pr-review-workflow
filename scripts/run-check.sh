#!/bin/sh
# Run the project's check command in the worktree and record any failure.
# Usage: sh scripts/run-check.sh <state-dir> [command]
# Without a command, the run's resolved check_command is used.
set -eu

dir=${1:?usage: run-check.sh <state-dir> [command]}
if [ $# -ge 2 ]; then
	cmd=$2
elif [ -f "$dir/settings.txt" ]; then
	cmd=$(sh "$(dirname "$0")/setting.sh" "$dir" check_command)
else
	cmd=''
fi
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
