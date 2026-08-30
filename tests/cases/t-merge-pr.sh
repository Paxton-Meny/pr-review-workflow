#!/bin/sh
# merge-pr: refuses bad states, approves or falls back, proves the merge.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner acme\nrepo widgets\npr 7\nauthor octocat\nself_login reviewer\n' >"$dir/meta.txt"

printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
: >"$stub/pr-review"
: >"$stub/pr-merge"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve | grep -qx 'merge-pr: acme/widgets#7 merged'
grep -q '^pr review 7 --repo acme/widgets --approve' "$stub/calls.log"

rm -f "$stub"/pr-view.1.done "$stub"/pr-view.2.done "$stub/calls.log"
printf 'owner acme\nrepo widgets\npr 7\nauthor reviewer\nself_login reviewer\n' >"$dir/meta.txt"
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
: >"$stub/pr-comment"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve >/dev/null
grep -q '^pr comment 7' "$stub/calls.log"
if grep -q '^pr review' "$stub/calls.log"; then
	echo "own pull request must not be approved" >&2
	exit 1
fi

rm -f "$stub"/pr-view.1.done "$stub"/pr-view.2.done
printf 'state OPEN\ndraft false\nmergeable CONFLICTING\nmerge_state DIRTY\n' >"$stub/pr-view.1"
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected refusal of a conflicting pull request" >&2
	exit 1
fi
grep -q "not mergeable: CONFLICTING" "$SCRATCH/err"

rm -f "$stub"/pr-view.1.done
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
printf 'OPEN\n' >"$stub/pr-view.2"
rc=0
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err" || rc=$?
[ "$rc" -eq 2 ]
grep -q "reported success but the pull request is OPEN" "$SCRATCH/err"
