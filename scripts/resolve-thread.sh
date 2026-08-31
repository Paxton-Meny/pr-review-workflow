#!/bin/sh
# Resolve the review thread that starts with the given comment.
# Usage: sh scripts/resolve-thread.sh <state-dir> <comment-id>
set -eu

dir=${1:?usage: resolve-thread.sh <state-dir> <comment-id>}
comment_id=${2:?usage: resolve-thread.sh <state-dir> <comment-id>}
case "$comment_id" in
'' | *[!0-9]*)
	echo "resolve-thread: comment id must be numeric: $comment_id" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "resolve-thread: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

page_max=10
page=0
cursor=''
thread_id=''
while [ "$page" -lt "$page_max" ]; do
	page=$((page + 1))
	after=''
	[ -n "$cursor" ] && after=", after: \"$cursor\""
	result=$(gh api graphql \
		-f query="query { repository(owner: \"$owner\", name: \"$repo\") { pullRequest(number: $pr) { reviewThreads(first: 100$after) { pageInfo { hasNextPage endCursor } nodes { id comments(first: 1) { nodes { databaseId } } } } } } }" \
		--jq ".data.repository.pullRequest.reviewThreads | \"page \(.pageInfo.hasNextPage) \(.pageInfo.endCursor)\", (.nodes[] | select(.comments.nodes[0].databaseId == $comment_id) | \"thread \(.id)\")")
	thread_id=$(printf '%s\n' "$result" | sed -n 's/^thread //p' | head -n 1)
	[ -n "$thread_id" ] && break
	has_next=$(printf '%s\n' "$result" | sed -n 's/^page \([a-z]*\) .*/\1/p')
	cursor=$(printf '%s\n' "$result" | sed -n 's/^page [a-z]* //p')
	[ "$has_next" = "true" ] || break
done

[ -n "$thread_id" ] || {
	echo "resolve-thread: no thread starts with comment $comment_id ($page pages searched)" >&2
	exit 1
}

resolved=$(gh api graphql \
	-f query="mutation { resolveReviewThread(input: {threadId: \"$thread_id\"}) { thread { isResolved } } }" \
	--jq '.data.resolveReviewThread.thread.isResolved')
[ "$resolved" = "true" ] || {
	echo "resolve-thread: mutation did not resolve the thread" >&2
	exit 1
}
echo "resolve-thread: $comment_id resolved"
