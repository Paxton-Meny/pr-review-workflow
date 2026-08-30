#!/bin/sh
# Push the worktree head to the pull request branch and prove it arrived.
# Usage: sh scripts/push-branch.sh <state-dir>
set -eu

dir=${1:?usage: push-branch.sh <state-dir>}
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "push-branch: no worktree in $dir, run checkout-pr.sh first" >&2
	exit 1
}
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")

git -C "$worktree" push --quiet origin "HEAD:$head_branch"

local_sha=$(git -C "$worktree" rev-parse HEAD)
remote_sha=$(git -C "$worktree" ls-remote origin "refs/heads/$head_branch" | cut -f1)
if [ "$local_sha" != "$remote_sha" ]; then
	echo "push-branch: remote is at $remote_sha, expected $local_sha" >&2
	exit 1
fi

tmp=$(mktemp "$dir/.meta.XXXXXX")
sed "s/^head_sha .*/head_sha $local_sha/" "$dir/meta.txt" >"$tmp"
mv "$tmp" "$dir/meta.txt"

echo "push-branch: $head_branch at $local_sha"
