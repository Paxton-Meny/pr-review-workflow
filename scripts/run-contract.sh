#!/bin/sh
# Run one finding's Check line in the worktree when policy allows it.
# Usage: sh scripts/run-contract.sh <state-dir> <id> [check-command] [extra-prefixes]
#        sh scripts/run-contract.sh --policy <state-dir> <id> [check-command] [extra-prefixes]
# Exit 0: the check ran and passed. Exit 3: it ran and failed (tail on
# stdout). Exit 4: no runnable check; judge the finding by reading.
# With --policy nothing runs: exit 0 says the line would be allowed to
# run, exit 4 says why not, so the router can tell an executable
# contract from one that will be judged by reading. Without the command
# arguments, the run's resolved check_command and contract_commands
# are used.
#
# A Check line executes only when it starts with the configured check
# command or one of the comma-separated extra prefixes, and contains no
# shell metacharacters. Reviewer-authored text never widens what can run
# beyond commands the user already chose to trust.
set -eu

policy=0
if [ "${1:-}" = --policy ]; then
	policy=1
	shift
fi
dir=${1:?usage: run-contract.sh <state-dir> <id> [check-command] [extra-prefixes]}
id=${2:?usage: run-contract.sh <state-dir> <id> [check-command] [extra-prefixes]}
if [ $# -ge 3 ]; then
	check=$3
	extra=${4:-}
else
	check=$(sh "$(dirname "$0")/setting.sh" "$dir" check_command)
	extra=$(sh "$(dirname "$0")/setting.sh" "$dir" contract_commands)
fi

record="$dir/findings/$id"
[ -f "$record" ] || {
	echo "run-contract: unknown finding: $id" >&2
	exit 1
}
worktree="$dir/worktree"
[ -d "$worktree" ] || {
	echo "run-contract: no worktree in $dir, run checkout-pr.sh first" >&2
	exit 1
}

cmd=$(sed -n 's/^Check: //p' "$record" | head -n 1)
if [ -z "$cmd" ]; then
	echo "run-contract: $id verdict not-executable reason no-check-line"
	exit 4
fi
if printf '%s' "$cmd" | grep -q '[;&|$<>`\\]'; then
	echo "run-contract: $id verdict not-executable reason metacharacters"
	exit 4
fi

allowed=0
if [ -n "$check" ]; then
	case "$cmd" in
	"$check" | "$check "*) allowed=1 ;;
	esac
fi
if [ "$allowed" -eq 0 ] && [ -n "$extra" ]; then
	rest="$extra,"
	while [ -n "$rest" ]; do
		prefix=${rest%%,*}
		rest=${rest#*,}
		prefix=${prefix# }
		prefix=${prefix% }
		[ -n "$prefix" ] || continue
		case "$cmd" in
		"$prefix" | "$prefix "*)
			allowed=1
			break
			;;
		esac
	done
fi
if [ "$allowed" -eq 0 ]; then
	echo "run-contract: $id verdict not-executable reason unapproved-prefix"
	exit 4
fi
if [ "$policy" -eq 1 ]; then
	echo "run-contract: $id verdict executable"
	exit 0
fi

out=$(mktemp "$dir/findings/.contract.XXXXXX")
trap 'rm -f "$out"' EXIT
if (cd "$worktree" && sh -c "$cmd") >"$out" 2>&1; then
	echo "run-contract: $id verdict satisfied"
	exit 0
fi
echo "run-contract: $id verdict failed"
tail -n 40 "$out"
exit 3
