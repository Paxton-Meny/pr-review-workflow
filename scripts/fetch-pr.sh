#!/bin/sh
# Fetch pull request context into the state directory.
# Usage: sh scripts/fetch-pr.sh <state-dir>
set -eu

dir=${1:?usage: fetch-pr.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "fetch-pr: no meta.txt in $dir, run init-state.sh first" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr" ] || {
	echo "fetch-pr: meta.txt in $dir is incomplete" >&2
	exit 1
}

ctx="$dir/pr-context"
mkdir -p "$ctx"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
err=$(mktemp "$ctx/.fetch.XXXXXX")
trap 'rm -f "$tmp" "$err"' EXIT
if ! gh pr diff "$pr" --repo "$owner/$repo" >"$tmp" 2>"$err"; then
	echo "fetch-pr: diff fetch failed for $owner/$repo#$pr (very large pull requests cannot be fetched through the API)" >&2
	sed 's/^/fetch-pr: /' "$err" >&2
	exit 1
fi
rm -f "$err"
mv "$tmp" "$ctx/diff.patch"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
gh pr view "$pr" --repo "$owner/$repo" \
	--json title,additions,deletions,changedFiles,labels \
	--jq '"title \(.title)\nadditions \(.additions)\ndeletions \(.deletions)\nchanged_files \(.changedFiles)\nlabels \([.labels[].name] | join(","))"' >"$tmp"
mv "$tmp" "$ctx/meta-full.txt"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
gh pr view "$pr" --repo "$owner/$repo" --json body --jq '.body' >"$tmp"
mv "$tmp" "$ctx/body.txt"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
gh pr view "$pr" --repo "$owner/$repo" --json files \
	--jq '.files[] | "\(.path)\t\(.additions)\t\(.deletions)"' >"$tmp"
mv "$tmp" "$ctx/files.txt"
trap - EXIT

sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/split-diff.sh" "$dir"

additions=$(sed -n 's/^additions //p' "$ctx/meta-full.txt")
deletions=$(sed -n 's/^deletions //p' "$ctx/meta-full.txt")
changed=$(sed -n 's/^changed_files //p' "$ctx/meta-full.txt")
echo "fetch-pr: $changed files, $additions additions, $deletions deletions"
