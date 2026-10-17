#!/bin/sh
# Reply to one inline review comment thread.
# Usage: sh scripts/reply-thread.sh <state-dir> <comment-id>   (body on stdin)
#        sh scripts/reply-thread.sh <state-dir> --addressed <finding-id>
# --addressed replies "Addressed in <sha> (<subject>)." on an addressed
# finding's thread, citing the commit its record names, and only once
# that commit is on the head push-branch.sh proved on the remote. A body
# on stdin may not claim a fix itself.
set -eu

usage='usage: reply-thread.sh <state-dir> <comment-id> | <state-dir> --addressed <finding-id>'
dir=${1:?$usage}
[ -f "$dir/meta.txt" ] || {
	echo "reply-thread: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")

numeric() {
	case "$1" in
	'' | *[!0-9]*)
		echo "reply-thread: comment id must be numeric: $1" >&2
		exit 1
		;;
	esac
}

if [ "${2:-}" = --addressed ]; then
	id=${3:?$usage}
	record="$dir/findings/$id"
	case "$id" in
	'' | *[!A-Za-z0-9]*) record= ;;
	esac
	[ -n "$record" ] && [ -f "$record" ] || {
		echo "reply-thread: unknown finding: $id" >&2
		exit 1
	}
	status=$(sed -n '/^---$/q; s/^status: //p' "$record")
	[ "$status" = addressed ] || {
		echo "reply-thread: $id is $status, not addressed; mark it with update-finding.sh first" >&2
		exit 1
	}
	comment_id=$(sed -n '/^---$/q; s/^comment_id: //p' "$record")
	commit=$(sed -n '/^---$/q; s/^commit: //p' "$record")
	numeric "$comment_id"
	[ -n "$commit" ] || {
		echo "reply-thread: $id records no commit" >&2
		exit 1
	}
	head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
	git -C "$dir/worktree" merge-base --is-ancestor "$commit" "$head_sha" 2>/dev/null || {
		echo "reply-thread: commit $commit is not on the pushed head $head_sha; push with push-branch.sh first" >&2
		exit 1
	}
	subject=$(git -C "$dir/worktree" log -1 --format=%s "$commit")
	body=$(printf 'Addressed in %s (%s).' "$commit" "$subject")
else
	comment_id=${2:?$usage}
	numeric "$comment_id"
	body=$(cat)
	case "$body" in
	'Addressed in '*)
		echo "reply-thread: a reply claiming a fix must use --addressed <finding-id>" >&2
		exit 1
		;;
	esac
fi

reply_id=$(printf '%s\n' "$body" | gh api "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
	-F body=@- --jq .id)
echo "reply-thread: replied to $comment_id as $reply_id"
