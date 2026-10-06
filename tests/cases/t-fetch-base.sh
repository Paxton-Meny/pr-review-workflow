#!/bin/sh
# fetch-base: updates origin/<branch> even in a single-branch clone, and
# reports stale or unavailable when the remote cannot be reached.
set -eu

remote="$SCRATCH/remote.git"
git init --quiet --bare "$remote"
seed="$SCRATCH/seed"
git clone --quiet "$remote" "$seed" 2>/dev/null
git -C "$seed" config user.name tester
git -C "$seed" config user.email tester@example.invalid
printf 'one\n' >"$seed/a"
git -C "$seed" add a
git -C "$seed" commit --quiet -m one
git -C "$seed" push --quiet origin HEAD:main
git -C "$seed" push --quiet origin HEAD:release

clone="$SCRATCH/clone"
git clone --quiet --single-branch --branch main "$remote" "$clone" 2>/dev/null
if git -C "$clone" rev-parse --verify --quiet refs/remotes/origin/release >/dev/null; then
	echo "a single-branch clone should not know origin/release yet" >&2
	exit 1
fi

[ "$(sh "$REPO_ROOT/scripts/fetch-base.sh" "$clone" release)" = "fetch-base: release fresh" ]
git -C "$clone" rev-parse --verify --quiet refs/remotes/origin/release >/dev/null

mv "$remote" "$remote.gone"
[ "$(sh "$REPO_ROOT/scripts/fetch-base.sh" "$clone" release)" = "fetch-base: release stale" ]
if sh "$REPO_ROOT/scripts/fetch-base.sh" "$clone" missing >"$SCRATCH/out"; then
	echo "expected exit 3 for a branch never seen" >&2
	exit 1
fi
[ "$(cat "$SCRATCH/out")" = "fetch-base: missing unavailable" ]

if sh "$REPO_ROOT/scripts/fetch-base.sh" "$clone" 'bad..name' 2>"$SCRATCH/err"; then
	echo "expected refusal of a malformed branch name" >&2
	exit 1
fi
grep -q "not a branch name" "$SCRATCH/err"
