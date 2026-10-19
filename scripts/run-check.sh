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
# current commit first. Exit 3 means the check fails. The command runs
# the pull request's code, so it runs only when author-trust.sh --exec
# allows it; otherwise the check is skipped (exit 0) as if unset.
# Each armed gate run records its outcome in check-gate.txt, in the same
# form, so merge-pr.sh can tell whether the check passed at the head it
# merges; a new baseline replaces that record. Every --gate run, armed
# or not, is journaled in steps.txt as "gate pass|fail|disarmed|none
# <commit>" for next-step.sh.
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
journal() {
	# journal <outcome>: a gate run, for next-step.sh
	[ "$mode" = gate ] || return 0
	printf 'gate %s %s\n' "$1" "$(git -C "$worktree" rev-parse HEAD 2>/dev/null || echo unknown)" >>"$dir/steps.txt"
}
if [ -z "$cmd" ]; then
	journal none
	echo "run-check: no command configured"
	exit 0
fi
if ! sh "$(dirname "$0")/author-trust.sh" "$dir" --exec >/dev/null 2>&1; then
	journal none
	echo "run-check: skipped, the pull request's author is not trusted to run code here (author-trust.sh)"
	exit 0
fi

out=$(mktemp "$ctx/.check.XXXXXX")
trap 'rm -f "$out"' EXIT
check() {
	(cd "$worktree" && sh -c "$cmd") >"$out" 2>&1
}
record() {
	# record pass|fail [file]
	printf '%s %s %s\n' "$1" "$cmd_hash" "$(git -C "$worktree" rev-parse HEAD 2>/dev/null || echo unknown)" >"$dir/${2:-check-baseline.txt}"
	[ -n "${2:-}" ] || rm -f "$dir/check-gate.txt"
}
cmd_hash=$(printf '%s' "$cmd" | git hash-object --stdin)

if [ "$mode" = gate ]; then
	baseline=''
	[ -f "$dir/check-baseline.txt" ] && baseline=$(cat "$dir/check-baseline.txt")
	case "$baseline" in
	"pass $cmd_hash "*) ;;
	"fail $cmd_hash "*)
		journal disarmed
		echo "run-check: gate disarmed, the baseline failed"
		exit 0
		;;
	*)
		# No baseline for this command: take one at the current commit.
		if check; then
			record pass
			journal pass
			echo "run-check: rebaselined, pass"
			exit 0
		fi
		record fail
		journal disarmed
		tail -n 60 "$out" >"$ctx/check-failure.txt"
		echo "run-check: rebaselined, fail; gate disarmed"
		exit 0
		;;
	esac
fi

if check; then
	[ "$mode" = baseline ] && record pass
	[ "$mode" = gate ] && record pass check-gate.txt
	journal pass
	echo "run-check: pass"
	exit 0
fi

[ "$mode" = baseline ] && record fail
[ "$mode" = gate ] && record fail check-gate.txt
journal fail
tail -n 60 "$out" >"$ctx/check-failure.txt"
echo "run-check: fail, output tail in pr-context/check-failure.txt"
[ "$mode" = baseline ] && exit 0
exit 3
