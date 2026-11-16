#!/bin/sh
# Record the converged review on the forge: a review with a body on the
# head the review covered, which is what a project's review gate looks
# for. An inline finding review has no body and a comment is not a
# review, so neither counts.
# Usage: sh scripts/record-review.sh <state-dir> [--approve]
# --approve makes the record an approval when the run's user is not the
# author; an author cannot approve their own pull request, so that case
# stays a review comment that says so.
# Runs once the review converges, whether or not this run merges: a pull
# request held, or merged by another tool, still carries its record.
# review-record.txt in the state directory keeps one "<event> <head>"
# line per record, so a rerun on the same head posts nothing unless
# --approve now asks for an approval where a comment stands.
# Exit 6: refused, writing nothing, because the ledger does not show a
# converged review; ledger-allows.sh's lines follow.
set -eu

dir=${1:?usage: record-review.sh <state-dir> [--approve]}
shift
approve=''
for arg in "$@"; do
	case "$arg" in
	--approve) approve=--approve ;;
	*)
		echo "record-review: unknown argument: $arg" >&2
		exit 1
		;;
	esac
done
[ -f "$dir/meta.txt" ] || {
	echo "record-review: no meta.txt in $dir" >&2
	exit 1
}
owner=$(sed -n 's/^owner //p' "$dir/meta.txt")
repo=$(sed -n 's/^repo //p' "$dir/meta.txt")
pr=$(sed -n 's/^pr //p' "$dir/meta.txt")
author=$(sed -n 's/^author //p' "$dir/meta.txt")
self=$(sed -n 's/^self_login //p' "$dir/meta.txt")
reviewed=$(sed -n 's/^reviewed_head //p' "$dir/meta.txt")
[ -n "$reviewed" ] || reviewed=$(sed -n 's/^head_sha //p' "$dir/meta.txt")
[ -n "$reviewed" ] || {
	echo "record-review: meta.txt names no head" >&2
	exit 1
}

here=$(dirname -- "$0")
rc=0
refused=$(sh "$here/ledger-allows.sh" "$dir") || rc=$?
case "$rc" in
0) ;;
3)
	echo "record-review: the ledger does not show a converged review"
	printf '%s\n' "$refused"
	exit 6
	;;
*) exit 1 ;;
esac

event=COMMENT
body='Review converged: no open findings.'
if [ "$approve" = "--approve" ] && [ -n "$self" ] && [ "$author" != "$self" ]; then
	event=APPROVE
elif [ "$approve" = "--approve" ]; then
	body="$body Authors cannot approve their own pull requests, so this review comment stands in for the approval."
fi

log="$dir/review-record.txt"
if grep -qx "APPROVE $reviewed" "$log" 2>/dev/null ||
	{ [ "$event" = COMMENT ] && grep -qx "COMMENT $reviewed" "$log" 2>/dev/null; }; then
	echo "record-review: already recorded on $reviewed"
	exit 0
fi

credit=$(sh "$here/attribution.sh" "$dir")
[ -z "$credit" ] || credit=$(printf '\n\n%s' "$credit")
rtmp=$(mktemp "$dir/.review.XXXXXX")
trap 'rm -f "$rtmp"' EXIT
printf '%s%s\n' "$body" "$credit" >"$rtmp"
gh api "repos/$owner/$repo/pulls/$pr/reviews" -f event="$event" \
	-f commit_id="$reviewed" -F body=@"$rtmp" >/dev/null
rm -f "$rtmp"
trap - EXIT
printf '%s %s\n' "$event" "$reviewed" >>"$log"
case "$event" in
APPROVE) echo "record-review: approval recorded on $reviewed" ;;
*) echo "record-review: review recorded on $reviewed" ;;
esac
