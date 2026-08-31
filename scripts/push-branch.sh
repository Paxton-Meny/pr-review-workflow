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
cross_repo=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")

dest=origin
if [ "$cross_repo" = "true" ]; then
	maintainer_can_modify=$(sed -n 's/^maintainer_can_modify //p' "$dir/meta.txt")
	if [ "$maintainer_can_modify" != "true" ]; then
		echo "push-branch: the fork does not allow maintainer edits" >&2
		exit 2
	fi
	dest=$(sed -n 's/^head_repo_url //p' "$dir/meta.txt")
	[ -n "$dest" ] || {
		echo "push-branch: meta.txt records no fork url" >&2
		exit 1
	}
fi

git -C "$worktree" push --quiet "$dest" "HEAD:$head_branch"

local_sha=$(git -C "$worktree" rev-parse HEAD)
remote_sha=$(git -C "$worktree" ls-remote "$dest" "refs/heads/$head_branch" | cut -f1)
if [ "$local_sha" != "$remote_sha" ]; then
	echo "push-branch: remote is at $remote_sha, expected $local_sha" >&2
	exit 1
fi

old_head=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
tmp=$(mktemp "$dir/.meta.XXXXXX")
sed -e "s/^head_sha .*/head_sha $local_sha/" -e "/^prev_head /d" "$dir/meta.txt" >"$tmp"
printf 'prev_head %s\n' "$old_head" >>"$tmp"
mv "$tmp" "$dir/meta.txt"

echo "push-branch: $head_branch at $local_sha"
