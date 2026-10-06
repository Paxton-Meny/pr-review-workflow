#!/bin/sh
# Run the project's check command in the worktree and record any failure.
# Usage: sh scripts/run-check.sh <state-dir> [--baseline | --gate] [command]
# Without a command, the run's resolved check_command is used.
#
# --baseline runs the check and records the outcome in check-baseline.txt
# as "pass|fail <command hash> <commit>", so the gate survives a resume.
# --gate runs the check after a round of edits only when the recorded
# baseline passed for this same command: a baseline that failed disarms
# the gate (exit 0, "gate disarmed"), and a missing baseline, or one
# taken for a different command, is taken again at the worktree's
# current commit first. Exit 3 means the check fails.
set -eu

dir=${1:?usage: run-check.sh <state-dir> [--baseline | --gate] [command]}
shift
mode=plain
case "${1:-}" in
--baseline | --gate)
	mode=${1#--}
	shift
	;;
esac
set -- "$dir" "$@"
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
check() {
	(cd "$worktree" && sh -c "$cmd") >"$out" 2>&1
}
record() {
	# record pass|fail
	printf '%s %s %s\n' "$1" "$cmd_hash" "$(git -C "$worktree" rev-parse HEAD 2>/dev/null || echo unknown)" >"$dir/check-baseline.txt"
}
cmd_hash=$(printf '%s' "$cmd" | git hash-object --stdin)

if [ "$mode" = gate ]; then
	baseline=''
	[ -f "$dir/check-baseline.txt" ] && baseline=$(cat "$dir/check-baseline.txt")
	case "$baseline" in
	"pass $cmd_hash "*) ;;
	"fail $cmd_hash "*)
		echo "run-check: gate disarmed, the baseline failed"
		exit 0
		;;
	*)
		# No baseline for this command: take one at the current commit.
		if check; then
			record pass
			echo "run-check: rebaselined, pass"
			exit 0
		fi
		record fail
		tail -n 60 "$out" >"$ctx/check-failure.txt"
		echo "run-check: rebaselined, fail; gate disarmed"
		exit 0
		;;
	esac
fi

if check; then
	[ "$mode" = baseline ] && record pass
	echo "run-check: pass"
	exit 0
fi

[ "$mode" = baseline ] && record fail
tail -n 60 "$out" >"$ctx/check-failure.txt"
echo "run-check: fail, output tail in pr-context/check-failure.txt"
[ "$mode" = baseline ] && exit 0
exit 3
