#!/bin/sh
# Ensure a detached worktree holding the pull request head, from this clone.
# Usage: sh scripts/checkout-pr.sh <state-dir> [--reviewed | --accept <sha>]
# A fork's head comes from GitHub's refs/pull/<n>/head on origin, as
# local-diff.sh fetches it, and only then from the fork's branch; every
# branch fetch puts -- before the remote, so a name read from GitHub
# cannot act as an option.
# Exit 3: the branch gained commits pushed outside this run since
# head_sha; worktree, head_sha, and prev_head moved to them, and the line
# "checkout-pr: advanced <base> <new>" names the oldest head whose
# successors nobody reviewed yet and the current one. The base is kept in
# meta.txt as arrived_base, so exit 3 repeats on every call, across
# further outside pushes, until `--reviewed` clears it and records
# head_sha as reviewed_head, the head merge-pr.sh insists the review
# covered, as reviewed-head.sh --mark does; it marks only while an
# arrival is pending; round-diff.sh
# <dir> --all <base> lists every file of the whole range. `--accept <sha>`
# adopts the branch head <sha> as the new head_sha after a person looked
# at a branch that went back or was rewritten. Exit 4: refused, changing nothing, because the branch went
# back past head_sha or diverged from it, or the worktree holds commits
# the branch lacks while the branch gained others.
set -eu

dir=${1:?usage: checkout-pr.sh <state-dir> [--reviewed | --accept <sha>]}
mode_arg=${2:-}
accept=''
case "$mode_arg" in
'' | --reviewed) ;;
--accept)
	accept=${3:?usage: checkout-pr.sh <state-dir> --accept <sha>}
	;;
*)
	echo "checkout-pr: unknown argument: $mode_arg" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "checkout-pr: no meta.txt in $dir, run init-state.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
head_branch=$(sed -n 's/^head_branch //p' "$dir/meta.txt")
head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
cross_repo=$(sed -n 's/^cross_repo //p' "$dir/meta.txt")
maintainer_can_modify=$(sed -n 's/^maintainer_can_modify //p' "$dir/meta.txt")
head_repo_url=$(sed -n 's/^head_repo_url //p' "$dir/meta.txt")
arrived_base=$(sed -n 's/^arrived_base //p' "$dir/meta.txt")
if [ "$mode_arg" = "--reviewed" ]; then
	tmp=$(mktemp "$dir/.meta.XXXXXX")
	case "$head_sha" in
	'' | *[!0-9a-f]*) mark='' ;;
	*) mark=$head_sha ;;
	esac
	if [ -n "$mark" ] && [ -n "$arrived_base" ]; then
		sed -e "/^arrived_base /d" -e "/^reviewed_head /d" "$dir/meta.txt" >"$tmp"
		printf 'reviewed_head %s\n' "$mark" >>"$tmp"
	else
		sed "/^arrived_base /d" "$dir/meta.txt" >"$tmp"
	fi
	mv "$tmp" "$dir/meta.txt"
	arrived_base=''
fi
case "$head_sha" in
'' | *[!0-9a-f]*)
	echo "checkout-pr: head_sha in meta.txt is not a commit id: $head_sha" >&2
	exit 1
	;;
esac

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
	src=$head_repo_url
else
	src=origin
fi
# A fork's head is read from GitHub's pull request ref on origin first, so
# the fork is not asked for a branch while origin already has the head; the
# fork's branch answers only when that ref is missing.
remote_head=''
if [ "$cross_repo" = "true" ]; then
	case "$pr" in
	'' | *[!0-9]*) ;;
	*)
		refs=$(git -C "$repo_root" ls-remote origin "refs/pull/$pr/head")
		remote_head=$(printf '%s\n' "$refs" | awk -v ref="refs/pull/$pr/head" '$2 == ref { print $1 }')
		;;
	esac
fi
if [ -z "$remote_head" ]; then
	refs=$(git -C "$repo_root" ls-remote "$src" "refs/heads/$head_branch")
	remote_head=$(printf '%s\n' "$refs" | awk -v ref="refs/heads/$head_branch" '$2 == ref { print $1 }')
fi
case "$remote_head" in
'' | *[!0-9a-f]*)
	echo "checkout-pr: $head_branch is not on $src" >&2
	exit 1
	;;
