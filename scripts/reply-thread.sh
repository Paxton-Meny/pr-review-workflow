#!/bin/sh
# Reply to one inline review comment thread.
# Usage: sh scripts/reply-thread.sh <state-dir> <comment-id>   (body on stdin)
#        sh scripts/reply-thread.sh <state-dir> --addressed <finding-id>...
# --addressed replies "Addressed in <sha> (<subject>)." on each addressed
# finding's thread, citing the commit its record names, and only once
# every one of those commits is on the head push-branch.sh proved on the
# remote; a finding with no thread is named and skipped. A body
# on stdin may not claim a fix itself. Every body passes through
# redact.sh before it posts.
set -eu

usage='usage: reply-thread.sh <state-dir> <comment-id> | <state-dir> --addressed <finding-id>...'
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

post() {
	# post <comment-id> <body>: redact the body, reply, print the result
	tmp=$(mktemp "$dir/.reply.XXXXXX")
	printf '%s\n' "$2" >"$tmp"
	out=$(sh "$(dirname -- "$0")/redact.sh" "$tmp")
	masked=$(printf '%s\n' "$out" | sed -n 's/^redact: \([0-9]*\) masked$/\1/p')
	reply_id=$(gh api "repos/$owner/$repo/pulls/$pr/comments/$1/replies" \
		-F body=@"$tmp" --jq .id)
	rm -f "$tmp"
	tail=''
	[ "${masked:-0}" -eq 0 ] || tail=", $masked masked"
	echo "reply-thread: replied to $1 as $reply_id$tail"
}
trap 'rm -f "$dir"/.reply.*' EXIT

if [ "${2:-}" = --addressed ]; then
	shift 2
	[ "$#" -gt 0 ] || {
		echo "$usage" >&2
		exit 1
	}
	head_sha=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
	for id in "$@"; do
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
		commit=$(sed -n '/^---$/q; s/^commit: //p' "$record")
		[ -n "$commit" ] || {
			echo "reply-thread: $id records no commit" >&2
			exit 1
		}
		git -C "$dir/worktree" merge-base --is-ancestor "$commit" "$head_sha" 2>/dev/null || {
			echo "reply-thread: commit $commit is not on the pushed head $head_sha; push with push-branch.sh first" >&2
			exit 1
		}
	done
	for id in "$@"; do
		record="$dir/findings/$id"
		comment_id=$(sed -n '/^---$/q; s/^comment_id: //p' "$record")
		[ -n "$comment_id" ] || {
			echo "reply-thread: $id has no thread, nothing to reply to"
			continue
		}
		numeric "$comment_id"
		commit=$(sed -n '/^---$/q; s/^commit: //p' "$record")
		subject=$(git -C "$dir/worktree" log -1 --format=%s "$commit")
		post "$comment_id" "$(printf 'Addressed in %s (%s).' "$commit" "$subject")"
	done
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
	post "$comment_id" "$body"
fi
