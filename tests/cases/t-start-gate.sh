#!/bin/sh
# start-gate: ignores other skills, refuses what cannot run, asks unless auto finds the pull request ready, never allows.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
export CLAUDE_PLUGIN_DATA="$SCRATCH/data"
unset CLAUDE_PLUGIN_OPTION_SELF_START
gate="$REPO_ROOT/scripts/start-gate.sh"

clone="$SCRATCH/clone"
git init --quiet "$clone"
git -C "$clone" config user.name tester
git -C "$clone" config user.email tester@example.invalid
git -C "$clone" remote add origin https://github.com/acme/widgets.git
git -C "$clone" checkout --quiet -b feat-thing
printf 'a\n' >"$clone/file.txt"
git -C "$clone" add -A
git -C "$clone" commit --quiet -m "Root"
head=$(git -C "$clone" rev-parse HEAD)

facts() {
	printf 'state %s\ndraft %s\nhead_branch feat-thing\nhead_sha %s\nreviewers %s\nfailing %s\n' "$1" "$2" "$3" "$4" "$5" >"$stub/pr-view"
}
call() {
	printf '{"session_id":"s","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"%s","args":"%s"}}' "$clone" "$2" "$3" |
		sh "$gate" "$1" >"$SCRATCH/out"
}
decision() {
	sed -n 's/.*"permissionDecision":"\([a-z]*\)".*/\1/p' "$SCRATCH/out"
}
reason() {
	sed -n 's/.*"permissionDecisionReason":"\(.*\)"}}$/\1/p' "$SCRATCH/out"
}

facts OPEN false "$head" '' 0
call ask anthropic-skills:pdf 'acme/widgets#7 auto_approve=false'
[ ! -s "$SCRATCH/out" ]

call ask pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -qx 'Claude wants to start a review of acme/widgets#7. The review posts comments to the pull request and pushes fixes to its branch.'

call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ ! -s "$SCRATCH/out" ]

printf 'acme widgets\n' >"$stub/repo-view"
call auto review-pr '7  auto_approve=false '
[ ! -s "$SCRATCH/out" ]

call '' pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
CLAUDE_PLUGIN_OPTION_SELF_START=auto call '' pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ ! -s "$SCRATCH/out" ]
CLAUDE_PLUGIN_OPTION_SELF_START=auto call ask pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]

call auto pr-review-workflow:review-pr ''
[ "$(decision)" = deny ]
reason | grep -q 'Pass the pull request as the argument'

# A refusal quoting a multi-line error stays one valid JSON line: gh's
# own stderr arrives with newlines and control characters in it.
printf '1\n' >"$stub/repo-view.exit"
printf 'failed to run git: fatal: not a git repository\n\tStopping at filesystem boundary\001.\r\n\n' >"$stub/repo-view.err"
call auto pr-review-workflow:review-pr '7 auto_approve=false'
rm -f "$stub/repo-view.exit" "$stub/repo-view.err"
[ "$(wc -l <"$SCRATCH/out" | tr -d ' ')" -eq 1 ]
[ "$(decision)" = deny ]
reason | grep -q 'failed to run git: fatal: not a git repository  Stopping at filesystem boundary.   resolve-ref: not inside a GitHub repository'
if LC_ALL=C grep -q "$(printf '[\001-\010\013-\037]')" "$SCRATCH/out"; then
	echo "the decision holds a raw control character" >&2
	exit 1
fi

for args in 'acme/widgets#7' 'acme/widgets#7 auto_approve=true' 'acme/widgets#7 auto_approve=false check=make' 'acme/widgets#7 self_start=auto auto_approve=false'; do
	call auto pr-review-workflow:review-pr "$args"
	[ "$(decision)" = deny ]
	reason | grep -q 'takes exactly the pull request and auto_approve=false, as in: acme/widgets#7 auto_approve=false'
done

mkdir -p "$clone/.claude"
printf 'self_start auto\n' >"$clone/.claude/pr-review-workflow.local.conf"
call ask pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ ! -s "$SCRATCH/out" ]
printf 'self_start ask\n' >"$clone/.claude/pr-review-workflow.local.conf"
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
rm "$clone/.claude/pr-review-workflow.local.conf"

printf 'self_start auto\n' >"$clone/.claude/pr-review-workflow.conf"
git -C "$clone" add .claude/pr-review-workflow.conf
git -C "$clone" commit --quiet -m "Share settings"
git -C "$clone" update-ref refs/remotes/origin/main HEAD
git -C "$clone" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
head=$(git -C "$clone" rev-parse HEAD)
facts OPEN false "$head" '' 0
call ask pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -qx 'Claude wants to start a review of acme/widgets#7. The review posts comments to the pull request and pushes fixes to its branch.'

call auto pr-review-workflow:review-pr 'acme/widgets#7\"x auto_approve=false'
[ "$(decision)" = deny ]

call auto pr-review-workflow:review-pr 'acme/other#7 auto_approve=false'
[ "$(decision)" = deny ]
reason | grep -q 'not acme/other'

facts MERGED false "$head" '' 0
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = deny ]
reason | grep -q 'acme/widgets#7 is MERGED, not open'

facts OPEN true "$head" 'alice, bob' 2
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -q 'but it is a draft; it already has reviews from alice, bob; 2 checks are failing\. The review'

facts OPEN false "$head" '' 0
mkdir -p "$CLAUDE_PLUGIN_DATA/state/acme__widgets__7"
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -q 'this machine already has a review run for it'
rm -rf "$CLAUDE_PLUGIN_DATA/state/acme__widgets__7"

(
	unset CLAUDE_PLUGIN_DATA
	call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
	[ "$(decision)" = ask ]
	reason | grep -q 'an earlier run could not be ruled out'
)

printf 'b\n' >"$clone/file.txt"
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -q 'the clone has uncommitted changes'
git -C "$clone" checkout --quiet -- file.txt

facts OPEN false 0000000000000000000000000000000000000000 '' 0
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -q 'the local branch differs from the pushed head'

git -C "$clone" checkout --quiet -b elsewhere
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ ! -s "$SCRATCH/out" ]

rm "$stub/pr-view"
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = ask ]
reason | grep -q 'GitHub could not be read, so nothing was checked'

git -C "$clone" remote set-url origin 'https://example.invalid/"q"/widgets.git'
call auto pr-review-workflow:review-pr 'acme/widgets#7 auto_approve=false'
[ "$(decision)" = deny ]
grep -q 'is https://example.invalid/\\"q\\"/widgets.git, not acme/widgets' "$SCRATCH/out"

[ "$(grep -o 'decide [a-z]*' "$gate" | sort -u | tr '\n' ' ')" = 'decide ask decide deny ' ]
hooks="$REPO_ROOT/hooks/hooks.json"
grep -q '"matcher": "Skill"' "$hooks"
grep -q '"${CLAUDE_PLUGIN_ROOT}/scripts/start-gate.sh"]' "$hooks"
if grep -q 'user_config' "$hooks"; then
	echo "the hook must not name a plugin option: an unset option stops the hook from running" >&2
	exit 1
fi
grep -q '"onFailure": "block"' "$hooks"
