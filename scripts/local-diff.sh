#!/bin/sh
# Build the pull request diff from the clone when the API will not serve it.
# Usage: sh scripts/local-diff.sh <state-dir>
# Writes pr-context/diff.patch and pr-context/files.txt in the shapes
# fetch-pr.sh writes from the API: the three-dot diff GitHub shows (merge
# base of the base branch and the head, to the head), with a/ b/ prefixes,
# three context lines, rename detection, and unquoted paths, whatever the
# user's git configuration says; and one "path<TAB>additions<TAB>deletions"
# line per file, binary files counted as 0 and 0.
# The head commit is fetched when the clone lacks it: GitHub's
# refs/pull/<n>/head first, which outlives a deleted fork, then the head
# branch as checkout-pr.sh does. Prints one line on success. Exit 1 when
# the clone cannot supply the diff, 2 when the fork is gone and the pull
# request ref is unavailable.
set -eu

dir=${1:?usage: local-diff.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "local-diff: no meta.txt in $dir, run init-state.sh first" >&2
	exit 1
}
meta() { sed -n "s/^$1 //p" "$dir/meta.txt"; }
owner=$(meta owner)
repo=$(meta repo)
pr=$(meta pr)
head_sha=$(meta head_sha)
head_branch=$(meta head_branch)
base_branch=$(meta base_branch)
cross_repo=$(meta cross_repo)
head_repo_url=$(meta head_repo_url)
repo_root=$(meta repo_root)
[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr" ] && [ -n "$head_sha" ] && [ -n "$base_branch" ] || {
	echo "local-diff: meta.txt in $dir lacks the head commit or base branch" >&2
	exit 1
}
case "$head_sha" in
*[!0-9a-f]* | '')
	echo "local-diff: head_sha in meta.txt is not a commit id: $head_sha" >&2
	exit 1
	;;
esac
git check-ref-format "refs/heads/$base_branch" 2>/dev/null || {
	echo "local-diff: not a branch name: $base_branch" >&2
	exit 1
}

[ -n "$repo_root" ] && [ -d "$repo_root" ] ||
	repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "local-diff: run from inside a clone of $owner/$repo" >&2
	exit 1
}
url=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || {
	echo "local-diff: the clone at $repo_root has no origin remote" >&2
	exit 1
}
case "$url" in
*[/:]"$owner/$repo" | *[/:]"$owner/$repo/" | *[/:]"$owner/$repo.git" | *[/:]"$owner/$repo.git/") ;;
*)
	echo "local-diff: origin of $repo_root is $url, not $owner/$repo" >&2
	exit 1
	;;
esac

have_head() { git -C "$repo_root" cat-file -e "$head_sha^{commit}" 2>/dev/null; }
if ! have_head; then
	git -C "$repo_root" fetch --quiet origin "refs/pull/$pr/head" 2>/dev/null || true
fi
if ! have_head; then
	if [ "$cross_repo" = "true" ]; then
		[ -n "$head_repo_url" ] || {
			echo "local-diff: the fork this pull request comes from is gone and origin has no refs/pull/$pr/head" >&2
			exit 2
		}
		git -C "$repo_root" fetch --quiet -- "$head_repo_url" "$head_branch" 2>/dev/null || true
	elif [ -n "$head_branch" ]; then
		git -C "$repo_root" fetch --quiet -- origin "$head_branch" 2>/dev/null || true
	fi
fi
have_head || {
	echo "local-diff: head commit $head_sha is not in $repo_root and could not be fetched" >&2
	exit 1
}

base_line=$(sh "$(dirname -- "$0")/fetch-base.sh" "$repo_root" "$base_branch") || {
	echo "local-diff: base branch $base_branch is not in $repo_root and could not be fetched" >&2
	exit 1
}
merge_base=$(git -C "$repo_root" merge-base "origin/$base_branch" "$head_sha" 2>/dev/null) || {
	echo "local-diff: $head_sha and origin/$base_branch share no history" >&2
	exit 1
}

ctx="$dir/pr-context"
mkdir -p "$ctx"
patch=$(mktemp "$ctx/.local.XXXXXX")
files=$(mktemp "$ctx/.local.XXXXXX")
trap 'rm -f "$patch" "$files"' EXIT
git_diff() {
	git -C "$repo_root" \
		-c core.quotePath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false \
		-c diff.renames=true -c diff.context=3 -c diff.interHunkContext=0 \
		-c diff.suppressBlankEmpty=false \
		diff --no-color --no-ext-diff --no-textconv --find-renames --ignore-submodules=none \
		"$@" "$merge_base" "$head_sha"
}
git_diff --patch >"$patch"
git_diff --numstat | awk -F '\t' '
{
	a = ($1 == "-") ? 0 : $1
	d = ($2 == "-") ? 0 : $2
	path = $3
	# A rename arrives as "old => new" or "dir/{old => new}/rest": keep the new name.
	if (path ~ /\{.* => .*\}/) { sub(/\{[^{]* => /, "", path); sub(/\}/, "", path); sub(/\/\//, "/", path); sub(/^\//, "", path) }
	else if (path ~ / => /) sub(/.* => /, "", path)
	printf "%s\t%s\t%s\n", path, a, d
}' >"$files"
mv "$patch" "$ctx/diff.patch"
mv "$files" "$ctx/files.txt"
trap - EXIT

count=$(grep -c . "$ctx/files.txt" || true)
short_base=$(git -C "$repo_root" rev-parse --short "$merge_base")
short_head=$(git -C "$repo_root" rev-parse --short "$head_sha")
echo "local-diff: $count files from the clone, $base_branch ${base_line#fetch-base: $base_branch } at $short_base to $short_head"
