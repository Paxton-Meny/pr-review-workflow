#!/bin/sh
# reply-thread and resolve-thread: happy paths and validation.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"

dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\n' >"$dir/meta.txt"

printf '5555\n' >"$stub/api-repos_acme_widgets_pulls_7_comments_9001_replies"
printf 'Addressed in abc123.\n' | sh "$REPO_ROOT/scripts/reply-thread.sh" "$dir" 9001 \
	| grep -qx 'reply-thread: replied to 9001 as 5555'

if printf 'x\n' | sh "$REPO_ROOT/scripts/reply-thread.sh" "$dir" '9001; rm -rf /' 2>"$SCRATCH/err"; then
	echo "expected refusal of a non-numeric comment id" >&2
	exit 1
fi
grep -q "must be numeric" "$SCRATCH/err"

printf 'PRRT_abc\n' >"$stub/api-graphql.1"
printf 'true\n' >"$stub/api-graphql.2"
sh "$REPO_ROOT/scripts/resolve-thread.sh" "$dir" 9001 | grep -qx 'resolve-thread: 9001 resolved'

printf '\n' >"$stub/api-graphql.1"
if sh "$REPO_ROOT/scripts/resolve-thread.sh" "$dir" 9001 2>"$SCRATCH/err"; then
	echo "expected failure when no thread matches" >&2
	exit 1
fi
grep -q "no thread starts with comment" "$SCRATCH/err"

printf 'PRRT_abc\n' >"$stub/api-graphql.1"
printf 'false\n' >"$stub/api-graphql.2"
if sh "$REPO_ROOT/scripts/resolve-thread.sh" "$dir" 9001 2>"$SCRATCH/err"; then
	echo "expected failure when the mutation does not resolve" >&2
	exit 1
fi
grep -q "did not resolve" "$SCRATCH/err"
