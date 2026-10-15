#!/bin/sh
# author-trust: own pull requests and pushers are trusted, a fork whose
# author GitHub cannot place is not, and a missing author never is.
set -eu

. "$REPO_ROOT/tests/fixture-identity.sh"
dir="$SCRATCH/state"
mkdir -p "$dir"
trust() {
	# trust <author> <permission> <cross_repo>: prints the line, keeps the exit
	printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nauthor_permission %s\ncross_repo %s\n' \
		"$fixture_owner" "$1" "$fixture_login" "$2" "$3" >"$dir/meta.txt"
	rc=0
	out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir") || rc=$?
}
other="${fixture_login}_author"

trust "$fixture_login" read true
[ "$rc" -eq 0 ] && [ "$out" = "author-trust: trusted $fixture_login own pull request" ]
for p in write maintain admin; do
	trust "$other" "$p" true
	[ "$rc" -eq 0 ] && [ "$out" = "author-trust: trusted $other $p permission" ]
done
for p in read triage none; do
	trust "$other" "$p" false
	[ "$rc" -eq 3 ] && [ "$out" = "author-trust: untrusted $other $p permission" ]
done
trust "$other" unknown false
[ "$rc" -eq 0 ] && [ "$out" = "author-trust: trusted $other branch in the repository, permission unknown" ]
trust "$other" unknown true
[ "$rc" -eq 3 ] && [ "$out" = "author-trust: untrusted $other fork, permission unknown" ]
# A ledger missing the fields is a fork whose author nobody placed.
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\n' "$fixture_owner" "$other" >"$dir/meta.txt"
rc=0
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "author-trust: untrusted $other fork, permission unknown" ]
printf 'owner %s\nrepo widgets\npr 7\nself_login %s\n' "$fixture_owner" "$fixture_login" >"$dir/meta.txt"
rc=0
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "author-trust: untrusted unknown no author recorded" ]
rm -f "$dir/meta.txt"
if sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" 2>/dev/null; then
	echo "expected failure without meta.txt" >&2
	exit 1
fi
