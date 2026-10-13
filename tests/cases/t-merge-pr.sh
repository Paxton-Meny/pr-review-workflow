#!/bin/sh
# merge-pr: refuses bad states, approves or falls back, proves the merge.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"
author="${fixture_login}_author"
dir="$SCRATCH/data/state/${fixture_owner}__widgets__7"
mkdir -p "$dir"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\n' "$fixture_owner" "$author" "$fixture_login" >"$dir/meta.txt"
: | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$dir" >/dev/null
printf '0\n' >"$dir/round.txt"

printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
: >"$stub/pr-review"
: >"$stub/pr-merge"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve | grep -qx "merge-pr: $fixture_owner/widgets#7 merged"
grep -q "^pr review 7 --repo $fixture_owner/widgets --approve" "$stub/calls.log"
grep -q 'Reviewed with \[pr-review-workflow\]' "$stub/calls.log" || {
	echo "a clean run's approval is its first comment and names the plugin" >&2
	exit 1
}

rm -f "$stub"/pr-view.1.done "$stub"/pr-view.2.done "$stub/calls.log"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\n' "$fixture_owner" "$fixture_login" "$fixture_login" >"$dir/meta.txt"
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.1"
: >"$stub/pr-comment"
printf 'MERGED\n' >"$stub/pr-view.2"
printf '1\n' >"$dir/round.txt"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve >/dev/null
grep -q '^pr comment 7' "$stub/calls.log"
if grep -q 'Reviewed with' "$stub/calls.log"; then
	echo "after a posted round the approval must not name the plugin again" >&2
	exit 1
fi
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

export MERGE_PR_SETTLE_SECONDS=0
rm -f "$stub"/pr-view.*.done "$stub"/pr-view.1 "$stub"/pr-view.2
printf 'state OPEN\ndraft false\nmergeable UNKNOWN\nmerge_state CLEAN\n' >"$stub/pr-view.1"
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\n' >"$stub/pr-view.2"
: >"$stub/pr-comment"
printf 'MERGED\n' >"$stub/pr-view.3"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" >/dev/null

rm -f "$stub"/pr-view.*.done "$stub"/pr-view.3
for n in 1 2 3 4 5; do
	printf 'state OPEN\ndraft false\nmergeable UNKNOWN\nmerge_state CLEAN\n' >"$stub/pr-view.$n"
done
if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure when mergeability never settles" >&2
	exit 1
fi
grep -q "still UNKNOWN after waiting" "$SCRATCH/err"

# A pull request changing migrations never merges until a person has
# checked what the review cannot see, with or without --approve, and a
# file list too short to rule migrations out is refused the same way.
rm -f "$stub"/pr-view.* "$stub/calls.log"
status='state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\nchanged 2\nfile app/migrations/0002_add_email.py\nfile src/app.py\n'
for flag in --approve ''; do
	printf "$status" >"$stub/pr-view.1"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" $flag) || rc=$?
	[ "$rc" -eq 4 ]
	[ "$out" = "$(printf 'merge-pr: migrations changed, a person decides\nmigration app/migrations/0002_add_email.py')" ]
	if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
		echo "a refused merge must write nothing to the pull request" >&2
		exit 1
	fi
	rm -f "$stub"/pr-view.*
done

printf "$status" >"$stub/pr-view.1"
printf 'MERGED\n' >"$stub/pr-view.2"
sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve --migrations-checked | grep -qx "merge-pr: $fixture_owner/widgets#7 merged"
grep -q '^pr merge 7' "$stub/calls.log"

rm -f "$stub"/pr-view.* "$stub/calls.log"
printf 'state OPEN\ndraft false\nmergeable MERGEABLE\nmerge_state CLEAN\nchanged 150\nfile src/app.py\n' >"$stub/pr-view.1"
rc=0
out=$(sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve) || rc=$?
[ "$rc" -eq 4 ]
[ "$out" = "merge-pr: only 1 of 150 changed files listed, so migrations cannot be ruled out; a person decides" ]
if grep -qE '^pr (review|comment|merge)' "$stub/calls.log"; then
	echo "an incomplete file list must write nothing to the pull request" >&2
	exit 1
fi

if sh "$REPO_ROOT/scripts/merge-pr.sh" "$dir" --approve --checked 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
grep -q "unknown argument: --checked" "$SCRATCH/err"