esac
# The pull request ref on origin first, as local-diff.sh fetches it, then
# the branch; every branch fetch puts -- before the remote.
case "$pr" in
'' | *[!0-9]*) ;;
*) git -C "$repo_root" fetch --quiet origin "refs/pull/$pr/head" 2>/dev/null || true ;;
esac
git -C "$repo_root" cat-file -e "$remote_head^{commit}" 2>/dev/null ||
	git -C "$repo_root" fetch --quiet -- "$src" "$head_branch"
git -C "$repo_root" cat-file -e "$remote_head^{commit}" 2>/dev/null || {
	echo "checkout-pr: $head_branch moved while it was fetched, run again" >&2
	exit 1
}

refuse() {
	echo "checkout-pr: refusing, $1" >&2
	echo "checkout-pr: after looking at $head_branch, run: sh checkout-pr.sh $dir --accept $remote_head" >&2
	echo "checkout-pr: that adopts $remote_head as the head the run last saw; or delete $dir to start over" >&2
	exit 4
}
is_ancestor() { git -C "$repo_root" merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

if [ -n "$accept" ]; then
	accepted=$(git -C "$repo_root" rev-parse --verify --quiet "$accept^{commit}") || accepted=''
	[ -n "$accepted" ] && [ "$accepted" = "$remote_head" ] || {
		echo "checkout-pr: $accept is not the head of $head_branch ($remote_head)" >&2
		exit 1
	}
	tmp=$(mktemp "$dir/.meta.XXXXXX")
	sed -e "s/^head_sha .*/head_sha $accepted/" -e "/^prev_head /d" -e "/^arrived_base /d" "$dir/meta.txt" >"$tmp"
	printf 'prev_head %s\n' "$accepted" >>"$tmp"
	mv "$tmp" "$dir/meta.txt"
	head_sha=$accepted
	arrived_base=''
fi

target=$head_sha
if [ "$remote_head" != "$head_sha" ]; then
	if is_ancestor "$head_sha" "$remote_head"; then
		target=$remote_head
	elif is_ancestor "$remote_head" "$head_sha"; then
		refuse "$head_branch is at $remote_head, behind $head_sha the run last saw"
	else
		refuse "$head_branch at $remote_head has diverged from $head_sha the run last saw"
	fi
fi

worktree="$dir/worktree"
if [ -d "$worktree" ]; then
	actual=$(git -C "$worktree" rev-parse HEAD)
	if [ "$actual" != "$target" ]; then
		if is_ancestor "$target" "$actual"; then
			echo "checkout-pr: keeping unpushed commits ahead of $target" >&2
		elif [ "$target" != "$head_sha" ] && ! is_ancestor "$actual" "$target"; then
			refuse "the worktree at $actual has diverged from $head_branch at $target: commits it lacks were pushed there"
		else
			git -C "$worktree" checkout --quiet --detach "$target" 2>/dev/null ||
				git -C "$worktree" reset --hard --quiet "$target"
		fi
	fi
else
	git -C "$repo_root" worktree add --quiet --detach "$worktree" "$target"
fi

actual=$(git -C "$worktree" rev-parse HEAD)
if [ "$actual" != "$target" ] && ! is_ancestor "$target" "$actual"; then
	echo "checkout-pr: worktree is at $actual, expected $target or a descendant" >&2
	exit 1
fi

if [ "$target" != "$head_sha" ]; then
	tmp=$(mktemp "$dir/.meta.XXXXXX")
	[ -n "$arrived_base" ] || arrived_base=$head_sha
	sed -e "s/^head_sha .*/head_sha $target/" -e "/^prev_head /d" -e "/^arrived_base /d" "$dir/meta.txt" >"$tmp"
	printf 'prev_head %s\narrived_base %s\n' "$head_sha" "$arrived_base" >>"$tmp"
	mv "$tmp" "$dir/meta.txt"
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
	sh "$(dirname "$0")/fetch-base.sh" "$repo_root" "$base_branch" >/dev/null || true
	# The base as the review starts, recorded once: the merge gate later
	# compares what landed after this point against the reviewed hunks.
	# A resumed run keeps the original snapshot.
	if ! grep -q '^base_sha ' "$dir/meta.txt" &&
		base_sha=$(git -C "$repo_root" rev-parse --verify --quiet "refs/remotes/origin/$base_branch"); then
		tmp=$(mktemp "$dir/.meta.XXXXXX")
		{ cat "$dir/meta.txt"; printf 'base_sha %s\n' "$base_sha"; } >"$tmp"
		mv "$tmp" "$dir/meta.txt"
	fi
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

if [ -n "$arrived_base" ]; then
	echo "checkout-pr: advanced $arrived_base $target"
	exit 3
fi
