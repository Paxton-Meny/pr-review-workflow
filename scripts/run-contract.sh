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
# beyond commands the user already chose to trust. A Check line naming
# migration tooling never runs, even under an allowed prefix: migrations
# are judged by reading, and no contract may touch a database. Nothing
# runs on the code of an author author-trust.sh --exec does not allow.
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
if ! sh "$(dirname "$0")/author-trust.sh" "$dir" --exec >/dev/null 2>&1; then
	echo "run-contract: $id verdict not-executable reason untrusted-author"
	exit 4
fi
if printf '%s' "$cmd" | grep -q '[;&|$<>`\\]'; then
	echo "run-contract: $id verdict not-executable reason metacharacters"
	exit 4
fi
tooling=0
sh "$(dirname "$0")/migration-tool.sh" "$cmd" || tooling=$?
case "$tooling" in
0) ;;
3)
	echo "run-contract: $id verdict not-executable reason migration-tooling"
	exit 4
	;;
*) exit 1 ;;
esac

allowed=0
matched=''
if [ -n "$check" ]; then
	case "$cmd" in
	"$check" | "$check "*)
		allowed=1
		matched=$check
		;;
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
			matched=$prefix
			break
			;;
		esac
	done
fi
if [ "$allowed" -eq 0 ]; then
	echo "run-contract: $id verdict not-executable reason unapproved-prefix"
	exit 4
fi
# The prefix is the user's; the arguments after it are the reviewer's.
# They may not name a path outside the worktree (absolute, ~, or a ..
# segment, also after any =), as in pytest --basetemp=/home/you, which
# empties that folder, nor carry quotes, globs, braces, parentheses, #,
# or !. A ./... package pattern is fine.
args=${cmd#"$matched"}
unsafe=0
if printf '%s' "$args" | grep -q "[][\"'*?{}()#!]"; then
	unsafe=1
fi
set -f
for word in $args; do
	part=$word
	while :; do
		case "$part" in
		/* | '~'* | .. | ../* | */.. | */../*) unsafe=1 ;;
		esac
		case "$part" in
		*=*) part=${part#*=} ;;
		*) break ;;
		esac
	done
done
set +f
if [ "$unsafe" -eq 1 ]; then
	echo "run-contract: $id verdict not-executable reason unsafe-argument"
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
