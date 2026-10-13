#!/bin/sh
# origin-base: origin/HEAD when recorded, else the one of origin/main or
# origin/master that exists, else exit 3; never the network.
set -eu

repo="$SCRATCH/repo"
git init --quiet "$repo"
git -C "$repo" config user.name tester
git -C "$repo" config user.email tester@example.invalid
git -C "$repo" commit --quiet --allow-empty -m root
sha=$(git -C "$repo" rev-parse HEAD)
base() { sh "$REPO_ROOT/scripts/origin-base.sh" "$@"; }

rc=0
base "$repo" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ]

git -C "$repo" update-ref refs/remotes/origin/main "$sha"
[ "$(base "$repo")" = main ]

git -C "$repo" update-ref refs/remotes/origin/master "$sha"
rc=0
base "$repo" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ]

git -C "$repo" update-ref -d refs/remotes/origin/main
[ "$(base "$repo")" = master ]

# A recorded origin/HEAD wins over both, wherever it points.
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
[ "$(base "$repo")" = trunk ]

if base 2>/dev/null; then
	echo "expected refusal without a clone argument" >&2
	exit 1
fi
if base "$SCRATCH/nowhere" 2>/dev/null; then
	echo "expected refusal of a missing directory" >&2
	exit 1
fi
