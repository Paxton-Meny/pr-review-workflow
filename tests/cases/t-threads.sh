#!/bin/sh
# reply-thread and resolve-threads: happy paths, pagination, validation.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner Paxton-Meny\nrepo widgets\npr 7\n' >"$dir/meta.txt"

printf '5555\n' >"$stub/api-repos_Paxton-Meny_widgets_pulls_7_comments_9001_replies"
printf 'Kept as is: the loop is bounded.\n' | sh "$REPO_ROOT/scripts/reply-thread.sh" "$dir" 9001 \
	| grep -qx 'reply-thread: replied to 9001 as 5555'

if printf 'x\n' | sh "$REPO_ROOT/scripts/reply-thread.sh" "$dir" '9001; rm -rf /' 2>"$SCRATCH/err"; then
	echo "expected refusal of a non-numeric comment id" >&2
	exit 1
fi
grep -q "must be numeric" "$SCRATCH/err"

# resolve-threads closes the thread of every verified finding, from one
# listing of the pull request's threads.
record() {
	# record <id> <status> <comment id or nothing>
	mkdir -p "$dir/findings"
	printf 'id: %s\nstatus: %s\ncomment_id: %s\n---\nBody.\n' "$1" "$2" "$3" >"$dir/findings/$1"
}
resolve() { sh "$REPO_ROOT/scripts/resolve-threads.sh" "$dir"; }
mutations() { grep -c 'resolveReviewThread' "$stub/calls.log" || true; }
reset() { rm -f "$stub"/api-graphql* "$stub/calls.log"; }

record F001 addressed 9001
[ "$(resolve)" = 'resolve-threads: no verified finding has a thread' ]
[ ! -f "$stub/calls.log" ] || ! grep -q graphql "$stub/calls.log"

# Verified findings resolve; one already resolved, one still open, and
# one posted in the summary are left alone.
record F001 verified 9001
record F002 verified 9002
record F003 open 9003
record F004 verified ''
reset
printf 'page false null\nthread PRRT_a false 9001\nthread PRRT_b true 9002\nthread PRRT_c false 9003\n' >"$stub/api-graphql.1"
printf 'true\n' >"$stub/api-graphql.2"
[ "$(resolve)" = 'resolve-threads: resolved 1, already resolved 1, failed 0' ]
[ "$(mutations)" -eq 1 ]
grep -q 'threadId: \\*"PRRT_a' "$stub/calls.log"

# The listing follows every page.
reset
printf 'page true CURSOR1\nthread PRRT_b true 9002\n' >"$stub/api-graphql.1"
printf 'page false null\nthread PRRT_a false 9001\n' >"$stub/api-graphql.2"
printf 'true\n' >"$stub/api-graphql.3"
[ "$(resolve)" = 'resolve-threads: resolved 1, already resolved 1, failed 0' ]
grep -q 'after: \\*"CURSOR1' "$stub/calls.log"

# A thread that is missing or does not resolve is named, the rest still
# resolve, and the exit says so.
reset
printf 'page false null\nthread PRRT_a false 9001\n' >"$stub/api-graphql.1"
printf 'false\n' >"$stub/api-graphql.2"
rc=0
out=$(resolve 2>"$SCRATCH/err") || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = 'resolve-threads: resolved 0, already resolved 0, failed 2' ]
grep -qx 'resolve-threads: F001: the thread of comment 9001 did not resolve' "$SCRATCH/err"
grep -qx 'resolve-threads: F002: no thread starts with comment 9002' "$SCRATCH/err"

# The review session runs it; no agent closes a thread.
skill="$REPO_ROOT/skills/review-pr/SKILL.md"
grep -qx '  - Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-threads.sh \*)' "$skill"
grep -q 'scripts/resolve-threads.sh <dir>' "$skill"
if grep -q 'resolve-thread' "$REPO_ROOT/agents/verifier.md" "$REPO_ROOT/scripts/agent-scope.sh"; then
	echo "an agent still resolves threads" >&2
	exit 1
fi
