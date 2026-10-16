#!/bin/sh
# Push the worktree head to the pull request branch and prove it arrived.
# Usage: sh scripts/push-branch.sh <state-dir> [--force-with-lease]
# --force-with-lease rewrites the branch, leased on the head meta.txt
# recorded, so a push the run never saw refuses it; only sync-branch.sh
# passes it, after a rebase onto the base. Each push is journaled in
# steps.txt as "push <sha>" for next-step.sh. Exit 3 means the worktree
# holds nothing new to push, or, on a plain push, lacks the commit an
# addressed finding records.
set -eu

dir=${1:?usage: push-branch.sh <state-dir> [--force-with-lease]}
lease=
case "${2:-}" in
'') ;;
--force-with-lease) lease=1 ;;
*)
	echo "push-branch: unknown argument: $2" >&2
	exit 1
	;;
esac
worktree="$dir/worktree"
[ -f "$dir/meta.txt" ] && [ -d "$worktree" ] || {
	echo "push-branch: no worktree in $dir, run checkout-pr.sh first" >&2
	exit 1
}
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")
old_head=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
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

local_sha=$(git -C "$worktree" rev-parse HEAD)
if [ "$local_sha" = "$old_head" ]; then
	echo "push-branch: nothing to push: $worktree is still at $old_head, the head the run last recorded; commits made anywhere else never reach the pull request" >&2
	exit 3
fi
if [ -z "$lease" ]; then
	for record in "$dir/findings"/F*; do
		[ -f "$record" ] || continue
		[ "$(sed -n '/^---$/q; s/^status: //p' "$record")" = addressed ] || continue
		commit=$(sed -n '/^---$/q; s/^commit: //p' "$record")
		[ -z "$commit" ] && continue
		git -C "$worktree" merge-base --is-ancestor "$commit" "$local_sha" 2>/dev/null && continue
		echo "push-branch: ${record##*/} records commit $commit, which $worktree at $local_sha does not contain" >&2
		exit 3
	done
fi

if [ -n "$lease" ]; then
	git -C "$worktree" push --quiet "--force-with-lease=refs/heads/$head_branch:$old_head" "$dest" "HEAD:$head_branch"
else
	git -C "$worktree" push --quiet "$dest" "HEAD:$head_branch"
fi

remote_sha=$(git -C "$worktree" ls-remote "$dest" "refs/heads/$head_branch" | cut -f1)
if [ "$local_sha" != "$remote_sha" ]; then
	echo "push-branch: remote is at $remote_sha, expected $local_sha" >&2
	exit 1
fi

# The run's own push is the head the review covers from here on: the
# loop verifies and re-reviews what it pushed. That holds only over a head
# the review covered; commits that arrived from outside and are not reviewed
# yet (reviewed_head behind head_sha, or an arrival pending) stay unreviewed.
reviewed=$(sed -n 's/^reviewed_head //p' "$dir/meta.txt")
arrived=$(sed -n 's/^arrived_base //p' "$dir/meta.txt")
if [ -z "$reviewed" ] || { [ "$reviewed" = "$old_head" ] && [ -z "$arrived" ]; }; then
	reviewed=$local_sha
fi
tmp=$(mktemp "$dir/.meta.XXXXXX")
sed -e "s/^head_sha .*/head_sha $local_sha/" -e "/^prev_head /d" -e "/^reviewed_head /d" "$dir/meta.txt" >"$tmp"
printf 'prev_head %s\nreviewed_head %s\n' "$old_head" "$reviewed" >>"$tmp"
mv "$tmp" "$dir/meta.txt"
printf 'push %s\n' "$local_sha" >>"$dir/steps.txt"

echo "push-branch: $head_branch at $local_sha"
