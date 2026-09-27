#!/bin/sh
# Ensure a detached worktree holding the pull request head, from this clone.
# Usage: sh scripts/checkout-pr.sh <state-dir>
set -eu

dir=${1:?usage: checkout-pr.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "checkout-pr: no meta.txt in $dir, run init-state.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
cross_repo=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")
maintainer_can_modify=$(sed -n 's/^maintainer_can_modify //p' "$dir/meta.txt")
head_repo_url=$(sed -n 's/^head_repo_url //p' "$dir/meta.txt")

if [ "$cross_repo" = "true" ] && [ -z "$head_repo_url" ]; then
	echo "checkout-pr: the fork this pull request comes from is gone" >&2
	exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "checkout-pr: run from inside a clone of $owner/$repo" >&2
	exit 1
}
url=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || {
	echo "checkout-pr: the clone at $repo_root has no origin remote" >&2
	exit 1
}
case "$url" in
*[/:]"$owner/$repo" | *[/:]"$owner/$repo/" | *[/:]"$owner/$repo.git" | *[/:]"$owner/$repo.git/") ;;
*)
	echo "checkout-pr: origin of $repo_root is $url, not $owner/$repo" >&2
	exit 1
	;;
esac

if [ "$cross_repo" = "true" ]; then
	case "$url" in
	git@github.com:*)
		case "$head_repo_url" in
		https://github.com/*)
			head_repo_url="git@github.com:${head_repo_url#https://github.com/}"
			tmp=$(mktemp "$dir/.meta.XXXXXX")
			sed "s|^head_repo_url .*|head_repo_url $head_repo_url|" "$dir/meta.txt" >"$tmp"
			mv "$tmp" "$dir/meta.txt"
			;;
		esac
		;;
	esac
	git -C "$repo_root" fetch --quiet "$head_repo_url" "$head_branch"
else
	git -C "$repo_root" fetch --quiet origin "$head_branch"
fi

worktree="$dir/worktree"
if [ -d "$worktree" ]; then
	actual=$(git -C "$worktree" rev-parse HEAD)
	if [ "$actual" != "$head_sha" ]; then
		if git -C "$worktree" merge-base --is-ancestor "$head_sha" "$actual"; then
			echo "checkout-pr: keeping unpushed commits ahead of $head_sha" >&2
		else
			git -C "$worktree" checkout --quiet --detach "$head_sha" 2>/dev/null ||
				git -C "$worktree" reset --hard --quiet "$head_sha"
		fi
	fi
else
	git -C "$repo_root" worktree add --quiet --detach "$worktree" "$head_sha"
fi

actual=$(git -C "$worktree" rev-parse HEAD)
if [ "$actual" != "$head_sha" ] &&
	! git -C "$worktree" merge-base --is-ancestor "$head_sha" "$actual"; then
	echo "checkout-pr: worktree is at $actual, expected $head_sha or a descendant" >&2
	exit 1
fi

grep -q '^repo_root ' "$dir/meta.txt" || {
	tmp=$(mktemp "$dir/.meta.XXXXXX")
	{ cat "$dir/meta.txt"; printf 'repo_root %s\n' "$repo_root"; } >"$tmp"
	mv "$tmp" "$dir/meta.txt"
}

printf '%s\n' "$worktree"
if [ "$cross_repo" = "true" ] && [ "$maintainer_can_modify" != "true" ]; then
	echo "mode review-only"
else
	echo "mode read-write"
fi

base_branch=$(sed -n 's/^base_branch //p' "$dir/meta.txt")
ctx="$dir/pr-context"
if [ -n "$base_branch" ] && [ -d "$ctx" ]; then
	git -C "$repo_root" fetch --quiet origin "$base_branch"
	rm -f "$ctx/conventions.txt"
	if git -C "$repo_root" show "origin/$base_branch:CLAUDE.md" >/dev/null 2>&1; then
		tmp=$(mktemp "$ctx/.conv.XXXXXX")
		git -C "$repo_root" show "origin/$base_branch:CLAUDE.md" |
			awk '/<!-- review-conventions:begin -->/ { take = 1; next }
			/<!-- review-conventions:end -->/ { take = 0 }
			take { print }' >"$tmp"
		if [ -s "$tmp" ]; then
			mv "$tmp" "$ctx/conventions.txt"
			echo "conventions $(grep -c . "$ctx/conventions.txt") lines"
		else
			rm -f "$tmp"
		fi
	fi
fi
