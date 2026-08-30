#!/bin/sh
# Remove the worktree and fetched context, keeping the ledger as the record.
# Usage: sh scripts/cleanup-state.sh <state-dir>
set -eu

dir=${1:?usage: cleanup-state.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "cleanup-state: no meta.txt in $dir" >&2
	exit 1
}

worktree="$dir/worktree"
if [ -d "$worktree" ]; then
	repo_root=$(sed -n 's/^repo_root //p' "$dir/meta.txt")
	if [ -n "$repo_root" ] && [ -d "$repo_root" ]; then
		git -C "$repo_root" worktree remove --force "$worktree"
	else
		rm -rf "$worktree"
	fi
fi
rm -rf "$dir/pr-context"

[ ! -d "$worktree" ] || {
	echo "cleanup-state: worktree removal left $worktree behind" >&2
	exit 1
}
echo "cleanup-state: worktree and context removed, ledger kept"
