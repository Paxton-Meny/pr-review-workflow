#!/bin/sh
# Reply to one inline review comment thread. Body arrives on stdin.
# Usage: sh scripts/reply-thread.sh <state-dir> <comment-id>
# The body passes through redact.sh before it posts.
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

tmp=$(mktemp "$dir/.reply.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"
masked=$(sh "$(dirname -- "$0")/redact.sh" "$tmp" | sed -n 's/^redact: \([0-9]*\) masked$/\1/p')
reply_id=$(gh api "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
	-F body=@"$tmp" --jq .id)
tail=''
[ "${masked:-0}" -eq 0 ] || tail=", $masked masked"
echo "reply-thread: replied to $comment_id as $reply_id$tail"
