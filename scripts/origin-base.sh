#!/bin/sh
# Name the base branch a clone's origin points at, without the network.
# Usage: sh scripts/origin-base.sh <clone>
# Prints the branch origin/HEAD names. When the clone never recorded
# origin/HEAD, as one made with git remote add rather than git clone,
# falls back to origin/main or origin/master when exactly one of them
# exists. Exit 3 when nothing names a base.
set -eu

clone=${1:?usage: origin-base.sh <clone>}
[ -d "$clone" ] || {
	echo "origin-base: no such directory: $clone" >&2
	exit 1
}
if head=$(git -C "$clone" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
	printf '%s\n' "${head#refs/remotes/origin/}"
	exit 0
fi
found=''
for branch in main master; do
	git -C "$clone" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null && found="$found $branch"
done
set -- $found
[ $# -eq 1 ] || exit 3
printf '%s\n' "$1"
