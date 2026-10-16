#!/bin/sh
# reviewed-head: current when GitHub's head is the reviewed one, moved
# (and head_sha follows) when someone pushed since, --mark records it.
set -eu

stub="$SCRATCH/stub"
mkdir -p "$stub"
export GH_STUB_DIR="$stub"
export PATH="$REPO_ROOT/tests/stubs:$PATH"
. "$REPO_ROOT/tests/fixture-identity.sh"
dir="$SCRATCH/state"
mkdir -p "$dir"
printf 'owner %s\nrepo widgets\npr 7\nhead_sha aaa111\nreviewed_head aaa111\n' "$fixture_owner" >"$dir/meta.txt"

printf 'aaa111\n' >"$stub/pr-view"
[ "$(sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir")" = "reviewed-head: current aaa111" ]
grep -qx "pr view 7 --repo $fixture_owner/widgets --json headRefOid --jq .headRefOid" "$stub/calls.log"

printf 'bbb222\n' >"$stub/pr-view"
rc=0
out=$(sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "reviewed-head: moved aaa111 bbb222" ]
grep -qx 'head_sha bbb222' "$dir/meta.txt"
grep -qx 'reviewed_head aaa111' "$dir/meta.txt"
# Still moved until the review of the new commits is marked.
rc=0
sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir" >/dev/null || rc=$?
[ "$rc" -eq 3 ]
[ "$(sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir" --mark)" = "reviewed-head: reviewed bbb222" ]
grep -qx 'reviewed_head bbb222' "$dir/meta.txt"
[ "$(grep -c '^reviewed_head ' "$dir/meta.txt")" -eq 1 ]
[ "$(sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir")" = "reviewed-head: current bbb222" ]

# A ledger without the field compares against head_sha.
printf 'owner %s\nrepo widgets\npr 7\nhead_sha ccc333\n' "$fixture_owner" >"$dir/meta.txt"
printf 'ccc333\n' >"$stub/pr-view"
[ "$(sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir")" = "reviewed-head: current ccc333" ]

# An unreadable head is an error, never "current".
printf 'null\n' >"$stub/pr-view"
if sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir" 2>"$SCRATCH/err"; then
	echo "expected failure on an unreadable head" >&2
	exit 1
fi
grep -q "reported no head commit" "$SCRATCH/err"
if sh "$REPO_ROOT/scripts/reviewed-head.sh" "$dir" --now 2>"$SCRATCH/err"; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
