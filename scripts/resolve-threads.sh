#!/bin/sh
# Resolve the review thread of every verified finding.
# Usage: sh scripts/resolve-threads.sh <state-dir>
# The review session runs it after each verification, so a thread closes
# on the ledger's verdict and no agent needs the right to close one. The
# pull request's threads are listed once; a verified finding whose thread
# is already resolved is left alone, so running it again is safe. A
# thread that cannot be found or does not resolve is named on stderr and
# the rest still resolve; exit 3 then, with the same count line.
set -eu

dir=${1:?usage: resolve-threads.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "resolve-threads: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

wanted=$(mktemp "$dir/.threads.XXXXXX")
threads=$(mktemp "$dir/.threads.XXXXXX")
trap 'rm -f "$wanted" "$threads"' EXIT
for record in "$dir/findings"/F*; do
	[ -f "$record" ] || continue
	[ "$(sed -n '/^---$/q; s/^status: //p' "$record")" = verified ] || continue
	comment_id=$(sed -n '/^---$/q; s/^comment_id: //p' "$record")
	case "$comment_id" in
	'' | *[!0-9]*) continue ;;
	esac
	printf '%s %s\n' "${record##*/}" "$comment_id" >>"$wanted"
done
[ -s "$wanted" ] || {
	echo "resolve-threads: no verified finding has a thread"
	exit 0
}

PAGE_MAX=10
page=0
cursor=''
while [ "$page" -lt "$PAGE_MAX" ]; do
	page=$((page + 1))
	after=''
	[ -n "$cursor" ] && after=", after: \"$cursor\""
	result=$(gh api graphql \
		-f query="query { repository(owner: \"$owner\", name: \"$repo\") { pullRequest(number: $pr) { reviewThreads(first: 100$after) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }" \
		--jq '.data.repository.pullRequest.reviewThreads | "page \(.pageInfo.hasNextPage) \(.pageInfo.endCursor)", (.nodes[] | "thread \(.id) \(.isResolved) \(.comments.nodes[0].databaseId)")')
	printf '%s\n' "$result" | sed -n 's/^thread //p' >>"$threads"
	has_next=$(printf '%s\n' "$result" | sed -n 's/^page \([a-z]*\) .*/\1/p')
	cursor=$(printf '%s\n' "$result" | sed -n 's/^page [a-z]* //p')
	[ "$has_next" = "true" ] || break
done

resolved=0 already=0 failed=0
while read -r id comment_id; do
	set -- $(awk -v c="$comment_id" '$3 == c { print $1, $2; exit }' "$threads")
	thread_id=${1:-}
	case "$thread_id" in
	'' | *[!A-Za-z0-9_=-]*)
		echo "resolve-threads: $id: no thread starts with comment $comment_id" >&2
		failed=$((failed + 1))
		continue
		;;
	esac
	if [ "${2:-}" = true ]; then
		already=$((already + 1))
		continue
	fi
	answer=$(gh api graphql \
		-f query="mutation { resolveReviewThread(input: {threadId: \"$thread_id\"}) { thread { isResolved } } }" \
		--jq '.data.resolveReviewThread.thread.isResolved') || answer=''
	if [ "$answer" = "true" ]; then
		resolved=$((resolved + 1))
	else
		echo "resolve-threads: $id: the thread of comment $comment_id did not resolve" >&2
		failed=$((failed + 1))
	fi
done <"$wanted"

echo "resolve-threads: resolved $resolved, already resolved $already, failed $failed"
[ "$failed" -eq 0 ] || exit 3
