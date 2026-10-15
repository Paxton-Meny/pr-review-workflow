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

# Running the author's code: trusted authors, or an untrusted one the
# user approved for this pull request, and nobody else.
trust "$other" read true
rc=0
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" --exec) || rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "author-trust: code does not run, $other read permission" ]
trust "$other" write true
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" --exec)
[ "$out" = "author-trust: code runs, $other write permission" ]
trust "$other" none true
[ "$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" --approve)" = "author-trust: approved running $other's code for this pull request" ]
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" --exec)
[ "$out" = "author-trust: code runs, approved for $other" ]
# The approval is for running code only: the author stays untrusted to merge.
rc=0
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$dir") || rc=$?
[ "$rc" -eq 3 ]
[ "$out" = "$(printf 'author-trust: untrusted %s none permission\nauthor-trust: you approved running this author'"'"'s code here' "$other")" ]
# An approval names its author: a different author is not covered.
sed -i "s/^author .*/author ${other}2/" "$dir/meta.txt"
rc=0
sh "$REPO_ROOT/scripts/author-trust.sh" "$dir" --exec >/dev/null || rc=$?
[ "$rc" -eq 3 ]
rm -f "$dir/exec-approved.txt"
# With a check command configured, the untrusted line says it will not run.
data="$SCRATCH/data"
run="$data/state/${fixture_owner}__widgets__7"
mkdir -p "$run"
printf 'owner %s\nrepo widgets\npr 7\nauthor %s\nself_login %s\nauthor_permission read\ncross_repo true\n' \
	"$fixture_owner" "$other" "$fixture_login" >"$run/meta.txt"
printf 'check_command make check\n' | sh "$REPO_ROOT/scripts/resolve-settings.sh" "$run" >/dev/null
rc=0
out=$(sh "$REPO_ROOT/scripts/author-trust.sh" "$run") || rc=$?
[ "$rc" -eq 3 ]
printf '%s\n' "$out" | grep -qx 'author-trust: the check command and contracts will not run on this code unless you approve it'
if sh "$REPO_ROOT/scripts/author-trust.sh" "$run" --merge 2>/dev/null; then
	echo "expected refusal of an unknown argument" >&2
	exit 1
fi
