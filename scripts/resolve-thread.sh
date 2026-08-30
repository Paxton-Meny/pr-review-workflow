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

thread_id=$(gh api graphql \
	-f query="query { repository(owner: \"$owner\", name: \"$repo\") { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { id comments(first: 1) { nodes { databaseId } } } } } } }" \
	--jq ".data.repository.pullRequest.reviewThreads.nodes[] | select(.comments.nodes[0].databaseId == $comment_id) | .id")
[ -n "$thread_id" ] || {
	echo "resolve-thread: no thread starts with comment $comment_id (only the first hundred threads are searched)" >&2
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
