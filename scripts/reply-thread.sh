#!/bin/sh
# Reply to one inline review comment thread. Body arrives on stdin.
# Usage: sh scripts/reply-thread.sh <state-dir> <comment-id>
set -eu

dir=${1:?usage: reply-thread.sh <state-dir> <comment-id>}
comment_id=${2:?usage: reply-thread.sh <state-dir> <comment-id>}
case "$comment_id" in
'' | *[!0-9]*)
	echo "reply-thread: comment id must be numeric: $comment_id" >&2
	exit 1
	;;
esac
[ -f "$dir/meta.txt" ] || {
	echo "reply-thread: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

reply_id=$(gh api "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
	-F body=@- --jq .id)
echo "reply-thread: replied to $comment_id as $reply_id"
