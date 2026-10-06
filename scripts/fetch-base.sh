#!/bin/sh
# Bring origin/<branch> up to date, even in a single-branch clone.
# Usage: sh scripts/fetch-base.sh <repo-root> <branch>
# Prints one line: "fetch-base: <branch> fresh" when the fetch worked,
# "stale" when it failed but an older origin/<branch> exists to read,
# "unavailable" when there is nothing to read. Exit 0 for fresh and
# stale, 3 for unavailable, 1 for bad arguments.
#
# A plain "git fetch origin <branch>" only updates FETCH_HEAD in a clone
# made with --single-branch, so the remote-tracking ref is named
# explicitly.
set -eu

root=${1:?usage: fetch-base.sh <repo-root> <branch>}
branch=${2:?usage: fetch-base.sh <repo-root> <branch>}
git check-ref-format "refs/heads/$branch" 2>/dev/null || {
	echo "fetch-base: not a branch name: $branch" >&2
	exit 1
}

if git -C "$root" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null; then
	echo "fetch-base: $branch fresh"
	exit 0
fi
if git -C "$root" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
	echo "fetch-base: $branch stale"
	exit 0
fi
echo "fetch-base: $branch unavailable"
exit 3
