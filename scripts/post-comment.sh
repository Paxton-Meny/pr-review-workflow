#!/bin/sh
# Post one status comment on the run's pull request. Body arrives on stdin.
# Usage: sh scripts/post-comment.sh <state-dir> <<'END' ... END
# The pull request comes from meta.txt, so the comment lands nowhere
# else; the body passes through redact.sh, and the first comment a run
# posts ends with the attribution line. Prints "post-comment: posted"
# and how many credentials were masked.
set -eu

dir=${1:?usage: post-comment.sh <state-dir>}
[ -f "$dir/meta.txt" ] || {
	echo "post-comment: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr" ] || {
	echo "post-comment: meta.txt in $dir is incomplete" >&2
	exit 1
}
here=$(dirname -- "$0")

tmp=$(mktemp "$dir/.comment.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"
grep -q '[^[:space:]]' "$tmp" || {
	echo "post-comment: empty body" >&2
	exit 1
}
credit=$(sh "$here/attribution.sh" "$dir")
[ -z "$credit" ] || printf '\n%s\n' "$credit" >>"$tmp"
masked=$(sh "$here/redact.sh" "$tmp")
gh pr comment "$pr" --repo "$owner/$repo" --body-file "$tmp" >/dev/null
echo "post-comment: posted, ${masked#redact: }"
