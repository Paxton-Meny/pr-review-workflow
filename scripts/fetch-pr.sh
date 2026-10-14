#!/bin/sh
# Fetch pull request context into the state directory.
# Usage: sh scripts/fetch-pr.sh <state-dir>
# The diff comes from the API; when the API refuses it (GitHub serves
# no diff for very large pull requests), local-diff.sh builds the same
# diff from the clone, and the file list comes from that diff too, since
# the API's file list is capped as well. meta-full.txt records which:
# "diff_source api" or "diff_source clone".
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
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
err=$(mktemp "$ctx/.fetch.XXXXXX")
trap 'rm -f "$tmp" "$err"' EXIT
diff_source=api
if gh pr diff "$pr" --repo "$owner/$repo" >"$tmp" 2>"$err"; then
	mv "$tmp" "$ctx/diff.patch"
else
	echo "fetch-pr: the API refused the diff for $owner/$repo#$pr (very large pull requests cannot be fetched through it), building it from the clone" >&2
	sed 's/^/fetch-pr: /' "$err" >&2
	rm -f "$tmp"
	rc=0
	sh "$here/local-diff.sh" "$dir" || rc=$?
	if [ "$rc" -ne 0 ]; then
		echo "fetch-pr: diff fetch failed for $owner/$repo#$pr: the API refused it and the clone could not supply it" >&2
		exit "$rc"
	fi
	diff_source=clone
fi
rm -f "$err"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
gh pr view "$pr" --repo "$owner/$repo" \
	--json title,additions,deletions,changedFiles,labels,commits \
	--jq '"title \(.title)\nadditions \(.additions)\ndeletions \(.deletions)\nchanged_files \(.changedFiles)\nlabels \([.labels[].name] | join(","))\ncommits \(.commits | length)"' >"$tmp"
printf 'diff_source %s\n' "$diff_source" >>"$tmp"
mv "$tmp" "$ctx/meta-full.txt"

tmp=$(mktemp "$ctx/.fetch.XXXXXX")
gh pr view "$pr" --repo "$owner/$repo" --json body --jq '.body' >"$tmp"
mv "$tmp" "$ctx/body.txt"

if [ "$diff_source" = api ]; then
	tmp=$(mktemp "$ctx/.fetch.XXXXXX")
	gh pr view "$pr" --repo "$owner/$repo" --json files \
		--jq '.files[] | "\(.path)\t\(.additions)\t\(.deletions)"' >"$tmp"
	mv "$tmp" "$ctx/files.txt"
fi
trap - EXIT

sh "$here/split-diff.sh" "$dir"

additions=$(sed -n 's/^additions //p' "$ctx/meta-full.txt")
deletions=$(sed -n 's/^deletions //p' "$ctx/meta-full.txt")
changed=$(sed -n 's/^changed_files //p' "$ctx/meta-full.txt")
if [ "$diff_source" = clone ]; then
	echo "fetch-pr: $changed files, $additions additions, $deletions deletions, diff from the clone"
else
	echo "fetch-pr: $changed files, $additions additions, $deletions deletions"
fi
