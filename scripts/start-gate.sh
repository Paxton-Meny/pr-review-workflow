#!/bin/sh
# Decide, as a PreToolUse hook on the Skill tool, whether Claude may start a review it chose to run.
# Usage: sh scripts/start-gate.sh <self_start from the plugin configuration> <hook-input.json
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
input=$(tr -d '\n')

case "$input" in
*'"pr-review-workflow:review-pr"'* | *'"review-pr"'*) ;;
*) exit 0 ;;
esac

decide() {
	reason=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\t\r')
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
	exit 0
}

field() {
	printf '%s' "$input" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"\\\\]*\)\".*/\1/p"
}

args=$(field args)
ref=${args%%[[:space:]]*}
[ -n "$ref" ] || decide deny "Pass the pull request as the argument: a number, owner/repo#n, or a URL."
[ "$(printf '%s' "${args#"$ref"}" | tr -s '[:space:]' ' ' | sed 's/ $//')" = ' auto_approve=false' ] ||
	decide deny "A review you start yourself takes exactly the pull request and auto_approve=false, as in: $ref auto_approve=false. Other per-run settings are for the user to type."

cwd=$(field cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

resolved=$(sh "$here/resolve-ref.sh" "$ref" 2>&1) || decide deny "$resolved"
owner=${resolved%% *}
rest=${resolved#* }
repo=${rest%% *}
number=${rest#* }
pr="$owner/$repo#$number"
effect="The review posts comments to the pull request and pushes fixes to its branch."

facts=$(gh pr view "$number" --repo "$owner/$repo" \
	--json state,isDraft,headRefName,headRefOid,reviews,statusCheckRollup \
	--jq '"state \(.state)\ndraft \(.isDraft)\nhead_branch \(.headRefName)\nhead_sha \(.headRefOid)\nreviewers \([.reviews[].author.login] | unique | join(", "))\nfailing \([.statusCheckRollup[]? | select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .state == "FAILURE" or .state == "ERROR")] | length)"' 2>/dev/null) ||
	decide ask "Claude wants to start a review of $pr, but GitHub could not be read, so nothing was checked. $effect"
fact() {
	printf '%s\n' "$facts" | sed -n "s/^$1 //p"
}

state=$(fact state)
[ "$state" = OPEN ] || decide deny "$pr is ${state:-unknown}, not open; there is nothing to review."

holds=''
hold() {
	holds="${holds:+$holds; }$1"
}
[ "$(fact draft)" = true ] && hold "it is a draft"
reviewers=$(fact reviewers)
[ -n "$reviewers" ] && hold "it already has reviews from $reviewers"
failing=$(fact failing)
[ "${failing:-0}" -gt 0 ] 2>/dev/null && hold "$failing checks are failing"
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
	hold "the plugin data directory is unknown, so an earlier run could not be ruled out"
elif [ -d "$CLAUDE_PLUGIN_DATA/state/${owner}__${repo}__${number}" ]; then
	hold "this machine already has a review run for it"
fi
[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && hold "the clone has uncommitted changes"
if [ "$(git symbolic-ref --short -q HEAD 2>/dev/null)" = "$(fact head_branch)" ] &&
	[ "$(git rev-parse HEAD 2>/dev/null)" != "$(fact head_sha)" ]; then
	hold "the local branch differs from the pushed head"
fi

[ -z "$holds" ] || decide ask "Claude wants to start a review of $pr, but $holds. $effect"
mode=${1:-ask}
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
	resolved_mode=$(printf 'self_start %s\n' "$mode" | sh "$here/resolve-settings.sh" --preview "$CLAUDE_PLUGIN_DATA" 2>/dev/null |
		sed -n 's/^settings: self_start \([a-z]*\) from .*/\1/p' | tail -n 1)
	[ -n "$resolved_mode" ] && mode=$resolved_mode
fi
[ "$mode" = auto ] && exit 0
decide ask "Claude wants to start a review of $pr. $effect"
